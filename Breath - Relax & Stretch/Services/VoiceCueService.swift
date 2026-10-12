import AVFoundation

final class VoiceCueService {
    static let shared = VoiceCueService()
    private let synthesizer = AVSpeechSynthesizer()
    private init() {}

    func speak(_ text: String) {
        guard UserDefaults.standard.bool(forKey: "voiceCuesEnabled") else { return }
        AppAudioSession.configureIfNeeded()
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate   = AVSpeechUtteranceDefaultSpeechRate * 0.85
        utterance.volume = 0.9
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
