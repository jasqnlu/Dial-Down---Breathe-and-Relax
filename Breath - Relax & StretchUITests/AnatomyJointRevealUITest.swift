import XCTest

/// Focused check: tapping a joint region (hip) — hitbox-only, no rendered
/// geometry — resolves to its crossing muscles as candidates, same as a
/// muscle-group tap.
final class AnatomyJointRevealUITest: XCTestCase {

    func testHipTapResolvesToCrossingMuscles() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "YES",
            "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES",
            "-auth.provider", "guest",
        ]
        // Body lives behind the Exercises tab's Areas / Body switch; this opens
        // it on Body without tapping (a tap would save the choice for later tests).
        app.launchArguments += ["-exercisesMode", "body"]
        app.launch()

        let bodyTab = app.buttons["Exercises"].firstMatch
        XCTAssertTrue(bodyTab.waitForExistence(timeout: 15), "Body tab not found")
        bodyTab.tap()
        sleep(6) // let the 13MB OBJ finish parsing before tapping

        // Hip joint hitbox (real Z-Anatomy capsule geometry) is a small box
        // right at waist height.
        let scene = app.otherElements.firstMatch
        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.58, dy: 0.435)).press(forDuration: 0.05)
        attach(app, "01-hip-pending")

        XCTAssertTrue(app.staticTexts["Which area did you mean?"].waitForExistence(timeout: 8),
                      "A hip tap should resolve to its crossing muscles")
        sleep(2)
        attach(app, "02-hip-reveal")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
