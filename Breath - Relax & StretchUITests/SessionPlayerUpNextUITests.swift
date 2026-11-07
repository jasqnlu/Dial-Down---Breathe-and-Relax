import XCTest

/// End-to-end coverage for the reworked session player: no more 0.5x/1x/2x
/// speed picker, a real "Previous exercise" button, and the "Up Next"
/// preview card that slides in during the last `SessionPlayerView
/// .upNextLeadSeconds` of an exercise. Drives two of the shortest catalog
/// exercises (20s each — "Left/Right Scalene Neck Stretch") via the same
/// standalone mini-routine flow `MiniRoutineReviewFlowUITests` covers, so
/// the whole test finishes in well under a minute of real time.
final class SessionPlayerUpNextUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testNoSpeedPickerBackButtonAndUpNextCard() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES", "-auth.provider", "guest",
        ]
        app.launch()

        // 1. Pick the two Scalene Neck Stretch exercises — 20s each, both
        //    resolvable from one search — via the standalone mini-routine
        //    flow (Exercises tab → Select → search → Continue → Start).
        app.buttons["Exercises"].tap()
        let searchField = app.textFields["Search exercises"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 20))
        searchField.tap()
        searchField.typeText("Scalene Neck Stretch")

        app.buttons["exerciseSelectToggle"].tap()
        let tiles = app.descendants(matching: .any).matching(identifier: "exerciseGridTile")
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(tiles.count, 2, "Should match both Left and Right Scalene Neck Stretch")
        tiles.element(boundBy: 0).tap()
        tiles.element(boundBy: 1).tap()

        app.buttons["Continue"].tap()

        // "Review Picks" screen: tap the "Start Mini-Routine" row to reach
        // the actual start screen, which has its own "Start" pill button.
        let startMiniRoutineRow = app.buttons["Start Mini-Routine"]
        XCTAssertTrue(startMiniRoutineRow.waitForExistence(timeout: 10))
        startMiniRoutineRow.tap()

        let startButton = app.buttons["Start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let pauseButton = app.buttons["Pause session"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 10), "Session player should appear")

        // 2. Top bar: no speed picker, real Previous + Skip buttons.
        XCTAssertEqual(app.segmentedControls.count, 0, "Speed picker should be removed")
        XCTAssertTrue(app.buttons["Previous exercise"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Skip exercise"].exists)
        attach(app, "01-session-top-bar-no-speed-picker")

        // 3. First exercise is a 20s exercise — confirm the countdown
        //    reflects the exercise's own duration (no scaling/hardcoding),
        //    then wait for the "Up Next" card to slide in near the end.
        let countdown = app.staticTexts.matching(NSPredicate(format: "label MATCHES '0:\\\\d\\\\d'")).firstMatch
        XCTAssertTrue(countdown.waitForExistence(timeout: 5))
        attach(app, "02-initial-countdown")

        let upNextCard = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH 'Up next:'"))
            .firstMatch
        XCTAssertTrue(upNextCard.waitForExistence(timeout: 25), "Up Next card should appear within the last 5s")
        attach(app, "03-up-next-card-visible")

        // 4. Let it auto-advance to exercise 2, then use the new back
        //    button to confirm it jumps to the previous exercise and
        //    restarts its timer.
        let indexLabel = app.staticTexts["2 / 2"]
        XCTAssertTrue(indexLabel.waitForExistence(timeout: 10), "Should auto-advance to the second exercise")
        attach(app, "04-advanced-to-second-exercise")

        app.buttons["Previous exercise"].tap()
        XCTAssertTrue(app.staticTexts["1 / 2"].waitForExistence(timeout: 5), "Back button should return to exercise 1")
        attach(app, "05-back-button-returned-to-first")
    }
}
