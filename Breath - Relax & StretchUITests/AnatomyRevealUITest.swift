import XCTest

/// Drives the skin-covered Body Map's tap-to-open muscle picker and captures
/// the key visual states for review: a clean skin-covered resting figure, a
/// chest tap reveal (skin fades, candidates colorize, no arm), Cancel (skin
/// fades back in), and a joint tap (hip) that resolves to its crossing
/// muscles.
final class AnatomyRevealUITest: XCTestCase {

    func testSkinModelRendersAndReveals() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-hasCompletedOnboarding", "YES",
            "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES",
            "-auth.provider", "guest",
        ]
        // Body lives behind the Exercises tab's Areas / Body switch; this opens
        // it on Body without tapping (a tap would save the choice for later tests).
        app.launchArguments += ["-exercisesMode", "body"]
        app.launch()

        // Body tab → resting figure (should read as a clean skin-covered
        // body: no patch seams, no groin hole, no half-grey seam).
        let bodyTab = app.buttons["Exercises"].firstMatch
        XCTAssertTrue(bodyTab.waitForExistence(timeout: 15), "Body tab not found")
        bodyTab.tap()
        sleep(6) // OBJ parses off-main
        attach(app, "01-resting-skin")

        let scene = app.otherElements.firstMatch
        let disambiguationHint = app.staticTexts["Which area did you mean?"]

        // Tap the chest → skin fades, grayscale muscles appear, candidates
        // colorize.
        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).press(forDuration: 0.05)
        XCTAssertTrue(disambiguationHint.waitForExistence(timeout: 8),
                      "A chest tap should reveal the muscle candidates")
        sleep(3)
        attach(app, "04-chest-reveal")

        // Dismiss → skin should fade back in (muscle hidden again).
        let cancel = app.buttons["Cancel"]
        if cancel.waitForExistence(timeout: 3) { cancel.tap() }
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: disambiguationHint)
        waitForExpectations(timeout: 5)
        attach(app, "05-dismissed-skin-restored")

        // Tap near the hip (joint region, hitbox-only — no rendered
        // geometry) → resolves to the joint's crossing muscles as candidates.
        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.58, dy: 0.435)).press(forDuration: 0.05)
        XCTAssertTrue(disambiguationHint.waitForExistence(timeout: 8),
                      "A hip tap should resolve to its crossing muscles")
        sleep(3)
        attach(app, "07-hip-reveal")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
