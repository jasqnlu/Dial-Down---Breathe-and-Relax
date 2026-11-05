import AVFoundation
import Foundation
import Observation
import Speech

enum SpeechState: Equatable {
    case idle
    case listening
    case unavailable(SpeechUnavailableReason)
}

enum SpeechUnavailableReason: Equatable {
    case micDenied
    case speechDenied
    case localeUnsupported
    /// The on-device speech model isn't installed and couldn't be installed (e.g. offline).
    case assetUnavailable
    /// Microphone/audio engine or session setup failed.
    case audioFailed
}

/// On-device, offline speech-to-text with a live transcript. Uses the iOS 26
/// `SpeechAnalyzer`/`SpeechTranscriber` pipeline; audio never leaves the phone.
/// Press-and-hold usage: `start(locale:)` on press, `stop()` on release.
@MainActor @Observable
final class SpeechInput {
    private(set) var state: SpeechState = .idle
    private(set) var transcript: String = ""

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var resultsTask: Task<Void, Never>?
    @ObservationIgnored private var finalizedText = ""
    @ObservationIgnored private var volatileText = ""
    /// Bumped by every start/stop/cancel so a stale `start` can detect it was superseded.
    @ObservationIgnored private var generation = 0

    @ObservationIgnored /// Generation that activated the shared audio session; nil when we hold no activation.
    @ObservationIgnored private var sessionOwnerGeneration: Int?

    /// Pure precedence rule for why speech can't run: mic > speech > locale > asset.
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

    func start(locale: Locale) async {
        guard state != .listening else { return }
        teardown()
        generation += 1
        let myGeneration = generation
        transcript = ""
        finalizedText = ""
        volatileText = ""

        let micGranted = await AVAudioApplication.requestRecordPermission()
        let speechAuthorized = await Self.requestSpeechAuthorization()
        let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        guard myGeneration == generation else { return }

        if let reason = Self.reason(
            micGranted: micGranted,
            speechAuthorized: speechAuthorized,
            localeSupported: supportedLocale != nil,
            assetInstalled: true
        ) {
            state = .unavailable(reason)
            return
        }
        guard let supportedLocale else { return }

        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        // Models are installed once by the system; recognition itself is offline.
        // Already-installed models skip the download, so offline use needs no network.
        var assetInstalled = await AssetInventory.status(forModules: [transcriber]) == .installed
        if !assetInstalled {
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
                assetInstalled = true
            } catch {
                assetInstalled = false
            }
        }
        guard myGeneration == generation else { return }
        if let reason = Self.reason(
            micGranted: true, speechAuthorized: true, localeSupported: true, assetInstalled: assetInstalled
        ) {
            state = .unavailable(reason)
            return
        }

        // Local resources: owned here until published to self, torn down here if stale or failed.
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        var engine: AVAudioEngine?
        var task: Task<Void, Never>?
        func discardLocals() {
            if let engine {
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
            }
            continuation.finish()
            task?.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }

        do {
            let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            guard myGeneration == generation else { discardLocals(); return }

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: [])
            sessionOwnerGeneration = myGeneration

            let newEngine = AVAudioEngine()
            engine = newEngine
            try Self.installTap(on: newEngine, analyzerFormat: format, continuation: continuation)
            newEngine.prepare()
            try newEngine.start()

            task = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self else { return }
                        self.apply(text: String(result.text.characters), isFinal: result.isFinal)
                    }
                } catch {
                    // Recognition ended (cancel or failure); transcript keeps what we have.
                }
            }
            try await analyzer.start(inputSequence: stream)

            guard myGeneration == generation else {
                discardLocals()
                releaseSession(ifOwnedBy: myGeneration)
                return
            }
            self.engine = newEngine
            self.analyzer = analyzer
            self.inputContinuation = continuation
            self.resultsTask = task
            state = .listening
        } catch {
            discardLocals()
            guard myGeneration == generation else { return }
            releaseSession(ifOwnedBy: myGeneration)
            state = .unavailable(.audioFailed)
        }
    }

    /// Stops listening and returns everything transcribed so far.
    @discardableResult
    func stop() -> String {
        generation += 1
        let text = currentText
        let analyzer = analyzer
        let continuation = inputContinuation
        stopAudio()
        continuation?.finish()
        resultsTask?.cancel()
        resultsTask = nil
        self.analyzer = nil
        self.inputContinuation = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        if state == .listening { state = .idle }
        transcript = text
        return text
    }

    func cancel() {
        generation += 1
        teardown()
        transcript = ""
        finalizedText = ""
        volatileText = ""
        state = .idle
    }

    // MARK: - Private

    private var currentText: String {
        (finalizedText + volatileText).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func apply(text: String, isFinal: Bool) {
        if isFinal {
            finalizedText += text
            volatileText = ""
        } else {
            volatileText = text
        }
        transcript = currentText
    }

    private func teardown() {
        let analyzer = analyzer
        stopAudio()
        inputContinuation?.finish()
        inputContinuation = nil
        resultsTask?.cancel()
        resultsTask = nil
        self.analyzer = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
    }

    private func stopAudio() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        releaseSession(ifOwnedBy: nil)
    }

    /// Deactivates the session if we hold it. A stale start passes its own generation so it
    /// can't deactivate a session a newer start has since activated.
    private func releaseSession(ifOwnedBy generation: Int?) {
        guard let owner = sessionOwnerGeneration, generation == nil || generation == owner else { return }
        sessionOwnerGeneration = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Built outside the main actor: the tap block runs on the realtime audio thread.
    private nonisolated static func installTap(
        on engine: AVAudioEngine,
        analyzerFormat: AVAudioFormat?,
        continuation: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let converter: AVAudioConverter? = {
            guard let analyzerFormat, analyzerFormat != inputFormat else { return nil }
            return AVAudioConverter(from: inputFormat, to: analyzerFormat)
        }()

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let converter, let analyzerFormat else {
                continuation.yield(AnalyzerInput(buffer: buffer))
                return
            }
            let ratio = analyzerFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }
            var consumed = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil, converted.frameLength > 0 {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
    }
}
