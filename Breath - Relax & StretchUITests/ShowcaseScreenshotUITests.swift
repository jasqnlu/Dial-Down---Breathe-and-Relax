import XCTest

/// Not an assertion test — a repeatable way to regenerate the onboarding
/// showcase screenshots straight from the app. Export the attachments with
/// `xcrun xcresulttool export attachments` (see .claude/skills/verify/SKILL.md).
final class ShowcaseScreenshotUITests: XCTestCase {

    func testCaptureShowcaseScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "YES",
            // Legacy global flag: RegistrationGate migrates it to the guest's
            // per-account flag, so the coach-mark tour stays out of the shots.
            "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES", "-auth.provider", "guest",
        ]
        app.launch()

        // Body is a view inside the Exercises tab now. Ends on Areas, since
        // the switch's choice is saved and later tests expect Areas.
        capture(app, tab: "Exercises", mode: "body", name: "showcase-bodymap", settle: 6) // 3D model warm-up
        capture(app, tab: "Exercises", mode: "areas", name: "showcase-exercises", settle: 2)
        capture(app, tab: "Routines", name: "showcase-routines", settle: 2)
    }

    private func capture(_ app: XCUIApplication, tab: String, mode: String? = nil, name: String, settle: TimeInterval) {
        let button = app.buttons[tab]
        XCTAssertTrue(button.waitForExistence(timeout: 15), "Missing tab button \(tab)")
        button.tap()
        if let mode {
            let modeButton = app.buttons["exercisesMode.\(mode)"].firstMatch
            XCTAssertTrue(modeButton.waitForExistence(timeout: 5), "Missing Areas / Body switch")
            modeButton.tap()
        }
        Thread.sleep(forTimeInterval: settle)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
