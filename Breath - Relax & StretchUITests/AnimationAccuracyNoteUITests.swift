import XCTest

/// Verifies (1) the re-rendered Left Wall Bicep Stretch animation still plays
/// in the exercise detail screen after the rotation-audit fix, and (2) the
/// "may not be 100% accurate" disclaimer shows under Reverse Prayer
/// Stretch's animation (the one known rig-limit case: no wrist bone).
final class AnimationAccuracyNoteUITests: XCTestCase {

    private func openExercise(_ name: String, app: XCUIApplication) {
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
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testWallBicepStretchAnimationStillPlays() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES",
            "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES",
            "-auth.provider", "guest",
        ]
        app.launch()

        openExercise("Left Wall Bicep Stretch", app: app)
        Thread.sleep(forTimeInterval: 1.5)   // let the loop begin
        attach(app, "01-left-wall-bicep-detail")
    }

    func testReversePrayerStretchShowsAccuracyNote() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES",
            "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES",
            "-auth.provider", "guest",
        ]
        app.launch()

        openExercise("Reverse Prayer Stretch", app: app)
        Thread.sleep(forTimeInterval: 1.0)

        let note = app.descendants(matching: .any)["Note: this animation may not be 100% accurate to the exercise."].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 8), "Accuracy note not found on Reverse Prayer Stretch")
        attach(app, "02-reverse-prayer-accuracy-note")
    }
}
