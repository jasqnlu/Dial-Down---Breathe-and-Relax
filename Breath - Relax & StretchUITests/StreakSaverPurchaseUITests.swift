import XCTest

final class StreakSaverPurchaseUITests: XCTestCase {

    private func launch(points: Int, spent: Int = 0, savers: Int, streak: Int = 5, daysAgo: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
                                "-auth.anonymousID", "streak-saver-uitest",
                                "-auth.isSignedIn", "YES", "-auth.provider", "guest",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                                "-uiTestSeedPoints", "\(points)", "-uiTestSeedSpent", "\(spent)",
                                "-uiTestSeedSavers", "\(savers)", "-uiTestSeedStreak", "\(streak)",
                                "-uiTestSeedBreakDaysAgo", "\(daysAgo)"]
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func openSettings(_ app: XCUIApplication) {
        let profileTab = app.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 20))
        profileTab.tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.buySaver"].waitForExistence(timeout: 5))
    }

    func testBlockedUnderCostAndAtMax() {
        var app = launch(points: 100, savers: 1, daysAgo: 0)
        openSettings(app)
        XCTAssertFalse(app.buttons["settings.buySaver"].isEnabled)
        attach(app, "1a-need-more-points")
        app.terminate()

        app = launch(points: 900, savers: 3, daysAgo: 0)
        openSettings(app)
        XCTAssertFalse(app.buttons["settings.buySaver"].isEnabled)
        attach(app, "1b-at-max")
    }

    func testPurchaseFromSettings() {
        let app = launch(points: 200, savers: 0, daysAgo: 0)
        openSettings(app)
        let buy = app.buttons["settings.buySaver"]
        XCTAssertTrue(buy.isEnabled)
        attach(app, "2a-before")
        buy.tap()
        _ = app.buttons["Buy Saver"].waitForExistence(timeout: 5)
        attach(app, "2b-dialog")
        app.buttons["Buy Saver"].tap()
        XCTAssertTrue(app.staticTexts["1 / 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["50"].exists)
        attach(app, "2c-after")
    }

    func testBuyAndRestoreFromStreakLostAlert() {
        let app = launch(points: 200, savers: 0, daysAgo: 3)
        let restore = app.buttons["Buy & Restore (150 pts)"]
        XCTAssertTrue(restore.waitForExistence(timeout: 20))
        attach(app, "3a-alert")
        restore.tap()
        XCTAssertTrue(restore.waitForNonExistence(timeout: 5))
        attach(app, "3b-restored")
    }
}
