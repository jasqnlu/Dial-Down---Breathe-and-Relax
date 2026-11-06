import XCTest

/// End-to-end coverage for pinning routines from the Routines list and
/// having Today's session selection follow the resulting priority order —
/// the replacement for the old single `pinnedTodayRoutineID` pin. Covers:
///   - the "Pin to Today"/"Unpin" swipe action on `RoutineListView` rows
///   - the pin badge next to a pinned routine's name
///   - the reorder button appearing on Today once 2+ routines are pinned,
///     and `PinnedRoutineOrderView` listing them
///   - unpinning the higher-priority routine promotes the next one, which
///     Today's hero card then shows
/// Drag-to-reorder itself is not scripted here — see
/// UnifiedCustomizeFlowUITests's comment on why XCUITest's synthesized
/// List drag gesture is unreliable to automate; the underlying List+
/// `.onMove` mechanism is identical to the already-covered Customize
/// screen's.
final class PinnedRoutinePriorityUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Creates a named routine from two exercises matching `searchTerm`,
    /// via the standalone picking flow → "Create New Routine" (the same
    /// unified Customize screen `UnifiedCustomizeFlowUITests` covers).
    private func createRoutine(named name: String, searchTerm: String, in app: XCUIApplication) {
        app.buttons["Exercises"].tap()
        let searchField = app.textFields["Search exercises"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 20))
        searchField.tap()
        // A prior search term (from an earlier createRoutine call) may
        // still be in the field — typeText appends rather than replaces,
        // so clear it first or the second search matches nothing.
        if let existing = searchField.value as? String, !existing.isEmpty {
            let clearButton = searchField.buttons["Clear text"]
            if clearButton.exists {
                clearButton.tap()
            } else {
                searchField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
            }
        }
        searchField.typeText(searchTerm)

        app.buttons["exerciseSelectToggle"].tap()
        let tiles = app.descendants(matching: .any).matching(identifier: "exerciseGridTile")
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(tiles.count, 2, "Search '\(searchTerm)' should match at least two exercises")
        tiles.element(boundBy: 0).tap()
        tiles.element(boundBy: 1).tap()

        app.buttons["Continue"].tap()
        let createNewRoutine = app.buttons["Create New Routine"]
        XCTAssertTrue(createNewRoutine.waitForExistence(timeout: 10))
        createNewRoutine.tap()

        let nameField = app.textFields["Routine name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText(name)
        app.buttons["Save Routine"].tap()

        // Returns to the Exercises tab with the search keyboard still up —
        // dismiss it (return key) so later taps land on the tab bar, not
        // the keyboard covering it.
        let returnKey = app.keyboards.buttons["search"]
        if returnKey.waitForExistence(timeout: 5) { returnKey.tap() }
    }

    func testPinFromRoutinesListDrivesRoundTripsPriority() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES", "-auth.provider", "guest",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Exercises"].waitForExistence(timeout: 30))

        // Two small, distinct routines to pin.
        createRoutine(named: "Neck Routine", searchTerm: "Scalene Neck Stretch", in: app)
        createRoutine(named: "Shin Routine", searchTerm: "Kneeling Tibialis Stretch", in: app)

        // Pin both, in order, from the Routines list.
        app.buttons["Routines"].tap()
        let neckRow = app.staticTexts["Neck Routine"]
        XCTAssertTrue(neckRow.waitForExistence(timeout: 10))
        neckRow.swipeRight()
        app.buttons["Pin to Today"].tap()

        let shinRow = app.staticTexts["Shin Routine"]
        XCTAssertTrue(shinRow.waitForExistence(timeout: 5))
        shinRow.swipeRight()
        app.buttons["Pin to Today"].tap()
        attach(app, "01-both-routines-pinned")

        // Pin badges show on both rows now.
        XCTAssertTrue(app.images["Pinned to Today"].firstMatch.waitForExistence(timeout: 5))

        // Today: reorder button appears (2 pinned), hero shows the
        // first-pinned routine (Neck Routine, priority 0).
        app.buttons["Today"].tap()
        let reorderButton = app.buttons["Arrange pinned routine order"]
        XCTAssertTrue(reorderButton.waitForExistence(timeout: 10), "Reorder button should appear once 2 routines are pinned")
        XCTAssertTrue(app.staticTexts["Neck Routine"].waitForExistence(timeout: 5), "Hero should show the highest-priority pinned routine")
        attach(app, "02-today-shows-first-pinned")

        reorderButton.tap()
        XCTAssertTrue(app.navigationBars["Pinned Order"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Neck Routine"].exists)
        XCTAssertTrue(app.staticTexts["Shin Routine"].exists)
        attach(app, "03-reorder-sheet")
        app.buttons["Done"].tap()

        // Unpin the higher-priority routine; the next one should be
        // promoted and Today should switch to showing it.
        app.buttons["Routines"].tap()
        XCTAssertTrue(app.staticTexts["Neck Routine"].waitForExistence(timeout: 5))
        app.staticTexts["Neck Routine"].swipeRight()
        app.buttons["Unpin"].tap()

        app.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["Shin Routine"].waitForExistence(timeout: 10), "Today should promote the next pinned routine once the top one is unpinned")
        attach(app, "04-today-promoted-after-unpin")
    }
}
