import Testing
import AVFoundation
import Foundation
@testable import BreathRelaxStretch

// Session cues are synthesized and played through the app's audio session
// (not AudioServicesPlaySystemSound, which the silent switch always mutes),
// so each cue has to render to audio AVAudioPlayer can actually load.
struct SoundCueServiceTests {

    @Test(arguments: SoundCue.allCases)
    func cueRendersAWellFormedWAV(cue: SoundCue) {
        let data = cue.wavData()
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")

        // 44-byte header, then 16-bit mono samples for every note.
        let expectedSamples = cue.notes.reduce(0) { $0 + Int($1.duration * Double(SoundCue.sampleRate)) }
        #expect(data.count == 44 + expectedSamples * 2)
    }

    @Test(arguments: SoundCue.allCases)
    func cueLoadsInAVAudioPlayerAtItsAuthoredLength(cue: SoundCue) throws {
        let player = try AVAudioPlayer(data: cue.wavData(), fileTypeHint: AVFileType.wav.rawValue)
        let expected = cue.notes.reduce(0) { $0 + $1.duration }
        #expect(abs(player.duration - expected) < 0.01)
        #expect(player.numberOfChannels == 1)
    }

    @Test(arguments: SoundCue.allCases)
    func cueIsAudibleAndNeverClips(cue: SoundCue) {
        let data = cue.wavData()
        let samples = stride(from: 44, to: data.count, by: 2).map { i in
            Int16(littleEndian: data.subdata(in: i..<i + 2).withUnsafeBytes { $0.load(as: Int16.self) })
        }
        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        #expect(peak > Int(Int16.max) / 20)
        #expect(peak < Int(Int16.max))
        // Starts and ends at silence, so a cue never clicks.
        #expect(abs(Int(samples.first ?? 0)) < 200)
        #expect(abs(Int(samples.last ?? 0)) < 200)
    }

    @Test func appAudioSessionIgnoresTheSilentSwitchAndMixesWithOtherAudio() {
        AppAudioSession.configureIfNeeded()
        let session = AVAudioSession.sharedInstance()
        #expect(session.category == .playback)
        #expect(session.categoryOptions.contains(.mixWithOthers))
    }
}
