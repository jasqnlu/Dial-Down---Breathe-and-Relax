import XCTest

/// Verifies the exercise animation loop appears in the search-list row and on the
/// exercise detail screen for "Clasped-Hands Behind-Back Stretch".
final class AnimationDemoUITest: XCTestCase {

    func testClaspedHandsAnimationInListAndDetail() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES",
            "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES",
            "-auth.provider", "guest",
        ]
        app.launch()

        // Exercises tab.
        let exercisesTab = app.descendants(matching: .any)["Exercises"].firstMatch
        XCTAssertTrue(exercisesTab.waitForExistence(timeout: 15), "Exercises tab not found")
        exercisesTab.tap()

        // Search surfaces the flat list of rows.
        let search = app.textFields["Search exercises"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "Search field not found")
        search.tap()
        search.typeText("Clasped")

        // The row's combined accessibility label begins with the exercise name.
        let rowPredicate = NSPredicate(format: "label BEGINSWITH %@",
                                       "Clasped-Hands Behind-Back Stretch")
        let row = app.descendants(matching: .any).matching(rowPredicate).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Clasped-Hands row not found")

        Thread.sleep(forTimeInterval: 1.5)   // let the loop begin
        attach(app, "01-list-row-with-animation")

        row.tap()
        Thread.sleep(forTimeInterval: 1.5)   // detail card loop
        attach(app, "02-detail-with-animation")
    }

    func testSecondBatchAnimationsInDetail() throws {
        for (query, tag) in [
            ("Neck Flexion", "01-neck-flexion"),
            ("Standing Forward Fold", "02-forward-fold"),
            ("Left Standing Side Bend", "03-side-bend"),
        ] {
            let app = XCUIApplication()
            app.launchArguments += [
                "-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES",
                "-hasSeenAppGuide", "YES",
                "-auth.isSignedIn", "YES",
                "-auth.provider", "guest",
            ]
            app.launch()

            let exercisesTab = app.descendants(matching: .any)["Exercises"].firstMatch
            XCTAssertTrue(exercisesTab.waitForExistence(timeout: 15), "Exercises tab not found")
            exercisesTab.tap()

            let search = app.textFields["Search exercises"]
            XCTAssertTrue(search.waitForExistence(timeout: 10), "Search field not found")
            search.tap()
            search.typeText(query)

            let rowPredicate = NSPredicate(format: "label BEGINSWITH %@", query)
            let row = app.descendants(matching: .any).matching(rowPredicate).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 8), "\(query) row not found")
            row.tap()
            Thread.sleep(forTimeInterval: 1.5)   // detail card loop
            attach(app, "\(tag)-detail")

            app.terminate()
        }
    }

    /// Verifies the 15 bicep/triceps exercises animated in the
    /// 2026-08-25 batch (139 -> 154 of 372 wired).
    func testFifteenthBatchAnimationsInDetail() throws {
        for (query, tag) in [
            ("Standing Doorway Bicep Stretch (Left)", "01-doorway-bicep-left"),
            ("Standing Doorway Bicep Stretch (Right)", "02-doorway-bicep-right"),
            ("Behind-Back Prayer Bicep Stretch", "03-prayer-bicep"),
            ("Wall-Assisted Bicep Stretch (Left)", "04-wall-bicep-left"),
            ("Wall-Assisted Bicep Stretch (Right)", "05-wall-bicep-right"),
            ("Overhead Bicep Reach with Strap (Left)", "06-overhead-bicep-left"),
            ("Overhead Bicep Reach with Strap (Right)", "07-overhead-bicep-right"),
            ("Seated Bicep Stretch on Chair Edge", "08-seated-bicep"),
            ("Overhead Triceps Stretch with Strap (Left)", "09-overhead-triceps-left"),
            ("Overhead Triceps Stretch with Strap (Right)", "10-overhead-triceps-right"),
            ("Cross-Body Triceps Pull at Wall (Left)", "11-cross-body-triceps-left"),
            ("Cross-Body Triceps Pull at Wall (Right)", "12-cross-body-triceps-right"),
            ("Behind-Head Bilateral Triceps Stretch", "13-behind-head-triceps"),
            ("Seated Triceps Stretch with Towel (Left)", "14-seated-triceps-left"),
            ("Seated Triceps Stretch with Towel (Right)", "15-seated-triceps-right"),
        ] {
            let app = XCUIApplication()
            app.launchArguments += [
                "-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES",
                "-hasSeenAppGuide", "YES",
                "-auth.isSignedIn", "YES",
                "-auth.provider", "guest",
            ]
            app.launch()

            let exercisesTab = app.descendants(matching: .any)["Exercises"].firstMatch
            XCTAssertTrue(exercisesTab.waitForExistence(timeout: 15), "Exercises tab not found")
            exercisesTab.tap()

            let search = app.textFields["Search exercises"]
            XCTAssertTrue(search.waitForExistence(timeout: 10), "Search field not found")
            search.tap()
            search.typeText(query)

            let rowPredicate = NSPredicate(format: "label BEGINSWITH %@", query)
            let row = app.descendants(matching: .any).matching(rowPredicate).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 8), "\(query) row not found")
            row.tap()
            Thread.sleep(forTimeInterval: 1.5)   // detail card loop
            attach(app, "\(tag)-detail")

            app.terminate()
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
