import XCTest

/// Simulator verification for the muscle picker: a tap opens the
/// muscle-selection overlay directly (camera dolly, skin fade, ≤4 candidate
/// muscles on a labelled rail) — no Mark mode, no colour, no checkmark — and
/// Cancel closes it without navigating, staying zoomed on the region rather
/// than resetting to the plain body.
final class BodyMapMusclePickerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchBodyTab(extraArgs: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "YES",
                                "-hasSeenAppGuide", "YES",
                                "-auth.isSignedIn", "YES",
                                "-auth.provider", "guest"]
        app.launchArguments += extraArgs
        app.launchArguments += ["-exercisesMode", "body"]
        app.launch()
        // Body lives behind the Exercises tab's Areas / Body switch. The
        // `-exercisesMode body` launch argument opens it on Body without a
        // tap — tapping the switch would save the choice into later tests.
        let bodyTab = app.buttons["Exercises"].firstMatch
        _ = bodyTab.waitForExistence(timeout: 30)
        bodyTab.tap()
        sleep(6) // async OBJ parse
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// A tap opens the muscle picker directly — no Mark mode, no colour, no
    /// checkmark.
    @MainActor
    func testTapOpensTheMusclePicker() throws {
        let app = launchBodyTab(extraArgs: [])
        attach(app, "01-body-at-rest")

        let scene = app.otherElements.firstMatch
        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.42)).press(forDuration: 0.05)

        // The picker replaces the facing toggle with a Cancel affordance and
        // the "Which area did you mean?" prompt.
        XCTAssertTrue(app.staticTexts["Which area did you mean?"].waitForExistence(timeout: 8),
                      "A tap should open the muscle-selection overlay")
        attach(app, "02-muscle-picker")

        XCTAssertTrue(app.buttons["Cancel"].exists,
                      "The picker should offer a way out")
    }

    /// Cancelling the picker closes it (and lands on the zoomed region's
    /// "Stretches for…" bar) without navigating.
    @MainActor
    func testCancellingThePickerClosesItWithoutNavigating() throws {
        let app = launchBodyTab(extraArgs: [])
        let scene = app.otherElements.firstMatch
        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.42)).press(forDuration: 0.05)
        XCTAssertTrue(app.staticTexts["Which area did you mean?"].waitForExistence(timeout: 8))

        app.buttons["Cancel"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.staticTexts["Which area did you mean?"])
        waitForExpectations(timeout: 5)
        attach(app, "03-back-to-body")

        XCTAssertTrue(app.buttons["bodymap.regionActionBar"].waitForExistence(timeout: 5),
                      "Cancel should land back on the zoomed region's action bar, not a full reset")
        XCTAssertTrue(app.staticTexts["3D body map"].exists,
                      "Cancel should not navigate anywhere")
    }

    /// Follows the tap-to-picker path all the way to a candidate: focus an
    /// unfocused rail label, confirm its accessibility label flips from
    /// "— highlight region" to "— view exercises", then tap it again to
    /// drill into its stretch list. Deliberately targets an UNFOCUSED
    /// candidate rather than the auto-focused first one
    /// (`focusedRegion = pins.first?.name` on open) — this exercises both
    /// halves of `handleCandidateTap`'s focus/select branch instead of only
    /// the already-focused half, which is strictly more coverage.
    @MainActor
    func testTappingACandidateFocusesThenSelectsIt() throws {
        let app = launchBodyTab(extraArgs: [])
        let scene = app.otherElements.firstMatch
        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.42)).press(forDuration: 0.05)
        XCTAssertTrue(app.staticTexts["Which area did you mean?"].waitForExistence(timeout: 8))
        attach(app, "04-picker-open")

        let unfocused = app.buttons.matching(
            NSPredicate(format: "label ENDSWITH '— highlight region'")
        ).firstMatch
        XCTAssertTrue(unfocused.waitForExistence(timeout: 5),
                      "Expected at least one unfocused candidate on the rail")
        let fullLabel = unfocused.label
        let name = String(fullLabel.dropLast(" — highlight region".count))

        unfocused.tap()

        let focused = app.buttons["\(name) — view exercises"]
        XCTAssertTrue(focused.waitForExistence(timeout: 5),
                      "Tapping an unfocused candidate should flip its label to '— view exercises'")
        attach(app, "05-candidate-focused")

        focused.tap()

        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5),
                      "Tapping the now-focused candidate should push the stretch list for '\(name)'")
        attach(app, "06-candidate-stretch-list")
    }

    /// Tapping empty space outside the body's silhouette, while the muscle
    /// picker is open, behaves like tapping Cancel: the picker goes away —
    /// without navigating to a stretch list — but the camera STAYS on the
    /// zoomed region (landing on the action bar), one level back rather than
    /// a full reset. A SECOND outside tap, from that now-unfocused zoomed
    /// state, is what actually zooms the camera back out.
    @MainActor
    func testTapOutsideBodyClosesThePickerThenZoomsOutOnASecondTap() throws {
        let app = launchBodyTab(extraArgs: [])
        let scene = app.otherElements.firstMatch
        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.42)).press(forDuration: 0.05)
        XCTAssertTrue(app.staticTexts["Which area did you mean?"].waitForExistence(timeout: 8))
        attach(app, "07-picker-open")

        // Tap empty space inside the scene view, off to the side of the
        // (zoomed-in, centered) body.
        let outside = scene.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.45))
        outside.press(forDuration: 0.05)
        attach(app, "08-after-outside-tap")

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.staticTexts["Which area did you mean?"])
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.staticTexts["3D body map"].exists,
                      "Should still be on Body Map, not navigated to a stretch list")

        // Must STAY gone, not just disappear momentarily — an
        // `expectation(for:)` above only proves it vanished at some point in
        // the window, not that it stuck. Checked repeatedly.
        for _ in 0..<6 {
            usleep(200_000)
            XCTAssertFalse(app.staticTexts["Which area did you mean?"].exists,
                           "The picker should not reappear after this tap")
        }

        // Landed one level back, not a full reset: the region's action bar
        // is still up.
        XCTAssertTrue(app.buttons["bodymap.regionActionBar"].waitForExistence(timeout: 5),
                      "Closing the picker with an outside tap should land on the zoomed region's action bar")

        // A second outside tap, from this resting state, fully backs out —
        // clearing the bar too.
        outside.press(forDuration: 0.05)
        let barGone = NSPredicate(format: "exists == false")
        expectation(for: barGone, evaluatedWith: app.buttons["bodymap.regionActionBar"])
        waitForExpectations(timeout: 5)
        attach(app, "09-after-second-outside-tap")
    }
}
