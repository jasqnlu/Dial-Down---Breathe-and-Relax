import XCTest

// Drives the flexibility check-in flow end-to-end for verification:
// Profile tab → Progress & Charts → empty Flexibility card → full check-in
// sheet (answer 3 tests, skip 1) → recorded levels back on the Progress card.
// Screenshots are attached at each stage (.keepAlways) for evidence export.
final class FlexibilityCheckInUITests: XCTestCase {

    @MainActor
    func testFlexibilityCheckInFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES",
            "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES",
            "-auth.provider", "guest",
        ]
        app.launch()

        attach(app, name: "01-launch")

        // → Profile tab → Progress & Charts
        let profileTab = app.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 10), "Profile tab should exist")
        profileTab.tap()

        let progressLink = app.buttons["Progress & Charts"].firstMatch.exists
            ? app.buttons["Progress & Charts"].firstMatch
            : app.staticTexts["Progress & Charts"].firstMatch
        XCTAssertTrue(progressLink.waitForExistence(timeout: 5), "Progress & Charts link should exist")
        progressLink.tap()

        // → scroll until the Flexibility card's CTA is on screen
        let startButton = app.buttons["Start First Check-In"]
        var swipes = 0
        while !startButton.isHittable && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        attach(app, name: "02-progress-empty-flexibility-card")
        XCTAssertTrue(startButton.waitForExistence(timeout: 5), "Empty-state CTA should exist on first run")
        startButton.tap()

        // → Toe Touch: pick level 2 (index) and continue
        let toeLevel = app.buttons["Fingertips reach my ankles"]
        XCTAssertTrue(toeLevel.waitForExistence(timeout: 5), "Check-in sheet should show toe touch levels")
        attach(app, name: "03-checkin-toe-touch")
        toeLevel.tap()
        app.buttons["Next"].tap()

        // → Shoulder Reach: skip it (probe: skipping must not record anything)
        XCTAssertTrue(app.buttons["Fingertips almost touch"].waitForExistence(timeout: 5))
        app.buttons["Skip"].tap()

        // → Neck Rotation
        let neckLevel = app.buttons["Chin turns about halfway"]
        XCTAssertTrue(neckLevel.waitForExistence(timeout: 5))
        neckLevel.tap()
        app.buttons["Next"].tap()

        // → Butterfly, then Finish
        let butterflyLevel = app.buttons["Knees nearly touch the floor"]
        XCTAssertTrue(butterflyLevel.waitForExistence(timeout: 5))
        butterflyLevel.tap()
        attach(app, name: "04-checkin-butterfly-selected")
        app.buttons["Finish"].tap()

        // → back on Progress: answered tests are listed with their level,
        //   the skipped one is absent
        let toeResult = app.staticTexts["Fingertips reach my ankles"]
        XCTAssertTrue(toeResult.waitForExistence(timeout: 5), "Recorded toe-touch level should show on the card")
        XCTAssertTrue(app.staticTexts["Toe Touch"].exists)
        XCTAssertTrue(app.staticTexts["Neck Rotation"].exists)
        XCTAssertTrue(app.staticTexts["Butterfly"].exists)
        XCTAssertFalse(app.staticTexts["Shoulder Reach"].exists, "Skipped test must not be recorded")
        attach(app, name: "05-progress-after-checkin")

        // 🔍 Probe: reopen and cancel — nothing new may be recorded
        let checkInButton = app.buttons["Check In"]
        XCTAssertTrue(checkInButton.waitForExistence(timeout: 5), "Header Check In button should exist once data exists")
        checkInButton.tap()
        let toeAgain = app.buttons["Fingertips touch the floor"]
        XCTAssertTrue(toeAgain.waitForExistence(timeout: 5))
        toeAgain.tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(toeResult.waitForExistence(timeout: 5), "Cancelling must leave the recorded level unchanged")
        attach(app, name: "06-progress-after-cancelled-checkin")

        // → second check-in (toe touch improves to the top level, rest
        //   skipped) so the ≥2-points paths render: delta badge + step chart
        checkInButton.tap()
        let toeTop = app.buttons["Palms rest flat on the floor"]
        XCTAssertTrue(toeTop.waitForExistence(timeout: 5))
        toeTop.tap()
        app.buttons["Next"].tap()
        for _ in 0..<3 {
            XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
            app.buttons["Skip"].tap()
        }

        let improvedLevel = app.staticTexts["Palms rest flat on the floor"]
        XCTAssertTrue(improvedLevel.waitForExistence(timeout: 5), "Second check-in should update the latest level")
        // The badge's container carries an .accessibilityLabel, which replaces
        // its child texts in the accessibility hierarchy — query that label.
        let deltaBadge = app.descendants(matching: .any)["Up 2 levels since first check-in"]
        XCTAssertTrue(deltaBadge.waitForExistence(timeout: 5), "Delta badge should show +2 levels (level 2 → 4)")
        attach(app, name: "07-progress-with-delta-and-chart")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
