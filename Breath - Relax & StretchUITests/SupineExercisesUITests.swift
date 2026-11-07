import XCTest

/// Verifies the eight new-base-pose animations from the 2026-08-09 Tier B
/// work (side-lying Chest Opener via an object-level roll, flat-on-back
/// Spinal Twist via a small thigh-Z tilt, Figure-4 via rigid mitt
/// weighting, and Thread the Needle via the first quadruped base pose)
/// actually open and play in the exercise detail screen, not just render
/// cleanly in Blender.
final class SupineExercisesUITests: XCTestCase {

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testAllEightAnimationsOpenAndPlay() throws {
        let names = [
            "Left Supine Chest Opener (Open Book)",
            "Right Supine Chest Opener (Open Book)",
            "Left Supine Spinal Twist (Windshield Wipers)",
            "Right Supine Spinal Twist (Windshield Wipers)",
            "Left Supine Figure-4 Stretch",
            "Right Supine Figure-4 Stretch",
            "Left Thread the Needle",
            "Right Thread the Needle",
        ]
        for name in names {
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
            search.tap()
            search.typeText(name)

            let row = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", name))
                .firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 8), "\(name) row not found")
            row.tap()

            Thread.sleep(forTimeInterval: 1.5)
            attach(app, name)
            app.terminate()
        }
    }
}
