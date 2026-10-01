import Testing
import Foundation
import SwiftData
@testable import BreathRelaxStretch

@MainActor
struct LocalDataEraserTests {

    private let suite = "LocalDataEraserTests.\(UUID().uuidString)"

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Exercise.self, FlexibilityCheckIn.self, PendingSyncOp.self,
                             Routine.self, Session.self, UserProfile.self])
        let container = try ModelContainer(
            for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func exercise(_ name: String, seedID: String?) -> Exercise {
        let e = Exercise(name: name, type: .stretch, targetBodyParts: [],
                         durationSeconds: 30, difficulty: 1, instructions: [])
        e.seedID = seedID
        return e
    }

    private func tempDocuments() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func eraseRemovesAllUserRowsAndCustomExercises() throws {
        let context = try makeContext()
        context.insert(Session(routineID: UUID()))
        context.insert(Routine(name: "Mine"))
        context.insert(UserProfile(profileID: "p", displayName: "Ada"))
        context.insert(FlexibilityCheckIn(test: .toeTouch, level: 1))
        context.insert(PendingSyncOp(entityType: .session, entityID: UUID(), opType: .upsert))
        context.insert(exercise("My custom stretch", seedID: nil))
        try context.save()

        let defaults = try #require(UserDefaults(suiteName: suite))
        try LocalDataEraser.eraseAll(context: context, defaults: defaults,
                                     domainName: suite, documentsDirectory: try tempDocuments())

        #expect(try context.fetchCount(FetchDescriptor<Session>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Routine>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<UserProfile>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<FlexibilityCheckIn>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PendingSyncOp>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 0)
    }

    @Test func eraseKeepsSeedCatalogAndItsVersionCounters() throws {
        let context = try makeContext()
        context.insert(exercise("Seed stretch", seedID: "seed-1"))
        try context.save()

        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(7, forKey: "seedDataVersion")
        defaults.set(7, forKey: "notifiedSeedVersion")
        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set(["neck"], forKey: "bodymap.markedRegions")
        defaults.set("Ada", forKey: "auth.displayName")

        try LocalDataEraser.eraseAll(context: context, defaults: defaults,
                                     domainName: suite, documentsDirectory: try tempDocuments())

        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 1)
        #expect(defaults.integer(forKey: "seedDataVersion") == 7)
        #expect(defaults.integer(forKey: "notifiedSeedVersion") == 7)
        #expect(defaults.object(forKey: "bodymap.markedRegions") == nil)
        #expect(defaults.object(forKey: "auth.displayName") == nil)
        // Explicitly false (not just absent) so @AppStorage observers fire.
        #expect(defaults.object(forKey: "hasCompletedOnboarding") as? Bool == false)
    }

    @Test func eraseDeletesTheProfilePhotoAndToleratesItMissing() throws {
        let docs = try tempDocuments()
        let photo = docs.appendingPathComponent("profile_photo.jpg")
        try Data([0xFF]).write(to: photo)
        let defaults = try #require(UserDefaults(suiteName: suite))

        try LocalDataEraser.eraseAll(context: try makeContext(), defaults: defaults,
                                     domainName: suite, documentsDirectory: docs)
        #expect(!FileManager.default.fileExists(atPath: photo.path))

        // Second run: no photo present, so it must not throw.
        try LocalDataEraser.eraseAll(context: try makeContext(), defaults: defaults,
                                     domainName: suite, documentsDirectory: docs)
    }
}
