import AVFoundation
import Foundation
import Observation
import Speech

enum SpeechState: Equatable {
    case idle
    case preparing
    case listening
    case unavailable(SpeechUnavailableReason)
}

enum SpeechUnavailableReason: Equatable {
    case micDenied
    case speechDenied
    case localeUnsupported
    case assetUnavailable
    case audioFailed
}

/// Offline speech input with live partial results. Audio setup and teardown run
/// on a serial background queue so the chat stays tappable if Core Audio stalls.
@MainActor @Observable
final class SpeechInput {
    private(set) var state: SpeechState = .idle
    private(set) var transcript = ""

    @ObservationIgnored private var capture: SpeechAudioCapture?
    @ObservationIgnored private var preparationTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pendingPermissionRequests = 0

    var isRequestingPermission: Bool { pendingPermissionRequests > 0 }

    nonisolated static func reason(
        micGranted: Bool,
        speechAuthorized: Bool,
        localeSupported: Bool,
        assetInstalled: Bool
    ) -> SpeechUnavailableReason? {
        if !micGranted { return .micDenied }
        if !speechAuthorized { return .speechDenied }
        if !localeSupported { return .localeUnsupported }
        if !assetInstalled { return .assetUnavailable }
        return nil
    }

    isolated deinit {
        teardown()
    }

    nonisolated static var permissionsUndetermined: Bool {
        AVAudioApplication.shared.recordPermission == .undetermined
            || SFSpeechRecognizer.authorizationStatus() == .notDetermined
    }

    func permissionOutcome() async -> SpeechUnavailableReason? {
        let (micGranted, speechAuthorized) = await requestPermissions()
        return Self.reason(micGranted: micGranted, speechAuthorized: speechAuthorized,
                           localeSupported: true, assetInstalled: true)
    }

    func start(locale: Locale) async {
        guard state != .preparing, state != .listening else { return }
        teardown()
        generation += 1
        let myGeneration = generation
        transcript = ""
        state = .preparing

        let (micGranted, speechAuthorized) = await requestPermissions()
        guard myGeneration == generation else { return }
        if let reason = Self.reason(micGranted: micGranted, speechAuthorized: speechAuthorized,
                                    localeSupported: true, assetInstalled: true) {
            state = .unavailable(reason)
            return
        }

        // A local recognizer starts without an asset download. Keep audio on
        // the phone, and report unsupported locales instead of waiting forever.
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.supportsOnDeviceRecognition else {
            state = .unavailable(.localeUnsupported)
            return
        }
        guard recognizer.isAvailable else {
            state = .unavailable(.assetUnavailable)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true

        let capture = SpeechAudioCapture()
        self.capture = capture
        preparationTimeoutTask?.cancel()
        preparationTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self,
                  self.generation == myGeneration, self.state == .preparing else { return }
            self.generation += 1
            self.teardown()
            self.state = .unavailable(.audioFailed)
        }

        do {
            try await capture.start(request: SpeechRequestBox(request),
                                    recognizer: SpeechRecognizerBox(recognizer)) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == myGeneration else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil {
                        self.generation += 1
                        self.teardown()
                        self.state = .unavailable(.audioFailed)
                    }
                }
            }
            guard myGeneration == generation else { return }
            preparationTimeoutTask?.cancel()
            preparationTimeoutTask = nil
            state = .listening
        } catch {
            guard myGeneration == generation else { return }
            teardown()
            state = .unavailable(.audioFailed)
        }
    }

    @discardableResult
    func stop() -> String {
        generation += 1
        preparationTimeoutTask?.cancel()
        preparationTimeoutTask = nil
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        teardown()
        state = .idle
        return text
    }

    func cancel() {
        generation += 1
        preparationTimeoutTask?.cancel()
        preparationTimeoutTask = nil
        teardown()
        transcript = ""
        state = .idle
    }

    private func teardown() {
        preparationTimeoutTask?.cancel()
        preparationTimeoutTask = nil
        capture?.stop()
        capture = nil
    }

    private func requestPermissions() async -> (mic: Bool, speech: Bool) {
        pendingPermissionRequests += 1
        defer { pendingPermissionRequests -= 1 }
        let micGranted = await AVAudioApplication.requestRecordPermission()
        let speechAuthorized = await Self.requestSpeechAuthorization()
        return (micGranted, speechAuthorized)
    }

    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

/// All AVAudioSession and AVAudioEngine operations are serialized off the main
/// actor. A queued stop finishes before a later recording can activate audio.
private final class SpeechRequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest

    init(_ request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }
}

private final class SpeechRecognizerBox: @unchecked Sendable {
    let recognizer: SFSpeechRecognizer

    init(_ recognizer: SFSpeechRecognizer) {
        self.recognizer = recognizer
    }
}

private enum SpeechCaptureError: Error {
    case noInput
    case invalidInputFormat
}

private final class SpeechAudioCapture: @unchecked Sendable {
    private static let queue = DispatchQueue(label: "com.dialdown.speech.audio")
    private var engine: AVAudioEngine?
    private var request: SpeechRequestBox?
    private var recognizer: SpeechRecognizerBox?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var ownsSession = false

    func start(
        request: SpeechRequestBox,
        recognizer: SpeechRecognizerBox,
        resultHandler: @escaping @Sendable (SFSpeechRecognitionResult?, Error?) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { result in
            Self.queue.async {
                var newEngine: AVAudioEngine?
                var tapInstalled = false
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.record, mode: .measurement, options: [])
                    try session.setActive(true, options: [])
                    self.ownsSession = true
                    guard session.isInputAvailable else { throw SpeechCaptureError.noInput }

                    let engine = AVAudioEngine()
                    newEngine = engine
                    let input = engine.inputNode
                    let format = input.outputFormat(forBus: 0)
                    guard format.sampleRate > 0, format.channelCount > 0 else {
                        throw SpeechCaptureError.invalidInputFormat
                    }
                    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                        request.request.append(buffer)
                    }
                    tapInstalled = true
                    engine.prepare()
                    try engine.start()
                    self.engine = engine
                    self.request = request
                    self.recognizer = recognizer
                    self.recognitionTask = recognizer.recognizer.recognitionTask(
                        with: request.request, resultHandler: resultHandler
                    )
                    result.resume()
                } catch {
                    if tapInstalled { newEngine?.inputNode.removeTap(onBus: 0) }
                    newEngine?.stop()
                    self.deactivateSession()
                    result.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        Self.queue.async {
            if let engine = self.engine {
                engine.stop()
                engine.inputNode.removeTap(onBus: 0)
                self.engine = nil
            }
            self.request?.request.endAudio()
            self.recognitionTask?.cancel()
            self.recognitionTask = nil
            self.request = nil
            self.recognizer = nil
            self.deactivateSession()
        }
    }

    private func deactivateSession() {
        guard ownsSession else { return }
        ownsSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
