import XCTest

/// Walks the whole coach-mark tour as a new guest would — welcome card,
/// every tab's spotlight steps, the three tap-to-continue steps, and the
/// finish card — attaching a screenshot at each stop for visual review.
final class AppTourWalkthroughUITests: XCTestCase {

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testWalkThroughEveryTourStep() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // A fresh guest account id, so the per-account "seen the tour" flag
        // is unset and the tour starts on Home.
        app.launchArguments += ["-hasCompletedOnboarding", "YES",
                                "-auth.anonymousID", UUID().uuidString,
                                "-auth.isSignedIn", "YES",
                                "-auth.provider", "guest"]
        app.launch()

        let start = app.buttons["Show Me Around"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "Tour should open on the welcome card")
        sleep(1)
        attach(app, "00-welcome")
        start.tap()

        let next = app.buttons["Next"]
        var shot = 1
        func nextStep(_ name: String) {
            XCTAssertTrue(next.waitForExistence(timeout: 10), "Next should show on \(name)")
            sleep(1)
            attach(app, String(format: "%02d-%@", shot, name))
            shot += 1
            next.tap()
        }

        // Today
        nextStep("today-hero")
        nextStep("today-recommended")

        // Exercises
        nextStep("exercises-search")
        nextStep("exercises-areas")

        // Switch to the Body — waits for the Body tap.
        XCTAssertTrue(app.staticTexts["Switch to the Body"].waitForExistence(timeout: 10))
        sleep(1)
        attach(app, String(format: "%02d-exercises-switch", shot)); shot += 1
        app.buttons["exercisesMode.body"].firstMatch.tap()

        // Tap a sore spot — waits for a tap on the body.
        XCTAssertTrue(app.staticTexts["Tap a Sore Spot"].waitForExistence(timeout: 10))
        sleep(6) // 3D model loads on first show
        attach(app, String(format: "%02d-body-tap", shot)); shot += 1
        app.otherElements.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.42)).tap()

        // Find Stretches — pick the focused muscle, then tap the bar.
        XCTAssertTrue(app.staticTexts["Find Stretches"].waitForExistence(timeout: 10))
        sleep(1)
        attach(app, String(format: "%02d-body-find", shot)); shot += 1
        let focused = app.buttons.matching(NSPredicate(format: "label ENDSWITH ' — view exercises'")).firstMatch
        if focused.waitForExistence(timeout: 5) {
            focused.tap()
        } else {
            app.buttons["bodymap.regionActionBar"].firstMatch.tap()
        }

        // Breathe, Routines, Profile
        nextStep("breathe-patterns")
        nextStep("breathe-preview")
        nextStep("routines-premade")
        nextStep("routines-yours")
        nextStep("profile-stats")

        let finish = app.buttons["Start Exploring"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "Tour should end on the finish card")
        sleep(1)
        attach(app, String(format: "%02d-finish", shot))
        finish.tap()
        XCTAssertFalse(app.descendants(matching: .any)["Exit tour"].waitForExistence(timeout: 2), "Tour should be closed")
    }
}
