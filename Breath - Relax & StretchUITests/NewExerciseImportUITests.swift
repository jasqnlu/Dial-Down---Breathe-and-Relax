import XCTest

/// Verifies the 10 exercises added to SeedData.json (physiological sigh,
/// resonant frequency breathing, right-nostril energizing breath, skull
/// shining breath, World's Greatest Stretch L/R, seated spinal rotation L/R,
/// standing adductor rock, standing tibialis raise) are actually seeded and
/// reachable through the Exercises tab search, not just present in the JSON.
final class NewExerciseImportUITests: XCTestCase {

    func testNewlyAddedExercisesAreSearchableAndOpenable() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES",
            "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES",
            "-auth.provider", "guest",
        ]
        app.launch()

        let exercisesTab = app.descendants(matching: .any)["Exercises"].firstMatch
        XCTAssertTrue(exercisesTab.waitForExistence(timeout: 15), "Exercises tab not found")
        exercisesTab.tap()

        let search = app.textFields["Search exercises"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "Search field not found")

        let names = [
            "Physiological Sigh (Double Inhale Exhale)",
            "Resonant Frequency Breathing (6 Breaths per Minute)",
            "Right-Nostril Energizing Breath (Surya Bhedana)",
            "Skull Shining Breath (Kapalabhati)",
            "World's Greatest Stretch (Left Lead Leg)",
            "World's Greatest Stretch (Right Lead Leg)",
            "Seated Spinal Rotation with Overhead Reach (Left)",
            "Seated Spinal Rotation with Overhead Reach (Right)",
            "Standing Adductor Rock (Side-to-Side)",
            "Standing Tibialis Raise (Toe Lifts)",
        ]

        for name in names {
            search.tap()
            if !(search.value as? String ?? "").isEmpty {
                let clear = app.buttons["Clear search"]
                if clear.exists { clear.tap() }
            }
            // A distinctive substring is enough and avoids apostrophe-typing issues.
            let query = String(name.prefix(20))
            search.typeText(query)

            let rowPredicate = NSPredicate(format: "label BEGINSWITH %@", name)
            let row = app.descendants(matching: .any).matching(rowPredicate).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 8), "\(name) row not found in search results")
        }

        // Confirm the last one actually opens to its detail screen.
        let tibialisRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Standing Tibialis Raise"))
            .firstMatch
        tibialisRow.tap()
        let detailHeading = app.descendants(matching: .any)["Standing Tibialis Raise (Toe Lifts)"].firstMatch
        XCTAssertTrue(detailHeading.waitForExistence(timeout: 8), "Standing Tibialis Raise detail screen did not open")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "standing-tibialis-raise-detail"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
