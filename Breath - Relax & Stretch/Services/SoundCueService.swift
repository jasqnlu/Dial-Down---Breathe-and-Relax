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
    case breatheIn   // Breathe tab: inhale (rising)
    case breatheOut  // Breathe tab: exhale (falling)
    case breatheHold // Breathe tab: either hold (steady, pitched between the two)

    /// One sine note gliding from `frequency` to `endFrequency` (Hz) over
    /// `duration` seconds. Equal frequencies give a steady tone.
    typealias Note = (frequency: Double, endFrequency: Double, duration: Double)

    private static func tone(_ frequency: Double, _ duration: Double) -> Note {
        (frequency, frequency, duration)
    }

    var notes: [Note] {
        switch self {
        case .tick:        return [Self.tone(1000, 0.03)]
        case .cueBeep:     return [Self.tone(660, 0.11)]
        case .transition:  return [Self.tone(523.25, 0.09), Self.tone(783.99, 0.14)]
        case .complete:    return [Self.tone(523.25, 0.13), Self.tone(659.25, 0.13), Self.tone(783.99, 0.30)]
        // G4 up to C5, C5 down to G4, and A4 in between.
        case .breatheIn:   return [(392.00, 523.25, 0.6)]
        case .breatheOut:  return [(523.25, 392.00, 0.6)]
        case .breatheHold: return [Self.tone(440.00, 0.5)]
        }
    }

    var gain: Double {
        switch self {
        case .tick: return 0.25
        case .cueBeep, .transition: return 0.45
        case .complete: return 0.5
        case .breatheIn, .breatheOut, .breatheHold: return 0.32
        }
    }

    /// Breathing cues add a quiet octave and ring out longer, so they sound
    /// like a soft bell rather than a beep.
    private var octaveLevel: Double { isBreathing ? 0.25 : 0 }
    private var decayRate: Double { isBreathing ? 3 : 4 }
    private var isBreathing: Bool {
        switch self {
        case .breatheIn, .breatheOut, .breatheHold: return true
        default: return false
        }
    }

    static let sampleRate = 44_100

    /// The cue rendered as a 16-bit mono WAV file. Synthesized rather than
    /// bundled, so there are no audio assets to license or ship.
    func wavData() -> Data {
        var samples: [Int16] = []
        for note in notes {
            let count = Int(note.duration * Double(Self.sampleRate))
            let attack = max(1, Int((isBreathing ? 0.02 : 0.004) * Double(Self.sampleRate)))
            var phase = 0.0
            for i in 0..<count {
                // Phase accumulates so a gliding pitch stays continuous.
                let progress = Double(i) / Double(count)
                let frequency = note.frequency + (note.endFrequency - note.frequency) * progress
                phase += 2 * .pi * frequency / Double(Self.sampleRate)
                // Short linear attack and an exponential decay to silence, so
                // notes neither click on nor cut off abruptly.
                let fadeIn = min(1, Double(i) / Double(attack))
                let decay = exp(-decayRate * progress)
                let fadeOut = min(1, Double(count - i) / Double(attack))
                let wave = (sin(phase) + octaveLevel * sin(2 * phase)) / (1 + octaveLevel)
                let value = wave * fadeIn * decay * fadeOut * gain
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

/// The Breathe tab's phase sounds. On by default; Settings → Session →
/// Breathing Sounds turns them off.
enum BreathingSounds {
    static let storageKey = "breathingSoundsEnabled"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: storageKey) as? Bool ?? true
    }

    static func cue(for phase: BreathPhase) -> SoundCue {
        switch phase {
        case .inhale:       return .breatheIn
        case .exhale:       return .breatheOut
        case .hold, .hold2: return .breatheHold
        }
    }

    static func play(for phase: BreathPhase) {
        guard isEnabled() else { return }
        SoundCueService.shared.play(cue(for: phase))
    }
}
