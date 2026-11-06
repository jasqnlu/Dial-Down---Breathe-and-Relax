import XCTest

/// Reproduces the exact user-reported path: BodyMap → double-tap → drill
/// into a region's stretch list → enter Select mode → add an exercise to
/// the picks → Continue → "Start Mini-Routine" opens the shared Customize
/// screen → "Start" → land in SessionPlayerView. Checks that the back/skip
/// buttons are not just present in the accessibility tree but actually
/// *hittable* — `.exists` alone doesn't prove visibility, which is exactly
/// how a real bug here slipped past manual testing: some exercises (ones
/// with an extra AnimationAccuracyNote caveat line) pushed the whole button
/// row off the bottom of the screen in the old non-scrolling layout, still
/// "existing" but neither visible nor tappable.
final class BodyMapMiniRoutineStartUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testStartFromBodyMapMiniRoutineBarShowsSkipAndBackButtons() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES", "-auth.provider", "guest",
        ]
        app.launchArguments += ["-exercisesMode", "body"]
        app.launch()

        // Body lives behind the Exercises tab's Areas / Body switch. The
        // `-exercisesMode body` launch argument opens it on Body without a
        // tap — tapping the switch would save the choice into later tests.
        let bodyTab = app.buttons["Exercises"].firstMatch
        XCTAssertTrue(bodyTab.waitForExistence(timeout: 30))
        bodyTab.tap()
        sleep(6) // async OBJ parse — mirrors BodyMapMusclePickerUITests

        let scene = app.otherElements.firstMatch
        // A single tap opens the picker now (gestures swapped — see BodyMapView).
        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.42)).tap()
        XCTAssertTrue(app.staticTexts["Which area did you mean?"].waitForExistence(timeout: 8))
        attach(app, "01-muscle-picker")

        // The auto-focused candidate (picker opens with the first pin
        // already focused) drills straight into that region's stretch list.
        let focusedCandidate = app.buttons.matching(
            NSPredicate(format: "label ENDSWITH '— view exercises'")
        ).firstMatch
        XCTAssertTrue(focusedCandidate.waitForExistence(timeout: 5))
        let regionName = String(focusedCandidate.label.dropLast(" — view exercises".count))
        focusedCandidate.tap()

        XCTAssertTrue(app.navigationBars[regionName].waitForExistence(timeout: 5))
        attach(app, "02-region-stretch-list")

        // Same Select/Cancel toggle as the Exercises tab's own select mode —
        // badges only appear once picking is active.
        let selectToggle = app.buttons["bodyMapSelectToggle"]
        XCTAssertTrue(selectToggle.waitForExistence(timeout: 5))
        selectToggle.tap()

        // Add the first exercise tile to the picks via its badge
        // (bottom-trailing corner of the tile — the badge collapses into
        // the tile's single combined accessibility element, so a plain
        // element query can't address it separately; a coordinate tap on
        // its known corner position is the reliable way to hit it).
        let firstTile = app.descendants(matching: .any).matching(identifier: "exerciseGridTile").firstMatch
        XCTAssertTrue(firstTile.waitForExistence(timeout: 10))
        firstTile.coordinate(withNormalizedOffset: CGVector(dx: 0.83, dy: 0.49)).tap() // the + badge on the restyled ExerciseTileCard

        // "Continue" opens the shared review screen with the three
        // destinations (Create New Routine / Add to Existing Routine /
        // Start Mini-Routine) instead of jumping straight into Customize.
        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5), "Picking bar with Continue should appear once an exercise is picked")
        attach(app, "03-picking-bar-appeared")
        continueButton.tap()

        let startMiniRoutineRow = app.buttons["Start Mini-Routine"]
        XCTAssertTrue(startMiniRoutineRow.waitForExistence(timeout: 5), "Review screen should offer Start Mini-Routine")
        attach(app, "04-review-destinations")
        startMiniRoutineRow.tap()

        let startButton = app.buttons["Start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10), "Start Mini-Routine should open the shared Customize screen with a Start action")
        attach(app, "05-customize-screen")
        startButton.tap()

        // The actual reported symptom: does this entry point's session
        // screen show the back/skip buttons, actually visible and
        // tappable (not merely present off-screen in the hierarchy)?
        let pauseButton = app.buttons["Pause session"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 10), "Should land in the session player")
        attach(app, "06-session-player-from-bodymap")

        let backButton = app.buttons["Previous exercise"]
        let skipButton = app.buttons["Skip exercise"]
        XCTAssertTrue(backButton.exists && backButton.isHittable, "Back button should be visible and tappable, not just present in the hierarchy")
        XCTAssertTrue(skipButton.exists && skipButton.isHittable, "Skip button should be visible and tappable, not just present in the hierarchy")
    }
}
