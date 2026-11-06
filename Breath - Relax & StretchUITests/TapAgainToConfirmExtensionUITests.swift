import XCTest

/// Verifies the tap-again-to-confirm pattern's extension beyond the session
/// exit button (mid-routine): (1) exiting a session on the very first
/// exercise now also requires a second tap, and (2) removing an exercise
/// from the Customize/review screen requires a second tap on its row's
/// remove button instead of a native confirmation alert.
///
/// Armed state is asserted via the button's own accessibilityValue
/// ("Armed, tap again to confirm") rather than by waiting for the separate
/// visible caption to show up as its own queryable element — the caption
/// renders correctly (confirmed via screenshot) but isn't reliably
/// independently discoverable, and on a slow simulator a second
/// accessibility-tree round trip can miss the ~2.5s armed window entirely.
final class TapAgainToConfirmExtensionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testFirstExerciseExitRequiresDoubleTap() throws {
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

        app.buttons["Continue"].tap()

        let startMiniRoutineRow = app.buttons["Start Mini-Routine"]
        XCTAssertTrue(startMiniRoutineRow.waitForExistence(timeout: 10))
        startMiniRoutineRow.tap()

        let startButton = app.buttons["Start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let pauseButton = app.buttons["Pause session"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 10), "Session player should appear")
        XCTAssertTrue(app.staticTexts["1 / 1"].waitForExistence(timeout: 5), "Should be the first (only) exercise")

        let closeButton = app.buttons["sessionCloseButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        // Let the CustomizeRoutineView -> SessionPlayerView sheet-swap
        // transition fully settle before tapping — acting immediately can
        // land a tap on a still-transitioning previous screen's own close
        // button instead.
        Thread.sleep(forTimeInterval: 1.0)

        // First tap on exercise 1 (currentIndex == 0): must NOT exit
        // immediately anymore.
        closeButton.tap()
        XCTAssertEqual(closeButton.value as? String, "Armed, tap again to confirm",
                        "First tap on exercise 1 should arm, not exit yet")
        XCTAssertTrue(pauseButton.exists, "First tap on exercise 1 should not exit yet")
        attach(app, "01-first-exercise-armed")

        closeButton.tap()
        XCTAssertTrue(exercisesTab.waitForExistence(timeout: 5), "Second tap should exit back to Exercises tab")
        attach(app, "02-exited-after-second-tap")
    }

    func testRemovingExerciseRequiresDoubleTap() throws {
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
        XCTAssertGreaterThanOrEqual(tiles.count, 2, "Should match both Left and Right Scalene Neck Stretch")
        tiles.element(boundBy: 0).tap()
        tiles.element(boundBy: 1).tap()

        app.buttons["Continue"].tap()

        let startMiniRoutineRow = app.buttons["Start Mini-Routine"]
        XCTAssertTrue(startMiniRoutineRow.waitForExistence(timeout: 10))
        startMiniRoutineRow.tap()

        // Now on the CustomizeRoutineView "Start Mini-Routine" screen with
        // 2 rows, each carrying its own remove button.
        let removeButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'removeExercise-'"))
        XCTAssertTrue(removeButtons.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(removeButtons.count, 2)

        let firstRemove = removeButtons.element(boundBy: 0)
        Thread.sleep(forTimeInterval: 1.0)
        firstRemove.tap()
        XCTAssertEqual(firstRemove.value as? String, "Armed, tap again to confirm",
                        "First tap on remove should arm, not remove yet")
        XCTAssertEqual(removeButtons.count, 2, "First tap should not remove the row yet")
        attach(app, "03-remove-armed")

        firstRemove.tap()
        // Give the removal + relayout a moment, then confirm only one row
        // remains.
        let rowGone = NSPredicate(format: "self.count == 1")
        expectation(for: rowGone, evaluatedWith: removeButtons, handler: nil)
        waitForExpectations(timeout: 5)
        attach(app, "04-removed-after-second-tap")
    }
}
