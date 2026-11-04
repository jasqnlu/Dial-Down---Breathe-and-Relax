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
        let tabs = ["Today", "Body", "Exercises", "Breathe", "Routines", "Profile"]
        for (index, name) in tabs.enumerated() {
            let app = XCUIApplication()
            app.launchArguments += ["-auth.isSignedIn", "YES", "-auth.provider", "guest",
                                    "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
                                    "-debugInitialTab", "\(index)"]
            app.launch()
            sleep(index == 0 ? 6 : 4) // first launch seeds exercises
            attach(app, "tab-\(index)-\(name)")
            if index != 1 { // Body tab is a 3D scene; swiping rotates it
                app.swipeUp()
                sleep(1)
                attach(app, "tab-\(index)-\(name)-scrolled")
            }
            app.terminate()
        }
    }

    private func launch(tab: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-auth.isSignedIn", "YES", "-auth.provider", "guest",
                                "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
                                "-debugInitialTab", "\(tab)"]
        app.launch()
        sleep(4)
        return app
    }

    func testDeeperScreens() throws {
        continueAfterFailure = true

        // Profile → Settings segment, and Progress & Charts
        var app = launch(tab: 5)
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
        app = launch(tab: 4)
        let premade = app.buttons["Premade Routines"].firstMatch
        if premade.waitForExistence(timeout: 5) { premade.tap(); sleep(2); attach(app, "z6-premade") }
        app.terminate()

        // Exercises → first search result list item via search
        app = launch(tab: 2)
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

    /// Exercise tiles in each place they appear: Today's For You row, a
    /// category group page, and search results.
    func testExerciseTiles() throws {
        continueAfterFailure = true
        var app = launch(tab: 0)
        for _ in 0..<4 { app.swipeUp() }
        sleep(1)
        attach(app, "t1-today-foryou")
        app.terminate()

        app = launch(tab: 2)
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
}
