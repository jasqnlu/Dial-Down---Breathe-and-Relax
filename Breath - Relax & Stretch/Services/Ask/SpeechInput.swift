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

    /// Pure precedence rule for why speech can't run. Mic is checked first.
    nonisolated static func reason(
        micGranted: Bool,
        speechAuthorized: Bool,
        localeSupported: Bool
    ) -> SpeechUnavailableReason? {
        if !micGranted { return .micDenied }
        if !speechAuthorized { return .speechDenied }
        if !localeSupported { return .localeUnsupported }
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
            localeSupported: supportedLocale != nil
        ) {
            state = .unavailable(reason)
            return
        }
        guard let supportedLocale else { return }

        do {
            let transcriber = SpeechTranscriber(
                locale: supportedLocale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            // Models are downloaded once by the system; recognition itself is offline.
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            guard myGeneration == generation else { return }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: [])

            let engine = AVAudioEngine()
            try Self.installTap(on: engine, analyzerFormat: format, continuation: continuation)
            engine.prepare()
            try engine.start()

            self.engine = engine
            self.analyzer = analyzer
            self.inputContinuation = continuation
            resultsTask = Task { [weak self] in
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
            guard myGeneration == generation else { return }
            state = .listening
        } catch {
            guard myGeneration == generation else { return }
            teardown()
            state = .idle
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
