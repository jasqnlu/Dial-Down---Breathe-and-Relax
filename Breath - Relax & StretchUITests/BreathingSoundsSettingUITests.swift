import XCTest

/// Settings → Session has a Breathing Sounds switch that turns the Breathe
/// tab's inhale/hold/exhale sounds off and on.
final class BreathingSoundsSettingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBreathingSoundsSwitchToggles() throws {
        let app = XCUIApplication()
        // No -breathingSoundsEnabled argument: a launch argument would shadow
        // the switch's own writes and it could never change.
        app.launchArguments += [
            "-carousel.paused", "YES", "-appLanguage", "en",
            "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES", "-auth.provider", "guest",
        ]
        app.launch()

        let profileTab = app.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 20))
        profileTab.tap()
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        let toggle = app.switches["settings.breathingSounds"].firstMatch
        var swipes = 0
        while !(toggle.exists && toggle.isHittable), swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(toggle.isHittable, "Breathing Sounds switch not found in Settings")
        XCTAssertTrue(toggle.label.contains("Breathing Sounds"))

        let before = toggle.value as? String
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        let flipped = NSPredicate { _, _ in (toggle.value as? String) != before }
        wait(for: [XCTNSPredicateExpectation(predicate: flipped, object: nil)], timeout: 5)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "breathing-sounds-switch"; shot.lifetime = .keepAlways; add(shot)

        // Leave it as it was for the next test.
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
    }
}
