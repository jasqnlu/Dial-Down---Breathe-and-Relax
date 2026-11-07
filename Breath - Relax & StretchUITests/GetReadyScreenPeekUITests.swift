import XCTest

/// Throwaway: captures the "Get Ready" countdown screen as-is, before any
/// redesign work, so we have a real reference screenshot instead of
/// guessing from source.
final class GetReadyScreenPeekUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testPeekGetReadyScreen() throws {
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

        app.buttons["Continue"].tap()

        let startMiniRoutineRow = app.buttons["Start Mini-Routine"]
        XCTAssertTrue(startMiniRoutineRow.waitForExistence(timeout: 10))
        startMiniRoutineRow.tap()

        let startButton = app.buttons["Start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        startButton.tap()

        // Grab it immediately — get-ready only lasts ~3s before the player
        // takes over.
        Thread.sleep(forTimeInterval: 0.6)
        attach(app, "get-ready-screen")
    }
}
