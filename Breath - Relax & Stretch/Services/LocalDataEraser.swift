import Foundation
import SwiftData

/// Returns the device to a fresh-install state after Delete Account
/// succeeds (decision 2026-10-01: deleting the account also wipes local
/// data). Run only *after* the server confirmed, never on failure.
///
/// Keeps the bundled seed exercise catalog (content, not user data; seed
/// rows have a non-nil `seedID`) and the two counters describing which
/// catalog version is installed, so the next launch neither re-runs seed
/// migrations nor greets the user with "New Content Added".
enum LocalDataEraser {

    static let preservedDefaultsKeys = ["seedDataVersion", "notifiedSeedVersion"]
    static let profilePhotoFilename = "profile_photo.jpg" // ProfileView.profilePhotoURL

    static func eraseAll(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        domainName: String? = Bundle.main.bundleIdentifier,
        documentsDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    ) throws {
        try context.delete(model: Session.self)
        try context.delete(model: Routine.self)
        try context.delete(model: UserProfile.self)
        try context.delete(model: FlexibilityCheckIn.self)
        try context.delete(model: PendingSyncOp.self)
        try context.delete(model: Exercise.self, where: #Predicate { $0.seedID == nil })
        try context.save()

        let preserved = preservedDefaultsKeys.compactMap { key in
            defaults.object(forKey: key).map { (key, $0) }
        }
        if let domainName { defaults.removePersistentDomain(forName: domainName) }
        for (key, value) in preserved { defaults.set(value, forKey: key) }
        // An explicit write (not just the removal above) so @AppStorage
        // observers re-render and OnboardingGate routes back to onboarding.
        defaults.set(false, forKey: "hasCompletedOnboarding")

        let photo = documentsDirectory.appendingPathComponent(profilePhotoFilename)
        if FileManager.default.fileExists(atPath: photo.path) {
            try FileManager.default.removeItem(at: photo)
        }
    }
}
