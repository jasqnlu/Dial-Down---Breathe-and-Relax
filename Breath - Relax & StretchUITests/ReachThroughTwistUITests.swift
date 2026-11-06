import XCTest

/// Verifies the Standing Reach-Through Twist animations (L/R), shipped
/// 2026-08-09 after three earlier authoring passes failed to make the
/// cross-body reach read without local-Z adduction tearing the torso mesh —
/// see left_standing_reach_through_twist.py's docstring for the fix (pure
/// local-X flexion instead, letting the torso twist carry the arm across).
final class ReachThroughTwistUITests: XCTestCase {

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testBothReachThroughTwistsOpenAndPlay() throws {
        for name in ["Left Standing Reach-Through Twist", "Right Standing Reach-Through Twist"] {
            let app = XCUIApplication()
            app.launchArguments += [
                "-carousel.paused", "YES", "-hasCompletedOnboarding", "YES",
                "-hasSeenAppGuide", "YES",
                "-auth.isSignedIn", "YES",
                "-auth.provider", "guest",
            ]
            app.launch()

            let exercisesTab = app.descendants(matching: .any)["Exercises"].firstMatch
            XCTAssertTrue(exercisesTab.waitForExistence(timeout: 15), "Exercises tab not found")
            exercisesTab.tap()

            let search = app.textFields["Search exercises"]
            XCTAssertTrue(search.waitForExistence(timeout: 10), "Search field not found")
            search.tap()
            search.typeText(name)

            let row = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", name))
                .firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 8), "\(name) row not found")
            row.tap()

            Thread.sleep(forTimeInterval: 1.5)
            attach(app, name)
            app.terminate()
        }
    }
}
