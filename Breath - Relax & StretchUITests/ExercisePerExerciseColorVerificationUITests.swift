import XCTest

/// Throwaway verification test — screenshots screens with multiple
/// PoseGlyphIcons visible at once, to eyeball that per-exercise accent
/// colors (Color.forExercise) read as varied and none is too light/dark.
final class ExercisePerExerciseColorVerificationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHomeAndExercisesTabShowVariedGlyphColors() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-hasCompletedOnboarding", "YES",
            "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES",
            "-auth.provider", "guest"
        ]
        app.launch()

        let homeTab = app.descendants(matching: .any)["Today"].firstMatch
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10))
        homeTab.tap()
        sleep(2)
        attach(app.screenshot(), name: "01-home-roadmap-glyph-colors")

        let exercisesTab = app.descendants(matching: .any)["Exercises"].firstMatch
        XCTAssertTrue(exercisesTab.waitForExistence(timeout: 10))
        exercisesTab.tap()
        sleep(2)
        attach(app.screenshot(), name: "02-exercises-tab-glyph-colors")

        homeTab.tap()
        sleep(1)
        let customizeButton = app.buttons["Customize"]
        if customizeButton.waitForExistence(timeout: 5) {
            customizeButton.tap()
            sleep(2)
            attach(app.screenshot(), name: "03-customize-routine-exercise-list-glyph-colors")
        }
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
