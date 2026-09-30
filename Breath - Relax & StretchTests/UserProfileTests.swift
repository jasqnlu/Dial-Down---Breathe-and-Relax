import Testing
import SwiftData
import Foundation
@testable import BreathRelaxStretch

// Covers UserProfile.dedupe(in:), the defensive merge pass that folds
// duplicate profiles (possible if CloudKit sync produces two rows before a
// merge resolves) into a single survivor instead of leaving stats split
// non-deterministically across rows.
struct UserProfileTests {

    private func makeContext() -> ModelContext {
        let container = try! ModelContainer(
            for: UserProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func dedupeNoOpsWithZeroOrOneProfile() {
        let context = makeContext()
        UserProfile.dedupe(in: context)

        let solo = UserProfile(profileID: "a", displayName: "Solo")
        context.insert(solo)
        try? context.save()
        UserProfile.dedupe(in: context)

        let all = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        #expect(all.count == 1)
    }

    @Test func dedupeMergesStatsIntoSurvivor() throws {
        let context = makeContext()

        let first = UserProfile(profileID: "a", displayName: "First")
        first.totalPoints = 100
        first.totalMinutes = 30
        first.streak = 3
        first.badges = ["First Breath"]

        let second = UserProfile(profileID: "a", displayName: "First")
        second.totalPoints = 50
        second.totalMinutes = 20
        second.streak = 7
        second.badges = ["Streak Starter"]

        context.insert(first)
        context.insert(second)
        try? context.save()

        UserProfile.dedupe(in: context)

        let all = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        #expect(all.count == 1)
        let survivor = try #require(all.first)
        #expect(survivor.totalPoints == 150)
        #expect(survivor.totalMinutes == 50)
        #expect(survivor.streak == 7)
        #expect(Set(survivor.badges) == ["First Breath", "Streak Starter"])
    }

    @Test func dedupeKeepsLatestLastSessionDate() {
        let context = makeContext()

        let older = UserProfile(profileID: "a", displayName: "A")
        older.lastSessionDate = Date(timeIntervalSince1970: 1000)

        let newer = UserProfile(profileID: "a", displayName: "A")
        newer.lastSessionDate = Date(timeIntervalSince1970: 2000)

        context.insert(older)
        context.insert(newer)
        try? context.save()

        UserProfile.dedupe(in: context)

        let all = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        #expect(all.first?.lastSessionDate == Date(timeIntervalSince1970: 2000))
    }

    private func remote(points: Int = 0, streak: Int = 0, minutes: Int = 0,
                        spent: Int? = nil, tokens: Int? = nil) -> RemoteProfile {
        RemoteProfile(id: "a", displayName: "A", totalPoints: points, streak: streak,
                      totalMinutes: minutes, lastSessionAt: nil,
                      pointsSpent: spent, streakFreezeTokens: tokens)
    }

    @Test func dedupeSumsPointsSpentAndTakesMaxTokensCapped() throws {
        let context = makeContext()
        let a = UserProfile(profileID: "a", displayName: "A")
        a.pointsSpent = 150; a.streakFreezeTokens = 2
        let b = UserProfile(profileID: "a", displayName: "A")
        b.pointsSpent = 300; b.streakFreezeTokens = 3
        context.insert(a); context.insert(b)
        try? context.save()

        UserProfile.dedupe(in: context)

        let survivor = try #require((try? context.fetch(FetchDescriptor<UserProfile>()))?.first)
        #expect(survivor.pointsSpent == 450)
        #expect(survivor.streakFreezeTokens == 3)
    }

    @Test func mergeRemoteTakesMaxOfMonotonicFields() {
        let p = UserProfile(profileID: "a", displayName: "A")
        p.totalPoints = 500; p.pointsSpent = 150; p.streak = 4; p.totalMinutes = 10
        p.mergeRemote(remote(points: 300, streak: 9, minutes: 5, spent: 300))
        #expect(p.totalPoints == 500)
        #expect(p.streak == 9)
        #expect(p.totalMinutes == 10)
        #expect(p.pointsSpent == 300)
    }

    @Test func mergeRemoteDoesNotResurrectSpentSaversOnDeviceWithProgress() {
        let p = UserProfile(profileID: "a", displayName: "A")
        p.totalPoints = 500; p.streak = 4; p.streakFreezeTokens = 0   // user used their saver
        p.mergeRemote(remote(points: 500, streak: 4, tokens: 2))       // stale remote count
        #expect(p.streakFreezeTokens == 0)
    }

    @Test func mergeRemoteAdoptsSaversOnFreshDevice() {
        let p = UserProfile(profileID: "a", displayName: "A")
        p.mergeRemote(remote(points: 600, streak: 5, spent: 300, tokens: 2))
        #expect(p.streakFreezeTokens == 2)
        #expect(p.pointsSpent == 300)
        #expect(p.spendablePoints == 300)
    }

    @Test func mergeRemoteClampsAdoptedSaversToCap() {
        let p = UserProfile(profileID: "a", displayName: "A")
        p.mergeRemote(remote(tokens: 99))
        #expect(p.streakFreezeTokens == GamificationService.maxSavers)
    }

    @Test func mergeRemoteToleratesMissingSaverFields() {
        let p = UserProfile(profileID: "a", displayName: "A")
        p.pointsSpent = 150; p.streakFreezeTokens = 1
        p.mergeRemote(remote(points: 400))
        #expect(p.pointsSpent == 150)
        #expect(p.streakFreezeTokens == 1)
    }
}
