import XCTest

/// Screenshot pass for the Tier-1 Lumina restyle (session player, auth,
/// onboarding, paywall). Not assertions of behavior — each test navigates to
/// a restyled screen and attaches a screenshot for visual review.
final class LuminaRestyleScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testAuthScreensDark() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-carousel.paused", "YES", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Email"].waitForExistence(timeout: 10))
        attach(app, "auth-dark")

        app.buttons["Email"].tap()
        XCTAssertTrue(app.buttons["Create Account"].waitForExistence(timeout: 5))
        attach(app, "email-auth-dark")
        app.buttons["Cancel"].tap()
    }

    func testOnboardingScreensDark() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-auth.isSignedIn", "YES", "-auth.provider", "guest",
                                "-carousel.paused", "YES", "-hasCompletedOnboarding", "NO", "-hasSeenAppGuide", "YES"]
        app.launch()
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        attach(app, "onboarding-1-welcome-dark")

        for name in ["2-goals", "3-focus-areas", "4-bodymap"] {
            next.tap()
            sleep(1)
            attach(app, "onboarding-\(name)-dark")
        }
        next.tap()
        sleep(1)
        attach(app, "onboarding-5-notifications-dark")
    }

    func testSessionPlayerDark() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-auth.isSignedIn", "YES", "-auth.provider", "guest",
                                "-carousel.paused", "YES", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES"]
        app.launch()

        // Today is the frontmost tab at launch; its hero CTA starts a session.
        let begin = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Begin today'")
        ).firstMatch
        XCTAssertTrue(begin.waitForExistence(timeout: 15)) // allows first-launch seeding
        begin.tap()
        sleep(1)
        attach(app, "session-getready-dark")

        let skip = app.buttons["Skip"].firstMatch
        if skip.waitForExistence(timeout: 3) { skip.tap() }
        sleep(1)
        attach(app, "session-player-dark")
    }

    // Investigation (task D): focus the Chest category, tap the General Chest
    // group satellite, and capture whether its corpus sheet appears. Uses
    // `return` rather than XCTAssert so every diagnostic screenshot is kept.
    func testGeneralChestGroupTapRepro() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["-auth.isSignedIn", "YES", "-auth.provider", "guest",
                                "-carousel.paused", "YES", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
                                "-debugInitialTab", "1"]
        app.launch()
        sleep(3)
        attach(app, "repro-graph-initial")

        let chest = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Chest,'")).firstMatch
        guard chest.waitForExistence(timeout: 15) else {
            NSLog("REPRO-D: chest category node NOT found")
            attach(app, "repro-no-chest")
            return
        }
        chest.tap()
        sleep(1)
        attach(app, "repro-chest-focused")

        let general = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'General Chest'")).firstMatch
        let exists = general.waitForExistence(timeout: 5)
        NSLog("REPRO-D: generalExists=\(exists) hittable=\(exists ? general.isHittable : false)")
        attach(app, exists ? "repro-general-visible" : "repro-general-missing")
        guard exists else { return }

        // Tap the node's visible centre; the corpus sheet's unique "Done"
        // button is the only trustworthy "opened" signal (the graph has none).
        let done = app.buttons["Done"]
        for attempt in 1...2 {
            let f = general.frame
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: f.midX, dy: f.midY))
                .tap()
            let opened = done.waitForExistence(timeout: 5)
            if attempt == 1 { attach(app, opened ? "repro-sheet-open" : "repro-sheet-closed") }
            XCTAssertTrue(opened, "General Chest sheet did not open on attempt \(attempt)")
            if opened { done.tap(); sleep(1) }
        }
    }

    // Task A: the new focus-area onboarding step (Welcome→Goals→Focus).
    func testFocusAreaOnboardingScreenshot() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["-auth.isSignedIn", "YES", "-auth.provider", "guest",
                                "-carousel.paused", "YES", "-hasCompletedOnboarding", "NO", "-hasSeenAppGuide", "YES"]
        app.launch()
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        for _ in 0..<2 { next.tap(); sleep(1) }   // Welcome→Goals→Focus areas
        attach(app, "A-focus-area-onboarding")
        // Select a couple of areas for good measure.
        for label in ["Chest", "Legs"] where app.buttons[label].exists {
            app.buttons[label].tap()
        }
        attach(app, "A-focus-area-selected")
    }

    // Verify the Breathe tab's canvas background matches the other tabs
    // (Lumina surface color) instead of the system default.
    func testBreatheTabBackgroundScreenshot() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["-auth.isSignedIn", "YES", "-auth.provider", "guest",
                                "-carousel.paused", "YES", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
                                "-debugInitialTab", "2"]
        app.launch()
        sleep(2)
        attach(app, "Breathe-tab-background")
    }

    // Repro for a reported bug: the search-results pagination spinner in the
    // Exercises tab either never resolves or spins without loading more rows.
    func testExerciseSearchPaginationRepro() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["-auth.isSignedIn", "YES", "-auth.provider", "guest",
                                "-carousel.paused", "YES", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
                                "-debugInitialTab", "1"]
        app.launch()
        sleep(2)
        let searchField = app.textFields["Search exercises"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText("stretch")
        sleep(1)
        attach(app, "search-page-1")

        let scrollView = app.scrollViews.firstMatch
        for i in 0..<8 {
            scrollView.swipeUp()
            sleep(1)
            attach(app, "search-scroll-\(i)")
        }
    }

    func testTodayTabBackgroundScreenshot() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["-auth.isSignedIn", "YES", "-auth.provider", "guest",
                                "-carousel.paused", "YES", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
                                "-debugInitialTab", "0"]
        app.launch()
        sleep(2)
        attach(app, "Today-tab-background")
    }

    // Task A: the Home "Recommended for You" rotating carousel, personalised
    // from a pre-seeded focus-area selection.
    func testRecommendedCarouselScreenshot() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["-auth.isSignedIn", "YES", "-auth.provider", "guest",
                                "-carousel.paused", "YES", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
                                "-onboardingAreas", "Chest,Legs,Core", "-debugInitialTab", "0"]
        app.launch()
        sleep(4)   // allow first-launch seeding
        attach(app, "A-home-carousel")
    }
}
