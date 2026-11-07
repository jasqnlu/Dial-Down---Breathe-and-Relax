import XCTest

/// Throwaway verification test — screenshots the restyled Exercises tab
/// search bar (real Liquid Glass) and the new filter sheet (Type/Difficulty/
/// Duration). Not part of the permanent regression suite's intent, but left
/// in place like the codebase's other one-off "NewExerciseBatchN..." /
/// "...VerificationUITests" verification tests.
final class ExerciseFilterVerificationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testExercisesTabSearchBarAndFilterSheet() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES",
            "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES",
            "-auth.provider", "guest"
        ]
        app.launch()

        let exercisesTab = app.descendants(matching: .any)["Exercises"].firstMatch
        XCTAssertTrue(exercisesTab.waitForExistence(timeout: 10))
        exercisesTab.tap()

        // Give the glass search bar + header a moment to render.
        let filterButton = app.buttons["exerciseFilterButton"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 10))

        attach(app.screenshot(), name: "01-exercises-tab-glass-search-bar")

        filterButton.tap()

        let easierChip = app.buttons["Easier"]
        XCTAssertTrue(easierChip.waitForExistence(timeout: 5))
        attach(app.screenshot(), name: "02-filter-sheet-default")

        easierChip.tap()
        app.buttons["Under 1 min"].tap()
        attach(app.screenshot(), name: "03-filter-sheet-easier-and-under1min-selected")

        app.buttons["Done"].tap()
        attach(app.screenshot(), name: "04-exercises-tab-with-active-filters")
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
