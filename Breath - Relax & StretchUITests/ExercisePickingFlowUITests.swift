import XCTest

/// End-to-end coverage for the cross-tab exercise-picking flow
/// (docs/superpowers/specs/2026-08-14-roadmap-carousel-exercise-picking-design.md).
///
/// Drives the REAL path the feature was built around:
/// Home → Customize → "Add Exercises" → Exercises tab region graph → focus a
/// region → open a satellite group (a PUSHED `ExerciseGroupCorpusSheet`) → tap
/// tiles → switch tabs and back → Done → back on Home with Customize
/// re-presented, carrying the merged exercise list.
///
/// The pushed-destination leg is the point: the picking bar is attached with
/// `.safeAreaInset` and such insets do NOT propagate from a NavigationStack's
/// root to its pushed destinations, so the bar has to be applied on the corpus
/// sheet itself. This test asserts the bar is visible and live on THAT screen,
/// which is exactly the regression a root-only attachment produces.
///
/// Element handles are accessibility identifiers, not visible labels, because
/// the region/group/exercise names all come from seed data and would make the
/// test brittle to content edits: "exerciseCategoryNode", "exerciseGroupNode",
/// "exerciseGridTile", "pickingBarCount".
final class ExercisePickingFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// First element matching `identifier` that is both hittable and enabled.
    /// The region graph draws every category's satellites, but only the
    /// focused category's are enabled, and nodes near the canvas edge can sit
    /// outside the visible frame — so "firstMatch" alone is not tappable.
    private func firstTappable(_ app: XCUIApplication,
                               identifier: String,
                               timeout: TimeInterval = 10) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let matches = app.descendants(matching: .any).matching(identifier: identifier)
            for i in 0..<matches.count {
                let element = matches.element(boundBy: i)
                if element.exists && element.isHittable && element.isEnabled {
                    return element
                }
            }
        } while Date() < deadline
        return nil
    }

    func testAddExercisesPickingRoundTripFromHomeToCorpusSheetAndBack() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES", "-auth.provider", "guest",
        ]
        app.launch()

        // 1. Home → Customize.
        let customizeButton = app.buttons["Customize"]
        XCTAssertTrue(customizeButton.waitForExistence(timeout: 20), "Home hero's Customize button should exist")
        customizeButton.tap()

        // 2. Customize → "Add Exercises" (begins the picking session, dismisses
        //    the sheet and posts .browseExercisesRequested → Exercises tab).
        let addExercises = app.buttons["Add Exercises"]
        XCTAssertTrue(addExercises.waitForExistence(timeout: 10), "Customize should offer Add Exercises")
        addExercises.tap()

        // 3. We should land on the Exercises tab, showing the region graph.
        let searchField = app.textFields["Search exercises"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Add Exercises should switch to the Exercises tab")
        guard let categoryNode = firstTappable(app, identifier: "exerciseCategoryNode") else {
            attach(app, "fail-no-category-node")
            return XCTFail("No tappable region circle in the exercise graph")
        }
        attach(app, "01-exercises-tab-graph")

        // 4. Focus a region, then open one of its satellite groups. The
        //    corpus sheet is a pushed destination, not a modal sheet.
        categoryNode.tap()
        guard let groupNode = firstTappable(app, identifier: "exerciseGroupNode") else {
            attach(app, "fail-no-group-node")
            return XCTFail("No enabled satellite group node after focusing a region")
        }
        groupNode.tap()

        // 5. The picking bar must be visible on THIS pushed screen.
        let pickingCount = app.staticTexts["pickingBarCount"]
        XCTAssertTrue(pickingCount.waitForExistence(timeout: 10),
                      "Picking bar must be visible on the pushed group corpus sheet")
        XCTAssertEqual(pickingCount.label, "0 exercises", "Picking bar should start empty")
        attach(app, "02-corpus-sheet-picking-bar-empty")

        // 6. Pick two tiles; the bar's count must track them live.
        let tiles = app.descendants(matching: .any).matching(identifier: "exerciseGridTile")
        XCTAssertGreaterThanOrEqual(tiles.count, 2, "Group corpus should render at least two exercise tiles")
        tiles.element(boundBy: 0).tap()
        XCTAssertTrue(expectLabel(pickingCount, "1 exercise"),
                      "Count should read '1 exercise' after one pick, got '\(pickingCount.label)'")
        tiles.element(boundBy: 1).tap()
        XCTAssertTrue(expectLabel(pickingCount, "2 exercises"),
                      "Count should read '2 exercises' after two picks, got '\(pickingCount.label)'")
        attach(app, "03-corpus-sheet-two-picked")

        // 7. Picking state must survive a tab switch — the whole reason this
        //    is an ObservableObject in the environment and not sheet-local
        //    state.
        app.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["Customize"].waitForExistence(timeout: 10), "Today tab should be showing")
        app.buttons["Exercises"].tap()
        XCTAssertTrue(pickingCount.waitForExistence(timeout: 10), "Picking bar should still be present after a tab round trip")
        XCTAssertEqual(pickingCount.label, "2 exercises", "Picks must survive switching tabs")
        attach(app, "04-after-tab-round-trip")

        // 8. Done → back on Home (tab 0) with Customize re-presented, now
        //    showing the merged list (Add Exercises is Customize's toolbar
        //    action, so its presence proves the sheet came back).
        app.buttons["Done"].tap()
        XCTAssertTrue(addExercises.waitForExistence(timeout: 10),
                      "Done should return to Home with Customize re-presented")
        attach(app, "05-customize-repopulated")
    }

    /// Polls an element's label instead of sleeping: SwiftUI republishes the
    /// count a frame or two after the tap.
    private func expectLabel(_ element: XCUIElement, _ expected: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && element.label == expected { return true }
        } while Date() < deadline
        return false
    }
}
