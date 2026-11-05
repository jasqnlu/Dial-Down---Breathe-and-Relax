import XCTest

/// Drives the Body Map's tap-to-open muscle picker directly and captures the
/// muscle-layer reveal for visual review against
/// docs/mockups/bodymap-muscle-reveal.html.
final class MuscleRevealUITest: XCTestCase {

    func testMuscleLayerRevealOnTap() {
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

        // Body tab.
        let bodyTab = app.buttons["Exercises"].firstMatch
        XCTAssertTrue(bodyTab.waitForExistence(timeout: 15), "Body tab not found")
        bodyTab.tap()
        sleep(6) // 3D model loads off-main
        attach(app, "01-body-map")

        // Tap the chest — reliably yields several muscle candidates
        // (Left/Right Chest + Upper/Lower Chest heads).
        let scene = app.otherElements.firstMatch
        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).press(forDuration: 0.05)

        XCTAssertTrue(app.staticTexts["Which area did you mean?"].waitForExistence(timeout: 8),
                      "A chest tap should open the muscle-selection overlay")
        sleep(3) // first-load: 13MB muscle OBJ parse (~2.7s) + fade (0.5s)
        attach(app, "04-muscle-reveal")

        sleep(4) // generous settle to fully rule out first-load parse timing
        attach(app, "05-muscle-reveal-settled")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
