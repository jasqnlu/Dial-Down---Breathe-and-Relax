import XCTest

/// Captures the screenshots in the repo's `App Screenshots/` folder. Skipped in normal
/// runs; generate with:
///
///     TEST_RUNNER_APP_SCREENSHOTS=1 xcodebuild test … \
///       -only-testing:"Breath - Relax & StretchUITests/AppScreenshotsUITests" \
///       -resultBundlePath shots.xcresult
///     xcrun xcresulttool export attachments --path shots.xcresult --output-path out
///
/// Each attachment is named after the file it becomes (e.g. "01-today").
final class AppScreenshotsUITests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["APP_SCREENSHOTS"] == "1",
                          "Set TEST_RUNNER_APP_SCREENSHOTS=1 to capture app screenshots")
        continueAfterFailure = true
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES", "-auth.provider", "guest",
            "-appLanguage", "en",
        ]
        app.launch()
        let notNow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Not Now"]
        if notNow.waitForExistence(timeout: 4) { notNow.tap() }
        return app
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 1.2)   // let springs and images settle
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTabs() {
        let app = launch()
        XCTAssertTrue(app.buttons["ask.button"].waitForExistence(timeout: 20))
        shoot(app, "01-today")
        for (index, tab) in ["Exercises", "Breathe", "Routines", "Profile"].enumerated() {
            app.buttons[tab].firstMatch.tap()
            shoot(app, String(format: "%02d-%@", index + 2, tab.lowercased()))
        }
    }

    func testAskSideChat() {
        let app = launch()
        let button = app.buttons["ask.button"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        button.tap()
        let field = app.textFields["ask.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("3 exercises for my lower back")
        shoot(app, "10-ask-bar")
        field.typeText("\n")

        XCTAssertTrue(app.staticTexts["ask.trayTotal"].waitForExistence(timeout: 20))
        let input = app.textFields["ask.input"]
        for _ in 0..<3 where !((input.value(forKey: "hasKeyboardFocus") as? Bool) ?? false) {
            input.tap()
            Thread.sleep(forTimeInterval: 1)
        }
        input.typeText("2 for my neck\n")
        let five = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '5 exercises'")).firstMatch
        XCTAssertTrue(five.waitForExistence(timeout: 20))
        shoot(app, "11-ask-side-chat")

        app.buttons["ask.resize"].tap()
        shoot(app, "12-ask-full-screen")

        app.buttons["ask.customize"].tap()
        XCTAssertTrue(app.buttons["customize.addMore"].waitForExistence(timeout: 5))
        shoot(app, "13-ask-customize")
        app.buttons["customize.addMore"].tap()

        XCTAssertTrue(app.buttons["ask.shrink"].waitForExistence(timeout: 5))
        app.buttons["ask.shrink"].tap()
        XCTAssertTrue(app.buttons["ask.pill"].waitForExistence(timeout: 5))
        shoot(app, "14-ask-pill")

        app.buttons["ask.pill"].tap()
        XCTAssertTrue(app.buttons["ask.close"].waitForExistence(timeout: 5))
        app.buttons["ask.close"].tap()
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        shoot(app, "15-ask-closed-badge")
    }
}
