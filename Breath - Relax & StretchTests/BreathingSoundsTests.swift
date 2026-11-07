import Testing
import Foundation
@testable import BreathRelaxStretch

// The Breathe tab marks each phase with its own soft tone: rising for inhale,
// falling for exhale, steady for holds. On unless turned off in Settings.
struct BreathingSoundsTests {

    @Test func eachPhaseHasItsOwnCue() {
        #expect(BreathingSounds.cue(for: .inhale) == .breatheIn)
        #expect(BreathingSounds.cue(for: .exhale) == .breatheOut)
        #expect(BreathingSounds.cue(for: .hold) == .breatheHold)
        #expect(BreathingSounds.cue(for: .hold2) == .breatheHold)
    }

    @Test func inhaleRisesExhaleFallsHoldStaysLevel() {
        let inhale = Self.pitchChange(of: .breatheIn)
        let exhale = Self.pitchChange(of: .breatheOut)
        let hold = Self.pitchChange(of: .breatheHold)
        #expect(inhale > 1.1, "inhale should rise, got ×\(inhale)")
        #expect(exhale < 0.9, "exhale should fall, got ×\(exhale)")
        #expect(abs(hold - 1) < 0.05, "hold should stay level, got ×\(hold)")
    }

    @Test func holdIsPitchedBetweenInhaleAndExhale() {
        let hold = SoundCue.breatheHold.notes[0].frequency
        let low = SoundCue.breatheIn.notes[0].frequency
        let high = SoundCue.breatheIn.notes[0].endFrequency
        #expect(low < hold && hold < high)
    }

    @Test func onByDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: "BreathingSoundsTests.default"))
        defaults.removePersistentDomain(forName: "BreathingSoundsTests.default")
        #expect(BreathingSounds.isEnabled(in: defaults))
    }

    @Test func turningItOffInSettingsSilencesIt() throws {
        let defaults = try #require(UserDefaults(suiteName: "BreathingSoundsTests.off"))
        defaults.set(false, forKey: BreathingSounds.storageKey)
        #expect(!BreathingSounds.isEnabled(in: defaults))
        defaults.removePersistentDomain(forName: "BreathingSoundsTests.off")
    }

    /// Zero-crossing rate late in the cue divided by the rate early on:
    /// above 1 means the pitch rose, below 1 that it fell.
    private static func pitchChange(of cue: SoundCue) -> Double {
        let data = cue.wavData()
        let samples = stride(from: 44, to: data.count, by: 2).map { i in
            Int16(littleEndian: data.subdata(in: i..<i + 2).withUnsafeBytes { $0.load(as: Int16.self) })
        }
        func crossings(_ from: Double, _ to: Double) -> Double {
            let a = Int(Double(samples.count) * from), b = Int(Double(samples.count) * to)
            let window = samples[a..<b]
            return Double(zip(window, window.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count)
        }
        return crossings(0.6, 0.8) / crossings(0.02, 0.22)
    }
}
