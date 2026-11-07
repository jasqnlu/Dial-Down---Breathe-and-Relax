import XCTest

/// Throwaway: captures the session player mid-breath-exercise, to verify
/// the inline type/cue badge cluster now sits under the phase readout
/// instead of overlaid on the breathing circle.
final class BreathPlayerLayoutPeekUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testPeekBreathPlayerLayout() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES", "-auth.provider", "guest",
            "-autoSkipGetReadyCountdown", "YES",
        ]
        app.launch()

        let exercisesTab = app.buttons["Exercises"]
        XCTAssertTrue(exercisesTab.waitForExistence(timeout: 20))
        exercisesTab.tap()

        let searchField = app.textFields["Search exercises"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 20))
        searchField.tap()
        searchField.typeText("Box Breathing")

        let selectToggle = app.buttons["exerciseSelectToggle"]
        XCTAssertTrue(selectToggle.waitForExistence(timeout: 10))
        selectToggle.tap()

        let tiles = app.descendants(matching: .any).matching(identifier: "exerciseGridTile")
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 10))
        tiles.element(boundBy: 0).tap()

        app.buttons["Continue"].tap()

        let startMiniRoutineRow = app.buttons["Start Mini-Routine"]
        XCTAssertTrue(startMiniRoutineRow.waitForExistence(timeout: 10))
        startMiniRoutineRow.tap()

        let startButton = app.buttons["Start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let pauseButton = app.buttons["Pause session"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 10), "Session player should appear")
        Thread.sleep(forTimeInterval: 1.0)
        attach(app, "breath-player-layout")
    }
}
