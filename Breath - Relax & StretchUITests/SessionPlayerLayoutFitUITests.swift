import XCTest

/// Throwaway verification test for the session-player no-scroll layout
/// rework: confirms the transport controls (bottom) and the countdown timer
/// (middle) are simultaneously on screen with no scrolling required, on
/// whatever simulator it's run against.
final class SessionPlayerLayoutFitUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTimerAndTransportControlsBothVisibleWithoutScrolling() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
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

        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        continueButton.tap()

        // "Review Picks" screen: tap the "Start Mini-Routine" row to get to
        // the actual start screen, which has its own "Start" pill button.
        let startMiniRoutineRow = app.buttons["Start Mini-Routine"]
        XCTAssertTrue(startMiniRoutineRow.waitForExistence(timeout: 10))
        startMiniRoutineRow.tap()

        let startButton = app.buttons["Start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        let pauseButton = app.buttons["Pause session"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 10), "Session player should appear")

        // Both the countdown timer and the transport row (previous/pause/skip)
        // must be hittable on screen at once, with no scroll needed.
        let countdown = app.staticTexts.matching(NSPredicate(format: "label MATCHES '0:\\\\d\\\\d'")).firstMatch
        XCTAssertTrue(countdown.waitForExistence(timeout: 5))
        XCTAssertTrue(countdown.isHittable, "Countdown timer should be on screen without scrolling")
        XCTAssertTrue(app.buttons["Previous exercise"].isHittable)
        XCTAssertTrue(pauseButton.isHittable)
        XCTAssertTrue(app.buttons["Skip exercise"].isHittable)

        attach(app, "session-player-no-scroll-layout")
    }
}
