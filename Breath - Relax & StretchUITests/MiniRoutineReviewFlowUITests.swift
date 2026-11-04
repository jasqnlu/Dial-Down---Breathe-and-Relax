import XCTest

/// End-to-end coverage for the standalone mini-routine flow in the
/// Exercises tab: tap "Select" → pick a couple of exercises via search
/// results (a flat grid, unlike the region graph) → "Continue" opens
/// `MiniRoutineReviewView` → "Start Mini-Routine" launches a one-off
/// `SessionPlayerView`. This is distinct from `ExercisePickingFlowUITests`,
/// which covers the Customize-context "Add Exercises" path (Done, not
/// Continue) — the two never share a code path once `PickingBar` branches
/// on `ExercisePickingSession.hasContext`.
final class MiniRoutineReviewFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func expectLabel(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && element.label == expected { return true }
        } while Date() < deadline
        return false
    }

    func testSelectPickContinueStartsMiniRoutine() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES", "-auth.provider", "guest",
        ]
        app.launch()

        // 1. Exercises tab.
        app.buttons["Exercises"].tap()
        let searchField = app.textFields["Search exercises"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 20), "Exercises tab should show the search field")

        // 2. Search to get a flat grid (simpler to drive than the region
        //    graph's pinch/focus gestures — not the point of this test).
        searchField.tap()
        searchField.typeText("e")

        // 3. Enter standalone picking mode (no Customize context).
        let selectToggle = app.buttons["exerciseSelectToggle"]
        XCTAssertTrue(selectToggle.waitForExistence(timeout: 10), "Select toggle should exist in the header")
        selectToggle.tap()

        // 4. Pick two tiles.
        let tiles = app.descendants(matching: .any).matching(identifier: "exerciseGridTile")
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 10), "Search should render exercise tiles")
        XCTAssertGreaterThanOrEqual(tiles.count, 2, "Search for \"e\" should match at least two exercises")
        tiles.element(boundBy: 0).tap()
        tiles.element(boundBy: 1).tap()

        let pickingCount = app.staticTexts["pickingBarCount"]
        XCTAssertTrue(expectLabel(pickingCount, "2 exercises"),
                      "Picking bar should read '2 exercises', got '\(pickingCount.label)'")
        attach(app, "01-two-picked-standalone")

        // 5. "Continue" (not "Done" — no Customize context) opens the review.
        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5), "Standalone picking bar should read Continue")
        continueButton.tap()

        let startMiniRoutine = app.buttons["Start Mini-Routine"]
        XCTAssertTrue(startMiniRoutine.waitForExistence(timeout: 10), "Review screen should offer Start Mini-Routine")
        XCTAssertTrue(app.buttons["Create New Routine"].exists, "Review screen should offer Create New Routine")
        XCTAssertTrue(app.buttons["Add to Existing Routine"].exists, "Review screen should offer Add to Existing Routine")
        attach(app, "02-review-screen")

        // 6. Start it — a one-off SessionPlayerView, nothing saved.
        // That row opens Customize first; its own "Start" button plays it.
        startMiniRoutine.tap()
        let startButton = app.buttons["Start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10), "Customize should offer Start")
        startButton.tap()
        let pauseButton = app.buttons["Pause session"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 10), "Start Mini-Routine should launch the session player")
        attach(app, "03-mini-routine-session-playing")
    }
}
