import XCTest

/// Screenshot pass for the "modern professional" restyle on the
/// seperate-main branch. Not behavior assertions — it opens each tab and
/// attaches a screenshot (plus one scrolled-down shot) for visual review.
final class ModernRestyleScreenshotTests: XCTestCase {

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testAllTabs() throws {
        continueAfterFailure = true
        let tabs = ["Today", "Exercises", "Breathe", "Routines", "Profile"]
        for (index, name) in tabs.enumerated() {
            let app = XCUIApplication()
            app.launchArguments += ["-auth.isSignedIn", "YES", "-auth.provider", "guest",
                                    "-carousel.paused", "YES", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
                                    "-debugInitialTab", "\(index)"]
            app.launch()
            sleep(index == 0 ? 6 : 4) // first launch seeds exercises
            attach(app, "tab-\(index)-\(name)")
            do {
                app.swipeUp()
                sleep(1)
                attach(app, "tab-\(index)-\(name)-scrolled")
            }
            app.terminate()
        }
    }

    /// Redesigned Routines tab: empty state, two premade routines saved
    /// from the strip, one pinned, then "See all".
    func testRoutinesTabRedesign() throws {
        continueAfterFailure = true
        let app = launch(tab: 3)
        sleep(4)
        attach(app, "r1-routines-empty")

        for title in ["Office Stretch", "Athletic Recovery"] {
            let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", title)).firstMatch
            if tile.waitForExistence(timeout: 5) {
                tile.tap()
                let save = app.buttons["Save Routine"].firstMatch
                if save.waitForExistence(timeout: 5) { save.tap() }
                sleep(2)
            }
        }
        attach(app, "r2-routines-saved")

        let first = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] 'Office Stretch'")).firstMatch
        if first.waitForExistence(timeout: 5) {
            first.swipeRight(); sleep(1)
            attach(app, "r3-routines-swipe")
            let pin = app.buttons["Pin to Today"].firstMatch
            if pin.exists { pin.tap(); sleep(1) }
        }
        attach(app, "r4-routines-pinned")

        let seeAll = app.buttons["Premade Routines"].firstMatch
        if seeAll.waitForExistence(timeout: 5) { seeAll.tap(); sleep(2); attach(app, "r5-premade-see-all") }
    }

    /// Five-tab bar + the Exercises tab's Areas / Body switch. Ends back on
    /// Areas because the choice is saved and later tests expect Areas.
    func testExercisesAreasBodySwitch() throws {
        continueAfterFailure = true
        let app = launch(tab: 0)
        attach(app, "t1-five-tab-bar")
        app.buttons["Exercises"].firstMatch.tap(); sleep(2)
        attach(app, "t2-exercises-areas")
        let body = app.buttons["exercisesMode.body"].firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap(); sleep(6) // 3D model loads on first show
        attach(app, "t3-exercises-body")
        app.buttons["Breathe"].firstMatch.tap(); sleep(1)
        app.buttons["Exercises"].firstMatch.tap(); sleep(1)
        attach(app, "t4-exercises-body-kept")
        app.buttons["exercisesMode.areas"].firstMatch.tap(); sleep(1)
        attach(app, "t5-exercises-back-to-areas")
    }

    private func launch(tab: Int, extraArgs: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-auth.isSignedIn", "YES", "-auth.provider", "guest",
                                "-carousel.paused", "YES", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
                                "-debugInitialTab", "\(tab)"] + extraArgs
        app.launch()
        sleep(4)
        return app
    }

    func testDeeperScreens() throws {
        continueAfterFailure = true

        // Profile → Settings segment, and Progress & Charts
        var app = launch(tab: 4)
        app.buttons["Settings"].firstMatch.tap(); sleep(1)
        attach(app, "z1-profile-settings")
        app.swipeUp(); sleep(1)
        attach(app, "z2-profile-settings-scrolled")
        app.swipeDown(); app.swipeDown(); sleep(1)
        app.buttons["Account"].firstMatch.tap(); sleep(1)
        let progress = app.buttons["Progress & Charts"].firstMatch
        if !progress.isHittable { app.swipeUp(); sleep(1) }
        if progress.waitForExistence(timeout: 3) { progress.tap(); sleep(2); attach(app, "z3-progress") }
        app.terminate()

        // Today → recommended card → exercise detail; then session player
        app = launch(tab: 0)
        let rec = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Stretch' OR label CONTAINS[c] ':'")).element(boundBy: 0)
        let begin = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Begin today'")).firstMatch
        if begin.waitForExistence(timeout: 10) {
            begin.tap(); sleep(2)
            attach(app, "z4-session-getready")
            let skip = app.buttons["Skip"].firstMatch
            if skip.waitForExistence(timeout: 3) { skip.tap() }
            sleep(2)
            attach(app, "z5-session-player")
        }
        app.terminate()
        _ = rec

        // Routines → Premade Routines
        app = launch(tab: 3)
        let premade = app.buttons["Premade Routines"].firstMatch
        if premade.waitForExistence(timeout: 5) { premade.tap(); sleep(2); attach(app, "z6-premade") }
        app.terminate()

        // Exercises → first search result list item via search
        app = launch(tab: 1)
        let field = app.textFields["Search exercises"].firstMatch
        if field.waitForExistence(timeout: 5) {
            field.tap(); field.typeText("neck"); sleep(2)
            attach(app, "z7-exercise-search")
            let cell = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'neck'")).element(boundBy: 0)
            if cell.waitForExistence(timeout: 3) { cell.tap(); sleep(2); attach(app, "z8-exercise-detail") }
        }
        app.terminate()
    }

    func testCustomizeScreen() throws {
        continueAfterFailure = true
        let app = launch(tab: 0)
        let customize = app.buttons["Customize"].firstMatch
        XCTAssertTrue(customize.waitForExistence(timeout: 10))
        customize.tap(); sleep(2)
        attach(app, "c1-customize")
        app.swipeUp(); sleep(1)
        attach(app, "c2-customize-scrolled")
        app.swipeUp(); sleep(1)
        attach(app, "c3-customize-bottom")
    }

    /// Premade routines on Today (scrolled down to the row) and on the
    /// Routines → Premade Routines screen.
    func testPremadeRoutines() throws {
        continueAfterFailure = true
        var app = launch(tab: 0)
        app.swipeUp(); app.swipeUp()
        sleep(1)
        attach(app, "p1-today-premade")
        app.terminate()

        app = launch(tab: 3)
        let premade = app.buttons["Premade Routines"].firstMatch
        if premade.waitForExistence(timeout: 5) {
            premade.tap(); sleep(2)
            attach(app, "p2-premade-screen")
            app.swipeUp(); sleep(1)
            attach(app, "p3-premade-screen-scrolled")
        }
        app.terminate()
    }

    /// What opens from a premade routine, and the mini-routine flow
    /// (Exercises → Select → pick → Continue → Review Picks → Start Mini-Routine).
    func testPremadeAndMiniRoutineScreens() throws {
        continueAfterFailure = true
        var app = launch(tab: 3)
        let premade = app.buttons["Premade Routines"].firstMatch
        if premade.waitForExistence(timeout: 5) {
            premade.tap(); sleep(2)
            let office = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Office Stretch'")).firstMatch
            if office.waitForExistence(timeout: 5) {
                office.tap(); sleep(2)
                attach(app, "m1-premade-opened")
                app.swipeUp(); sleep(1)
                attach(app, "m2-premade-opened-scrolled")
            }
        }
        app.terminate()

        app = launch(tab: 1)
        let field = app.textFields["Search exercises"].firstMatch
        if field.waitForExistence(timeout: 10) {
            field.tap(); field.typeText("Neck Stretch")
            app.buttons["exerciseSelectToggle"].tap()
            let tiles = app.descendants(matching: .any).matching(identifier: "exerciseGridTile")
            if tiles.firstMatch.waitForExistence(timeout: 10) {
                for i in 0..<min(3, tiles.count) { tiles.element(boundBy: i).tap() }
                app.buttons["Continue"].tap(); sleep(2)
                attach(app, "m3-review-picks")
                let mini = app.buttons["Start Mini-Routine"]
                if mini.waitForExistence(timeout: 5) {
                    mini.tap(); sleep(2)
                    attach(app, "m4-mini-customize")
                }
            }
        }
        app.terminate()
    }

    /// Body Map: idle, the "Which area did you mean?" muscle picker, and
    /// the region's stretch list it drills into.
    func testBodyMapPicker() throws {
        continueAfterFailure = true
        let app = launch(tab: 1, extraArgs: ["-exercisesMode", "body"])
        sleep(6) // async OBJ parse
        attach(app, "bm1-idle")
        let scene = app.otherElements.firstMatch
        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.42)).tap()
        if app.staticTexts["Which area did you mean?"].waitForExistence(timeout: 8) {
            sleep(1)
            attach(app, "bm2-picker")
            // Focus another candidate to see the unfocused → focused swap.
            let other = app.buttons.matching(NSPredicate(format: "label ENDSWITH '— highlight region'")).firstMatch
            if other.exists { other.tap(); sleep(1); attach(app, "bm2b-picker-refocused") }
            let focused = app.buttons.matching(NSPredicate(format: "label ENDSWITH '— view exercises'")).firstMatch
            if focused.waitForExistence(timeout: 5) {
                focused.tap(); sleep(2)
                attach(app, "bm3-region-list")
                app.navigationBars.buttons.element(boundBy: 0).tap(); sleep(2)
                app.buttons["Cancel"].firstMatch.tap(); sleep(1)
                attach(app, "bm4-region-action-bar")
            }
        }
    }

    /// Breathe tab idle, mid-session, and the completion screen.
    func testBreathingScreen() throws {
        continueAfterFailure = true
        let app = launch(tab: 2)
        sleep(4) // first launch seeds the library behind the splash
        attach(app, "b1-breathe-idle")
        // Energising is 6s in / 2s out — the shortest pattern.
        let energising = app.buttons["Energising"].firstMatch
        if energising.waitForExistence(timeout: 5) { energising.tap(); sleep(1) }
        attach(app, "b3-breathe-energising")
        let start = app.buttons["Start"].firstMatch
        if start.waitForExistence(timeout: 5) {
            start.tap(); sleep(3)
            attach(app, "b4-breathe-inhale")
            sleep(4)
            attach(app, "b5-breathe-exhale")
            let pause = app.buttons["Pause"].firstMatch
            if pause.exists { pause.tap(); sleep(1); attach(app, "b6-breathe-paused") }
        }
    }

    /// Exercise tiles in each place they appear: Today's For You row, a
    /// category group page, and search results.
    func testExerciseTiles() throws {
        continueAfterFailure = true
        var app = launch(tab: 0)
        for _ in 0..<4 { app.swipeUp() }
        sleep(1)
        attach(app, "t1-today-foryou")
        app.terminate()

        app = launch(tab: 1)
        let chest = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Chest,'")).firstMatch
        if chest.waitForExistence(timeout: 10) {
            chest.tap(); sleep(1)
            let general = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH 'General Chest'")).firstMatch
            if general.waitForExistence(timeout: 5) {
                let f = general.frame
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
                sleep(2)
                attach(app, "t2-group-page")
            }
        }
        app.terminate()
    }

    // MARK: - Remaining screens sweep

    private func launchRaw(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += args
        app.launch()
        sleep(6)
        return app
    }

    private func tapIfExists(_ e: XCUIElement, timeout: TimeInterval = 4) -> Bool {
        guard e.waitForExistence(timeout: timeout) else { return false }
        e.tap(); return true
    }

    /// Signed-out, app lock, and onboarding.
    func testEntryScreens() throws {
        continueAfterFailure = true
        var app = launchRaw(["-carousel.paused", "YES", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
                             "-auth.isSignedIn", "NO"])
        attach(app, "r01-auth")
        let email = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'email'")).firstMatch
        if tapIfExists(email) { sleep(2); attach(app, "r02-email-auth") }
        app.terminate()

        app = launchRaw(["-carousel.paused", "YES", "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
                         "-auth.isSignedIn", "YES", "-auth.provider", "guest",
                         "-auth.appLockEnabled", "YES"])
        attach(app, "r03-app-lock")
        app.terminate()

        app = launchRaw(["-carousel.paused", "YES", "-hasCompletedOnboarding", "NO", "-auth.isSignedIn", "NO"])
        for i in 0..<7 {
            attach(app, "r1\(i)-onboarding")
            let next = app.buttons["Next"].firstMatch
            guard next.waitForExistence(timeout: 3) else { break }
            next.tap(); sleep(2)
        }
        app.terminate()
    }

    /// Session player, exercise detail, routines, and profile sub-screens.
    func testInnerScreens() throws {
        continueAfterFailure = true
        var app = launch(tab: 0)
        sleep(2)
        let begin = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Begin today'")).firstMatch
        if tapIfExists(begin, timeout: 10) {
            sleep(1); attach(app, "s1-get-ready")
            sleep(5); attach(app, "s2-player")
            let pause = app.buttons["Pause session"].firstMatch
            if tapIfExists(pause) { sleep(1); attach(app, "s3-player-paused") }
        }
        app.terminate()

        app = launch(tab: 1)
        let field = app.textFields["Search exercises"].firstMatch
        if field.waitForExistence(timeout: 8) {
            field.tap(); field.typeText("Cat-Cow")
            let tile = app.descendants(matching: .any).matching(identifier: "exerciseGridTile").firstMatch
            if tapIfExists(tile, timeout: 6) {
                sleep(2); attach(app, "s4-exercise-detail")
                app.swipeUp(); sleep(1); attach(app, "s5-exercise-detail-scrolled")
            }
        }
        app.terminate()

        app = launch(tab: 3)
        attach(app, "s6-routines")
        let plus = app.navigationBars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'add' OR label CONTAINS[c] 'new' OR label CONTAINS[c] 'create'")).firstMatch
        if tapIfExists(plus) { sleep(2); attach(app, "s7-routine-create") }
        app.terminate()

        app = launch(tab: 4)
        for (name, label) in [("s8-progress", "Progress & Charts"), ("s9-badges", "View All Badges"),
                              ("sA-leaderboard", "Leaderboard")] {
            let link = app.buttons[label].firstMatch
            if !link.isHittable { app.swipeUp(); sleep(1) }
            if tapIfExists(link) {
                sleep(2); attach(app, name)
                app.swipeUp(); sleep(1); attach(app, name + "-scrolled")
                app.navigationBars.buttons.element(boundBy: 0).tap(); sleep(1)
            }
        }
        app.terminate()
    }
}
