import XCTest

/// Coverage for the "route routine creation through Today's Customize
/// screen" unification: "Create New Routine" (from the standalone
/// mini-routine review) now opens `CustomizeRoutineView` — with a name
/// field, the roadmap preview, per-exercise duration steppers, and
/// reorderable rows — instead of the old `RoutineBuilderView` Form. Also
/// screenshots the brighter streak flame (color is subjective — this just
/// confirms it renders).
final class UnifiedCustomizeFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testCreateNewRoutineOpensSharedCustomizeScreen() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES", "-auth.provider", "guest",
        ]
        app.launch()

        // App launch shows a splash/loading screen (seed data import) before
        // TodayView and the tab bar exist — wait for the real UI, not just
        // the process, before interacting.
        let exercisesTab = app.buttons["Exercises"]
        XCTAssertTrue(exercisesTab.waitForExistence(timeout: 30), "Tab bar should appear once launch/seeding finishes")

        // Today tab: screenshot the brighter streak flame.
        attach(app, "01-today-streak-flame")

        // Pick two exercises via the standalone flow → MiniRoutineReviewView.
        exercisesTab.tap()
        let searchField = app.textFields["Search exercises"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 20))
        searchField.tap()
        searchField.typeText("Scalene Neck Stretch")

        app.buttons["exerciseSelectToggle"].tap()
        let tiles = app.descendants(matching: .any).matching(identifier: "exerciseGridTile")
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(tiles.count, 2)
        tiles.element(boundBy: 0).tap()
        tiles.element(boundBy: 1).tap()

        app.buttons["Continue"].tap()
        let createNewRoutine = app.buttons["Create New Routine"]
        XCTAssertTrue(createNewRoutine.waitForExistence(timeout: 10))
        createNewRoutine.tap()

        // The shared Customize screen: name field (new), roadmap, reorderable
        // exercise rows, "Save Routine" primary action (disabled until named).
        let nameField = app.textFields["Routine name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "Create New Routine should open the shared Customize screen with a name field")
        let saveButton = app.buttons["Save Routine"]
        XCTAssertTrue(saveButton.exists)
        XCTAssertFalse(saveButton.isEnabled, "Save Routine should be disabled until a name is entered")
        attach(app, "02-create-routine-customize-screen")

        // Both reorderable rows render with the same stable identifiers
        // RoutineBuilderView's own (already-shipped) drag-to-reorder List
        // uses. The drag gesture itself is exercised there already;
        // XCUITest's synthesized long-press+drag for List/UITableView
        // reordering is known to be unreliable to script (the row becomes
        // "not hittable" mid-gesture once the system drag preview appears),
        // so this confirms the reorderable structure exists rather than
        // scripting the gesture.
        XCTAssertTrue(app.otherElements.matching(identifier: "customizeExerciseRow-0").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements.matching(identifier: "customizeExerciseRow-1").firstMatch.exists)

        // Name it and save.
        nameField.tap()
        nameField.typeText("Neck Reset")
        XCTAssertTrue(saveButton.isEnabled, "Save Routine should enable once named")
        saveButton.tap()

        // Give both sheets (Customize, then MiniRoutineReviewView) time to
        // fully dismiss before checking where we landed.
        let routinesTab = app.buttons["Routines"]
        XCTAssertTrue(routinesTab.waitForExistence(timeout: 10), "Should return to tab content after both sheets dismiss")
        attach(app, "03-after-save-routine-tap")

        // Lands back on the Exercises tab exactly where the search was left
        // — keyboard still up, covering the floating tab bar. Dismiss it
        // (return key) before the tab bar is reachable.
        if app.keyboards.buttons["search"].exists {
            app.keyboards.buttons["search"].tap()
        }

        // Lands back on the Exercises tab (picking session origin); confirm
        // the new routine actually saved by checking the Routines tab.
        routinesTab.tap()
        attach(app, "04-routines-tab")
        XCTAssertTrue(app.staticTexts["Neck Reset"].waitForExistence(timeout: 10), "New routine should appear in the Routines list")
        attach(app, "05-routine-saved-in-list")
    }
}
