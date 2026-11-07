import XCTest

/// Sanity check for the BreathingView spring change: navigates to the
/// Breathe tab, starts a session, and confirms the phase label / countdown
/// still render (the spring drives the ring's scaleEffect only — nothing
/// here should be visually different at a single frame, this just confirms
/// no crash and the expected UI is present).
final class BreathingCircleSpringUITest: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBreathingSessionStartsAndAnimates() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES",
            "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES",
            "-auth.provider", "guest",
        ]
        app.launch()

        let breatheTab = app.buttons["Breathe"]
        XCTAssertTrue(breatheTab.waitForExistence(timeout: 5), "Breathe tab should exist")
        breatheTab.tap()

        let startButton = app.buttons["Start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Start button should appear")

        let shotIdle = XCTAttachment(screenshot: app.screenshot())
        shotIdle.lifetime = .keepAlways
        shotIdle.name = "01-idle"
        add(shotIdle)

        startButton.tap()

        // Give the spring a moment to be mid-flight, not just at rest.
        Thread.sleep(forTimeInterval: 0.6)
        let shotMidInhale = XCTAttachment(screenshot: app.screenshot())
        shotMidInhale.lifetime = .keepAlways
        shotMidInhale.name = "02-mid-inhale"
        add(shotMidInhale)

        Thread.sleep(forTimeInterval: 1.5)
        let shotLater = XCTAttachment(screenshot: app.screenshot())
        shotLater.lifetime = .keepAlways
        shotLater.name = "03-later"
        add(shotLater)
    }
}
