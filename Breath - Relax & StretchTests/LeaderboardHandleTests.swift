import Testing
import Foundation
@testable import BreathRelaxStretch

// .serialized: the preference-cache tests read and write the process-global
// LeaderboardPreference (UserDefaults.standard); run concurrently, one test's
// "Calm Otter 4821" lands between the other's write and its nil expectation.
@Suite(.serialized)
struct LeaderboardHandleTests {

    /// Deterministic RNG (SplitMix64) so generation tests never flake.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    @Test func generatedHandlesAreAdjectiveAnimalNumberAndAlwaysValid() {
        var generator = SeededGenerator(state: 42)
        for _ in 0..<500 {
            let handle = LeaderboardHandle.generate(using: &generator)
            let parts = handle.split(separator: " ")
            #expect(parts.count == 3, "unexpected shape: \(handle)")
            #expect(LeaderboardHandle.adjectives.contains(String(parts[0])))
            #expect(LeaderboardHandle.animals.contains(String(parts[1])))
            let number = Int(parts[2])
            #expect(number != nil && (1000...9999).contains(number!))
            #expect(LeaderboardHandle.isValid(handle))
        }
    }

    @Test func sameSeedProducesTheSameHandle() {
        var a = SeededGenerator(state: 7)
        var b = SeededGenerator(state: 7)
        #expect(LeaderboardHandle.generate(using: &a) == LeaderboardHandle.generate(using: &b))
    }

    @Test func handlesVaryAcrossDraws() {
        var generator = SeededGenerator(state: 1)
        let handles = Set((0..<50).map { _ in LeaderboardHandle.generate(using: &generator) })
        #expect(handles.count > 40)
    }

    @Test func validityMatchesTheDatabaseCheckConstraint() {
        // leaderboard.handle: char_length between 2 and 32.
        #expect(!LeaderboardHandle.isValid(""))
        #expect(!LeaderboardHandle.isValid("a"))
        #expect(LeaderboardHandle.isValid("ab"))
        #expect(LeaderboardHandle.isValid(String(repeating: "a", count: 32)))
        #expect(!LeaderboardHandle.isValid(String(repeating: "a", count: 33)))
    }

    @Test func longestPossibleGeneratedHandleFitsTheColumn() {
        let longest = (LeaderboardHandle.adjectives.map(\.count).max() ?? 0)
            + 1 + (LeaderboardHandle.animals.map(\.count).max() ?? 0) + 1 + 4
        #expect(longest <= LeaderboardHandle.lengthRange.upperBound)
    }

    // MARK: - Preference cache

    @Test func preferenceRoundTripsAndClears() {
        let saved = LeaderboardPreference.handle
        defer { LeaderboardPreference.handle = saved }

        LeaderboardPreference.handle = "Calm Otter 4821"
        #expect(LeaderboardPreference.handle == "Calm Otter 4821")
        #expect(LeaderboardPreference.isOptedIn)

        LeaderboardPreference.clear()
        #expect(LeaderboardPreference.handle == nil)
        #expect(!LeaderboardPreference.isOptedIn)
    }

    @Test func preferenceRejectsAnInvalidHandleInsteadOfStoringIt() {
        let saved = LeaderboardPreference.handle
        defer { LeaderboardPreference.handle = saved }

        LeaderboardPreference.handle = "Calm Otter 4821"
        LeaderboardPreference.handle = "x"   // too short → treated as opting out
        #expect(LeaderboardPreference.handle == nil)
    }
}
