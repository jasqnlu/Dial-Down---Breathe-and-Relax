import XCTest

/// Simulator verification for the head fan-out: tapping the head should
/// surface the four evidence-based face zones (Forehead + one side's
/// Eye, Temple, Jaw) as pins, with the side inferred from the tapped x.
/// Asserts the fan-out is functionally correct and attaches screenshots.
///
/// ANCHOR TUNING: the on-face dot positions come from HeadZones.leftAnchors /
/// foreheadAnchor (currently estimates). To fine-tune, run this test in Xcode
/// and open the "02-head-zones-fanned" attachment in the Test Report (the CLI
/// xcresulttool export returns nothing under Xcode 26, but the Xcode Test
/// navigator shows the screenshots). Nudge the anchors until each dot sits on
/// its feature.
final class HeadZoneVerificationUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchBodyTab() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES",
                                "-hasSeenAppGuide", "YES",
                                "-auth.isSignedIn", "YES",
                                "-auth.provider", "guest"]
        // Body lives behind the Exercises tab's Areas / Body switch; this opens
        // it on Body without tapping (a tap would save the choice for later tests).
        app.launchArguments += ["-exercisesMode", "body"]
        app.launch()
        app.buttons["Exercises"].firstMatch.tap()
        sleep(6) // async OBJ parse
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testHeadFansIntoFaceZones() throws {
        let app = launchBodyTab()
        let scene = app.otherElements.firstMatch
        attach(app, "00-body-initial")

        // Tap the head, slightly right-of-centre. (Offset retuned for the
        // skin-covered pivot's BodySkinMuscle model, which renders the body
        // smaller/lower in frame than the old BodyAnatomy model — a naive
        // dy: 0.16 lands above the head in empty space.)
        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.56, dy: 0.29)).press(forDuration: 0.05)
        attach(app, "01-head-tapped")

        let hint = app.staticTexts["Which area did you mean?"]
        XCTAssertTrue(hint.waitForExistence(timeout: 8),
                      "Tapping the head should fan into the face-zone disambiguation")
        sleep(1) // let the candidate-label fade-in animation settle before enumerating buttons —
                 // without this, allElementsBoundByIndex can race a still-animating button count.
        attach(app, "02-head-zones-fanned")

        let labels = app.buttons.allElementsBoundByIndex.map(\.label).filter { $0.contains("—") }
        let names = Set(labels.map {
            String($0.split(separator: "—")[0]).trimmingCharacters(in: .whitespaces)
        })
        print("HEADZONE-CANDIDATE-LABELS:", labels.sorted())

        XCTAssertEqual(names.count, 4, "Head should fan into exactly four zones, got \(names)")
        XCTAssertTrue(names.contains("Forehead"), "Forehead (midline) should always appear")
        let sides = names.subtracting(["Forehead"])
        XCTAssertTrue(sides == ["Left Eye", "Left Temple", "Left Jaw"] ||
                      sides == ["Right Eye", "Right Temple", "Right Jaw"],
                      "The three bilateral zones should all be one side: \(sides)")
    }
}
