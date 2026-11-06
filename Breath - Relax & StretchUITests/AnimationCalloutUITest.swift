import XCTest

/// Verifies the animation-instruction-callout overlay reaches the accessibility
/// tree on the exercise detail screen for a seeded example ("Wrist Circles",
/// authored with a `.rotate` callout — see SeedData.json and
/// docs/superpowers/specs/2026-09-06-exercise-animation-instruction-callouts-design.md).
/// The overlay's `accessibilityLabel` is exposed independent of the fade
/// timing, so it's the reliable thing to assert on here rather than a
/// screenshot at some particular loop offset (see `AnimationDemoUITest` for
/// the screenshot-based pattern used for the animations themselves).
final class AnimationCalloutUITest: XCTestCase {

    func testWristCirclesShowsCalloutInstructionOnDetail() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-hasCompletedOnboarding", "YES",
            "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES",
            "-auth.provider", "guest",
        ]
        app.launch()

        let exercisesTab = app.descendants(matching: .any)["Exercises"].firstMatch
        XCTAssertTrue(exercisesTab.waitForExistence(timeout: 15), "Exercises tab not found")
        exercisesTab.tap()

        let search = app.textFields["Search exercises"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "Search field not found")
        search.tap()
        search.typeText("Wrist Circles")

        let rowPredicate = NSPredicate(format: "label BEGINSWITH %@", "Wrist Circles")
        let row = app.descendants(matching: .any).matching(rowPredicate).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Wrist Circles row not found")
        row.tap()

        // The callout's accessibilityLabel is the authored instruction text,
        // persistent regardless of the fade envelope's current opacity.
        let callout = app.descendants(matching: .any)["Rotate your wrists in a circle"].firstMatch
        XCTAssertTrue(callout.waitForExistence(timeout: 8), "Animation callout instruction not found")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "01-wrist-circles-callout"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
