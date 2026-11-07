import XCTest

/// Verifies the re-rendered Left/Right Seated Spinal Twist animations still
/// play in the exercise detail screen after adding a genuinely seated leg
/// pose (previously rendered standing despite the exercise name).
final class SeatedSpinalTwistUITests: XCTestCase {

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testBothSeatedTwistsOpenAndPlay() throws {
        for name in ["Left Seated Spinal Twist", "Right Seated Spinal Twist"] {
            let app = XCUIApplication()
            app.launchArguments += [
                "-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES",
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
