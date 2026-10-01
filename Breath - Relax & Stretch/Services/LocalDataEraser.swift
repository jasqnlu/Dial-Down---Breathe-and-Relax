import Foundation
import SwiftData
import os

/// Returns the device to a fresh-install state after Delete Account
/// succeeds (decision 2026-10-01: deleting the account also wipes local
/// data). Run only *after* the server confirmed, never on failure.
///
/// Keeps the bundled seed exercise catalog (content, not user data; seed
/// rows have a non-nil `seedID`) and the two counters describing which
/// catalog version is installed, so the next launch neither re-runs seed
/// migrations nor greets the user with "New Content Added".
///
/// Best-effort: the server account is already gone when this runs, so one
/// failing step must not leave the rest of the device un-wiped. Every step
/// runs, each failure is logged, and the first one is rethrown.
enum LocalDataEraser {

    private static let log = Logger(subsystem: "com.jasonlu.breath", category: "localDataEraser")

    static let preservedDefaultsKeys = ["seedDataVersion", "notifiedSeedVersion"]
    static let profilePhotoFilename = "profile_photo.jpg" // ProfileView.profilePhotoURL

    static func eraseAll(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        domainName: String? = Bundle.main.bundleIdentifier,
        documentsDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    ) throws {
        // Settings go last: clearing hasCompletedOnboarding is what flips the
        // UI back to onboarding, so it happens after the data is gone.
        try runEveryStep([
            (name: "user data", run: {
                try context.delete(model: Session.self)
                try context.delete(model: Routine.self)
                try context.delete(model: UserProfile.self)
                try context.delete(model: FlexibilityCheckIn.self)
                try context.delete(model: PendingSyncOp.self)
                try context.delete(model: Exercise.self, where: #Predicate { $0.seedID == nil })
                try context.save()
            }),
            (name: "profile photo", run: {
                let photo = documentsDirectory.appendingPathComponent(profilePhotoFilename)
                if FileManager.default.fileExists(atPath: photo.path) {
                    try FileManager.default.removeItem(at: photo)
                }
            }),
            (name: "settings", run: {
                let preserved = preservedDefaultsKeys.compactMap { key in
                    defaults.object(forKey: key).map { (key, $0) }
                }
                if let domainName { defaults.removePersistentDomain(forName: domainName) }
                for (key, value) in preserved { defaults.set(value, forKey: key) }
                // An explicit write (not just the removal above) so @AppStorage
                // observers re-render and OnboardingGate routes back to onboarding.
                defaults.set(false, forKey: "hasCompletedOnboarding")
            }),
        ])
    }

    /// Runs every step even if earlier ones throw; logs each failure and
    /// rethrows the first.
    static func runEveryStep(_ steps: [(name: String, run: () throws -> Void)]) throws {
        var firstFailure: Error?
        for step in steps {
            do {
                try step.run()
            } catch {
                log.error("Local wipe step '\(step.name, privacy: .public)' failed: \(error)")
                if firstFailure == nil { firstFailure = error }
            }
        }
        if let firstFailure { throw firstFailure }
    }
}
