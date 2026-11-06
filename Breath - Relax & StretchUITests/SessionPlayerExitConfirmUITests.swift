import XCTest

/// Verifies the tap-again-to-confirm exit flow replacing the old native
/// confirmation alert: once mid-routine (currentIndex > 0), a first tap on
/// the X shows a "Double tap to confirm" caption and does NOT dismiss; a
/// second tap while it's showing does.
final class SessionPlayerExitConfirmUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testFirstTapArmsSecondTapExits() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES", "-auth.provider", "guest",
        ]
        app.launch()

        let exercisesTab = app.buttons["Exercises"]
        XCTAssertTrue(exercisesTab.waitForExistence(timeout: 20))
        exercisesTab.tap()

        let searchField = app.textFields["Search exercises"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 20))
        searchField.tap()
        searchField.typeText("Scalene Neck Stretch")

        let selectToggle = app.buttons["exerciseSelectToggle"]
        XCTAssertTrue(selectToggle.waitForExistence(timeout: 10))
        selectToggle.tap()

        let tiles = app.descendants(matching: .any).matching(identifier: "exerciseGridTile")
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 10))
        tiles.element(boundBy: 0).tap()
        tiles.element(boundBy: 1).tap()

        app.buttons["Continue"].tap()

        let startMiniRoutineRow = app.buttons["Start Mini-Routine"]
        XCTAssertTrue(startMiniRoutineRow.waitForExistence(timeout: 10))
        startMiniRoutineRow.tap()

        let startButton = app.buttons["Start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let pauseButton = app.buttons["Pause session"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 10), "Session player should appear")

        // Advance past the first exercise so currentIndex > 0 — the
        // confirm-to-exit path only applies once something's in progress.
        app.buttons["Skip exercise"].tap()
        XCTAssertTrue(app.staticTexts["2 / 2"].waitForExistence(timeout: 10))

        let closeButton = app.buttons["sessionCloseButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))

        closeButton.tap()
        // Checked via the button's own accessibilityValue rather than
        // waiting for the separate visible caption to appear as its own
        // queryable element — the caption renders correctly (confirmed via
        // screenshot in TapAgainToConfirmExtensionUITests) but a second
        // accessibility-tree round trip can miss the ~2.5s armed window on
        // a slow simulator.
        XCTAssertEqual(closeButton.value as? String, "Armed, tap again to confirm",
                        "First tap should arm, not exit yet")
        // Still on the session player — not dismissed.
        XCTAssertTrue(pauseButton.exists, "First tap should not exit yet")
        attach(app, "01-armed-caption-visible")

        closeButton.tap()
        XCTAssertTrue(exercisesTab.waitForExistence(timeout: 5), "Second tap should exit back to Exercises tab")
        attach(app, "02-exited-after-second-tap")
    }
}
