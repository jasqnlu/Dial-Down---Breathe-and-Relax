import AVFoundation

/// The app's shared audio session setup. `.playback` is what makes cue sounds
/// and voice cues audible with the ring/silent switch set to silent (the
/// default `.soloAmbient` category is muted by it). `.mixWithOthers` keeps the
/// user's own music or podcast playing underneath instead of stopping it.
enum AppAudioSession {
    private static var isConfigured = false

    static func configureIfNeeded() {
        guard !isConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            isConfigured = true
        } catch {
            // Left unconfigured so the next cue retries; sounds fall back to
            // the default category (muted by the silent switch) meanwhile.
            print("AppAudioSession: configure failed: \(error)")
        }
    }
}

/// The short non-verbal cues a session plays.
enum SoundCue: CaseIterable {
    case tick        // breathing metronome
    case cueBeep     // cue reminder / phase change
    case transition  // exercise advance
    case complete    // session done

    /// One sine note: frequency in Hz, duration in seconds.
    typealias Note = (frequency: Double, duration: Double)

    var notes: [Note] {
        switch self {
        case .tick:       return [(1000, 0.03)]
        case .cueBeep:    return [(660, 0.11)]
        case .transition: return [(523.25, 0.09), (783.99, 0.14)]
        case .complete:   return [(523.25, 0.13), (659.25, 0.13), (783.99, 0.30)]
        }
    }

    var gain: Double {
        switch self {
        case .tick: return 0.25
        case .cueBeep, .transition: return 0.45
        case .complete: return 0.5
        }
    }

    static let sampleRate = 44_100

    /// The cue rendered as a 16-bit mono WAV file. Synthesized rather than
    /// bundled, so there are no audio assets to license or ship.
    func wavData() -> Data {
        var samples: [Int16] = []
        for note in notes {
            let count = Int(note.duration * Double(Self.sampleRate))
            let attack = max(1, Int(0.004 * Double(Self.sampleRate)))
            for i in 0..<count {
                let t = Double(i) / Double(Self.sampleRate)
                // Short linear attack and an exponential decay to silence, so
                // notes neither click on nor cut off abruptly.
                let fadeIn = min(1, Double(i) / Double(attack))
                let decay = exp(-4 * Double(i) / Double(count))
                let fadeOut = min(1, Double(count - i) / Double(attack))
                let value = sin(2 * .pi * note.frequency * t) * fadeIn * decay * fadeOut * gain
                samples.append(Int16(value * Double(Int16.max)))
            }
        }

        let dataSize = UInt32(samples.count * MemoryLayout<Int16>.size)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))                           // fmt chunk size
        append(UInt16(1))                            // PCM
        append(UInt16(1))                            // mono
        append(UInt32(Self.sampleRate))
        append(UInt32(Self.sampleRate * 2))          // byte rate
        append(UInt16(2))                            // block align
        append(UInt16(16))                           // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(dataSize)
        for sample in samples { append(sample) }
        return data
    }
}

/// Plays `SoundCue`s through the app's audio session. Replaces
/// `AudioServicesPlaySystemSound`, which iOS always mutes with the silent
/// switch regardless of the session category.
final class SoundCueService {
    static let shared = SoundCueService()
    private var players: [SoundCue: AVAudioPlayer] = [:]
    private init() {}

    /// Builds every player up front so the first cue of a session isn't late.
    func prepare() {
        AppAudioSession.configureIfNeeded()
        for cue in SoundCue.allCases { _ = player(for: cue) }
    }

    func play(_ cue: SoundCue) {
        AppAudioSession.configureIfNeeded()
        guard let player = player(for: cue) else { return }
        player.currentTime = 0
        player.play()
    }

    private func player(for cue: SoundCue) -> AVAudioPlayer? {
        if let existing = players[cue] { return existing }
        guard let player = try? AVAudioPlayer(data: cue.wavData(), fileTypeHint: AVFileType.wav.rawValue) else {
            return nil
        }
        player.prepareToPlay()
        players[cue] = player
        return player
    }
}
