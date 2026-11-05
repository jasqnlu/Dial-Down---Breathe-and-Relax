import XCTest

/// End-to-end coverage for the floating Ask button: tap → ask bar → type →
/// chat sheet. On the simulator Apple Intelligence is usually unavailable, so
/// the keyword path answers — which is what these assertions rely on.
final class AskFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES", "-auth.provider", "guest",
            "-appLanguage", "en",
        ]
        app.launch()
        dismissSystemAlerts()
        return app
    }

    /// The simulator sometimes shows a system "Apple Account Verification"
    /// alert over the app, which swallows every tap. Dismiss it if present.
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notNow = springboard.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 4) { notNow.tap() }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Taps the floating button, types `text` into the ask bar and submits.
    private func ask(_ text: String, in app: XCUIApplication) {
        let button = app.buttons["ask.button"]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "Ask button not found")
        attach(app, "1-resting")
        button.tap()

        let field = app.textFields["ask.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Ask field not found")
        XCTAssertTrue(app.buttons["ask.mic"].exists, "Ask bar mic not found")
        field.typeText(text)
        attach(app, "2-bar")
        field.typeText("\n")

        let sheet = app.descendants(matching: .any)["ask.sheet"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "Chat sheet not presented")
    }

    func testTypeLowerBackShowsRoutine() throws {
        let app = launch()
        ask("lower back pain", in: app)
        XCTAssertTrue(app.buttons["ask.start"].waitForExistence(timeout: 20), "Routine Start button not shown")
        attach(app, "3-routine")
    }

    func testUrgentShowsNoStart() throws {
        let app = launch()
        ask("chest pain", in: app)
        XCTAssertTrue(app.buttons["ask.emergency"].waitForExistence(timeout: 20), "Emergency button not shown")
        XCTAssertFalse(app.buttons["ask.start"].exists, "Urgent reply must not offer Start")
        attach(app, "4-urgent")
    }
}
