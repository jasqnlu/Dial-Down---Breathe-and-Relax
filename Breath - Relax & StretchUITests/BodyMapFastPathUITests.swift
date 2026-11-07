import XCTest

/// Simulator verification for the zoomed "region resting state": reached by
/// tapping the body (which opens the muscle picker) and then tapping off the
/// picker to collapse it — landing on a dot + the "Stretches for…" action
/// bar, still zoomed in, rather than a full reset. Also covers a tap that
/// resolves nothing, a tap-off-body reset from full rest, and drag-still-
/// rotates.
final class BodyMapFastPathUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchBodyTab(extraArgs: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES",
                                "-hasSeenAppGuide", "YES",
                                "-auth.isSignedIn", "YES",
                                "-auth.provider", "guest"]
        app.launchArguments += extraArgs
        app.launchArguments += ["-exercisesMode", "body"]
        app.launch()
        // Cold/fresh-install launches run seed insertion + up to 5 sequential
        // SwiftData migration passes synchronously in `.onAppear` — wait that
        // out before assuming the tab bar exists, or later steps fail against
        // a still-launching app rather than testing what they mean to test.
        // Body lives behind the Exercises tab's Areas / Body switch. The
        // `-exercisesMode body` launch argument opens it on Body without a
        // tap — tapping the switch would save the choice into later tests.
        let bodyTab = app.buttons["Exercises"].firstMatch
        _ = bodyTab.waitForExistence(timeout: 30)
        bodyTab.tap()
        // Wait out the async OBJ parse ("Loading 3D model…" placeholder).
        sleep(6)
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// A tap opens the muscle picker; closing it (Cancel — functionally the
    /// same as tapping off it, see `BodyMapView.cancelDisambiguation`)
    /// collapses back to the zoomed region's action bar; tapping the bar
    /// reaches its stretch list.
    @MainActor
    func testTappingOffThePickerRaisesActionBarAndReachesStretches() throws {
        let app = launchBodyTab(extraArgs: [])
        attach(app, "01-body-at-rest")

        // Tap dead-centre chest — reliably on the torso silhouette (the
        // model renders smaller/lower in frame than a naive centre guess).
        let scene = app.otherElements.firstMatch
        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.42)).press(forDuration: 0.05)
        XCTAssertTrue(app.staticTexts["Which area did you mean?"].waitForExistence(timeout: 8),
                      "A tap on the body should open the muscle picker")
        attach(app, "02-picker-open")

        // Close the picker. Cancel rather than an off-body scene coordinate:
        // the candidate rail renders on whichever screen edge is emptier for
        // THIS region's candidates (left or right, `CandidateRailOverlay.layout`,
        // which side varies by region), so a fixed coordinate can land on a
        // label instead of empty space depending on what was tapped.
        app.buttons["Cancel"].tap()

        let bar = app.buttons["bodymap.regionActionBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5),
                      "Tapping off the picker should land on the zoomed region's action bar")
        attach(app, "03-bar-raised")

        let barLabel = bar.label
        XCTAssertTrue(barLabel.hasPrefix("Find stretches for "),
                      "Bar should name the region it will search; got '\(barLabel)'")

        bar.tap()
        // The pushed list is titled with the region name.
        let region = String(barLabel.dropFirst("Find stretches for ".count))
        XCTAssertTrue(app.navigationBars[region].waitForExistence(timeout: 5),
                      "Tapping the bar should push the stretch list for '\(region)'")
        attach(app, "04-stretch-list")
    }

    /// Drag must still rotate — tap-to-face shares the same surface and the
    /// single-tap recogniser must not swallow a pan.
    @MainActor
    func testDragStillRotatesTheBody() throws {
        let app = launchBodyTab(extraArgs: [])
        attach(app, "05-before-drag")
        let scene = app.otherElements.firstMatch
        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05,
                   thenDragTo: scene.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)))
        sleep(1)
        attach(app, "06-after-drag")
        // No picker, no bar: a drag is not a tap.
        XCTAssertFalse(app.staticTexts["Which area did you mean?"].exists,
                       "A drag should rotate without opening the muscle picker")
        XCTAssertFalse(app.buttons["bodymap.regionActionBar"].exists,
                       "A drag should rotate without selecting a region")
    }

    /// A tap outside the body resets the camera even fully at rest — no
    /// selection, no picker — as a quick "undo my pinch" gesture. There's no
    /// accessibility-visible signal for camera distance, so this pinches in
    /// first (a visibly bigger body) and screenshots before/after the
    /// outside tap for manual visual confirmation; the hard assertions guard
    /// against a crash or an accidental navigation.
    @MainActor
    func testTappingOffTheBodyAtRestResetsTheZoom() throws {
        let app = launchBodyTab(extraArgs: [])
        let scene = app.otherElements.firstMatch

        // Pinch in (scale > 1 zooms in) around the body's center.
        scene.pinch(withScale: 2.5, velocity: 2)
        sleep(1)
        attach(app, "07-pinched-in-at-rest")

        XCTAssertFalse(app.buttons["bodymap.regionActionBar"].exists,
                       "A pinch should zoom without selecting a region")

        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.5)).press(forDuration: 0.05)
        sleep(1)
        attach(app, "08-after-outside-tap-at-rest")

        XCTAssertTrue(app.staticTexts["3D body map"].exists,
                      "Should still be on Body Map — an outside tap at rest must not navigate")
        XCTAssertFalse(app.buttons["bodymap.regionActionBar"].exists,
                       "Still no selection — the outside tap must not have hit the body")
    }

    /// The figure faces the viewer, so a tap on the VIEWER'S LEFT must
    /// resolve to the figure's own RIGHT side, and vice versa. Taps the body
    /// (opening the picker), backs out to the region's action bar, and
    /// asserts on the bar's "Find stretches for <region>" label — the single
    /// source of truth for what the original tap resolved to.
    @MainActor
    func testViewerLeftTapMapsToFigureRight() throws {
        let app = launchBodyTab(extraArgs: [])
        let scene = app.otherElements.firstMatch
        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.40)).press(forDuration: 0.05)
        XCTAssertTrue(app.staticTexts["Which area did you mean?"].waitForExistence(timeout: 8))

        // Close the picker (Cancel — see the comment in
        // `testTappingOffThePickerRaisesActionBarAndReachesStretches` on why
        // this uses the button rather than a scene coordinate).
        app.buttons["Cancel"].tap()
        let bar = app.buttons["bodymap.regionActionBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        attach(app, "09-viewer-left-tap")
        XCTAssertTrue(bar.label.hasPrefix("Find stretches for Right "),
                      "A tap on the viewer's left should resolve to the figure's own right side; got '\(bar.label)'")
    }

    @MainActor
    func testViewerRightTapMapsToFigureLeft() throws {
        let app = launchBodyTab(extraArgs: [])
        let scene = app.otherElements.firstMatch
        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.58, dy: 0.62)).press(forDuration: 0.05)
        XCTAssertTrue(app.staticTexts["Which area did you mean?"].waitForExistence(timeout: 8))

        // Close the picker (Cancel — see the comment in
        // `testTappingOffThePickerRaisesActionBarAndReachesStretches` on why
        // this uses the button rather than a scene coordinate).
        app.buttons["Cancel"].tap()
        let bar = app.buttons["bodymap.regionActionBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        attach(app, "10-viewer-right-tap")
        XCTAssertTrue(bar.label.hasPrefix("Find stretches for Left "),
                      "A tap on the viewer's right should resolve to the figure's own left side; got '\(bar.label)'")
    }
}
