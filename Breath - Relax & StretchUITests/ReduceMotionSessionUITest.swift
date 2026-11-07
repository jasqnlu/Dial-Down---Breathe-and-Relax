import XCTest

/// Verifies the SessionPlayerView Reduce Motion fixes: the app should launch
/// and render a session's cue badge / instruction cue without crashing under
/// `UIAccessibility.isReduceMotionEnabled`. The simulator's Reduce Motion
/// setting is toggled from outside the test (via `simctl spawn ... defaults
/// write com.apple.Accessibility ReduceMotionEnabled`) before this runs, so
/// there's nothing to set here — SwiftUI's `accessibilityReduceMotion`
/// environment key picks it up at launch.
final class ReduceMotionSessionUITest: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSessionRendersUnderCurrentReduceMotionSetting() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES",
            "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES",
            "-auth.provider", "guest",
        ]
        app.launch()

        let beginPredicate = NSPredicate(format: "label BEGINSWITH %@", "Begin")
        let beginButton = app.buttons.matching(beginPredicate).firstMatch
        if beginButton.waitForExistence(timeout: 5) {
            beginButton.tap()
        }

        let cueBadgePredicate = NSPredicate(format: "label ==[c] %@", "Exercise cue")
        let cueBadge = app.descendants(matching: .any).matching(cueBadgePredicate).firstMatch
        XCTAssertTrue(cueBadge.waitForExistence(timeout: 15), "Cue badge should appear during the exercise")

        let instruction = app.descendants(matching: .any)["Exercise instruction"]
        XCTAssertTrue(instruction.exists, "Instruction cue should appear alongside the badge")

        let shot1 = XCTAttachment(screenshot: app.screenshot())
        shot1.lifetime = .keepAlways
        shot1.name = "01-session-frame-a"
        add(shot1)

        Thread.sleep(forTimeInterval: 1.5)

        let shot2 = XCTAttachment(screenshot: app.screenshot())
        shot2.lifetime = .keepAlways
        shot2.name = "02-session-frame-b"
        add(shot2)
    }
}
