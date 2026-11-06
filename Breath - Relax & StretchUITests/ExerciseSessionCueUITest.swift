import XCTest

final class ExerciseSessionCueUITest: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Starts a session and confirms both the cue badge and the instruction
    /// text render during the first exercise. Per the repo's `verify` skill,
    /// elements with an explicit combined `.accessibilityLabel` are queried
    /// by that label via `descendants`, not by the raw displayed text.
    func testCueBadgeAndInstructionAppearDuringExercise() throws {
        let app = XCUIApplication()
        // Per the repo's `verify` skill: skip onboarding/auth via launch
        // arguments so a fresh install lands straight on the Today tab
        // (where "Begin" lives) instead of the app-guide carousel.
        app.launchArguments += [
            "-carousel.paused", "YES", "-hasCompletedOnboarding", "YES",
            "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES",
            "-auth.provider", "guest",
        ]
        app.launch()

        // The Today screen's start button has a dynamic combined
        // accessibilityLabel ("Begin today's session: N exercises, M
        // minutes") rather than a plain "Begin" identifier, so it must be
        // matched by label prefix rather than `app.buttons["Begin"]`.
        let beginPredicate = NSPredicate(format: "label BEGINSWITH %@", "Begin")
        let beginButton = app.buttons.matching(beginPredicate).firstMatch
        if beginButton.waitForExistence(timeout: 5) {
            beginButton.tap()
        }

        // The session inserts a 3s "Get Ready" countdown screen before the
        // actual exercise (with the cue badge) appears, so the wait needs
        // headroom beyond that countdown plus navigation animation.
        //
        // The badge's Text carries `.textCase(.uppercase)`, and that
        // uppercasing bleeds into the accessibility label iOS reports to
        // XCUITest ("EXERCISE CUE") even though the source sets the exact
        // string "Exercise cue" via `.accessibilityLabel(...)` — so this
        // is matched case-insensitively rather than via the exact subscript.
        let cueBadgePredicate = NSPredicate(format: "label ==[c] %@", "Exercise cue")
        let cueBadge = app.descendants(matching: .any).matching(cueBadgePredicate).firstMatch
        XCTAssertTrue(cueBadge.waitForExistence(timeout: 15), "Cue badge should appear during the exercise")

        let instruction = app.descendants(matching: .any)["Exercise instruction"]
        XCTAssertTrue(instruction.exists, "Instruction cue should appear alongside the badge")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        screenshot.name = "01-exercise-with-cues"
        add(screenshot)
    }
}
