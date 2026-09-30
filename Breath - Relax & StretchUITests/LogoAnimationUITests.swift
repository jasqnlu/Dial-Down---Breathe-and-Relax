import XCTest

/// Visual verification for the Dial Down logo mark on the onboarding Welcome
/// page (breathing hero). Two screenshots ~2 s apart show the breath cycle;
/// export them from the .xcresult to inspect.
///
/// The splash intro isn't asserted here: the splash is only guaranteed for
/// 1.5 s and XCUITest's launch + wait-for-idle often outlasts it (the same
/// race makes AppLoadingViewUITest flaky on main). Verify the intro with a
/// simulator recording instead: `xcrun simctl io "iPhone 17" recordVideo`.
final class LogoAnimationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWelcomeHeroBreathes() throws {
        let app = XCUIApplication()
        app.launch()

        // Fresh install lands on the onboarding Language page; Next leads to
        // the Welcome page, which hosts the breathing hero mark.
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15), "Onboarding should show a Next button")
        next.tap()
        Thread.sleep(forTimeInterval: 1.0)

        for index in 1...2 {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.lifetime = .keepAlways
            shot.name = "welcome-\(index)"
            add(shot)
            Thread.sleep(forTimeInterval: 2.0)
        }
    }
}
