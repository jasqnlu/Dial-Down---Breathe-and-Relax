import XCTest

final class RegistrationFlowUITests: XCTestCase {

    /// Launches with a full baseline (every key a test depends on) and a FRESH
    /// random anonymousID, so the per-account tour flag `hasSeenAppGuide.<id>`
    /// is unset by construction. Each test overrides only what it needs; later
    /// duplicate `-key value` pairs win, so `extra` is appended after the baseline.
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let baseline = ["-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES",
                        "-auth.anonymousID", UUID().uuidString,
                        "-auth.isSignedIn", "YES",
                        "-auth.provider", "email",
                        "-auth.displayName", "",
                        "-auth.firstName", "",
                        "-auth.lastName", ""]
        app.launchArguments += baseline + extra
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func tourExit(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["Exit tour"]
    }

    /// Registered-only evidence: the Home greeting contains the first name
    /// (prefix is time-of-day dependent, e.g. "Time to unwind, Ada").
    private func greeting(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", ", Ada")).firstMatch
    }

    /// Legacy single-string name, no stored first/last: name step, prefilled,
    /// then Home with the first-name greeting and the tour starting.
    func testUnregisteredAccountSeesPrefilledNameStepThenHomeAndTour() {
        let app = launch(["-auth.displayName", "Ada Lovelace"])
        let first = app.textFields["First name"]
        XCTAssertTrue(first.waitForExistence(timeout: 20), "Name step should appear")
        XCTAssertEqual(first.value as? String, "Ada")
        XCTAssertEqual(app.textFields["Last name"].value as? String, "Lovelace")
        attach(app, "1-name-step")

        app.buttons["Continue"].tap()
        XCTAssertTrue(greeting(app).waitForExistence(timeout: 10), "Home greeting with first name should follow")
        XCTAssertTrue(tourExit(app).waitForExistence(timeout: 10), "Tour should start after the name step")
        attach(app, "2-home-tour-after-name")
    }

    /// The name step is not a dead end: "Not you?" signs out to the sign-in screen.
    func testNameStepOffersSignOutBackToSignIn() {
        let app = launch(["-auth.displayName", "Ada Lovelace"])
        XCTAssertTrue(app.textFields["First name"].waitForExistence(timeout: 20), "Name step should appear")
        let notYou = app.buttons["Not you? Use a different account"]
        XCTAssertTrue(notYou.waitForExistence(timeout: 5))
        notYou.tap()
        XCTAssertTrue(app.buttons["Start breathing"].waitForExistence(timeout: 15), "Sign-in screen should appear")
        XCTAssertFalse(app.textFields["First name"].exists)
        attach(app, "2b-signed-out")
    }

    /// A complete stored name means registered: Home, no name step, and NO tour
    /// even though this account's tour flag is unseen (returning account).
    func testRegisteredAccountSkipsNameStepAndTour() {
        let app = launch(["-auth.firstName", "Ada", "-auth.lastName", "Lovelace",
                          "-auth.displayName", "Ada Lovelace"])
        XCTAssertTrue(greeting(app).waitForExistence(timeout: 20), "Registered Home greeting should appear")
        XCTAssertFalse(app.textFields["First name"].exists, "Name step must be absent")
        XCTAssertFalse(tourExit(app).waitForExistence(timeout: 3), "Registered account must not get the tour")
        attach(app, "3-registered-home")
    }

    /// Guests never see the name step but still get the tour once.
    func testGuestSkipsNameStepButGetsTour() {
        let app = launch(["-auth.provider", "guest"])
        XCTAssertTrue(tourExit(app).waitForExistence(timeout: 15), "Guest should get the tour once")
        XCTAssertFalse(app.textFields["First name"].exists)
        attach(app, "3b-guest-tour")
    }

    /// Fresh install: showcase pages appear, Skip jumps to the goal picker.
    func testFreshInstallShowsShowcaseAndSkipWorks() {
        let app = XCUIApplication()
        app.launchArguments += ["-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "NO",
                                "-auth.isSignedIn", "NO",
                                "-auth.anonymousID", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 15))
        app.buttons["Next"].tap()                       // language -> welcome
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
        app.buttons["Next"].tap()                       // -> showcase 1
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        attach(app, "4-showcase-1")
        app.buttons["Skip"].tap()                       // -> goals page
        XCTAssertTrue(app.staticTexts["What brings you here?"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Skip"].exists)
        attach(app, "5-after-skip")
    }
}
