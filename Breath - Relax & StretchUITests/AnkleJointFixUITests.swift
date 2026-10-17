import XCTest

/// Verifies the 2026-10-17 ankle-joint fix (26 foot/ankle exercises re-rendered
/// on the new `foot.{L,R}` bone, see Tools/blender/exercises/ANIMATION_HANDOFF.md
/// "Ankle joint"): a sample opens, plays its clip, and no longer shows either
/// the "may not be 100% accurate" note or the old instruction callout.
final class AnkleJointFixUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "YES",
            "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES",
            "-auth.provider", "guest",
        ]
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The simulator sometimes shows a system "Apple Account Verification"
    /// alert over the app, which swallows every tap. Dismiss it if present.
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notNow = springboard.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 4) { notNow.tap() }
    }

    private func openExercisesTab(_ app: XCUIApplication) {
        dismissSystemAlerts()
        let tab = app.descendants(matching: .any)["Exercises"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "Exercises tab not found")
        tab.tap()
    }

    private func search(_ app: XCUIApplication) -> XCUIElement {
        let field = app.textFields["Search exercises"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Search field not found")
        return field
    }

    private func searchFor(_ app: XCUIApplication, _ field: XCUIElement, _ name: String) {
        field.tap()
        if !(field.value as? String ?? "").isEmpty {
            let clear = app.buttons["Clear search"]
            if clear.exists { clear.tap() }
        }
        field.typeText(String(name.prefix(20)))
    }

    @discardableResult
    private func navigateBack(_ app: XCUIApplication) -> Bool {
        for _ in 0..<3 {
            let navBack = app.navigationBars.buttons.element(boundBy: 0)
            if navBack.waitForExistence(timeout: 3), navBack.isHittable {
                navBack.tap()
                return true
            }
            usleep(400_000)
        }
        return false
    }

    private let fixed: [(name: String, oldCallout: String)] = [
        ("Ankle Alphabet", "Trace letters with your toes"),
        ("Seated Foot Flex-and-Point Flow", "Flex your feet back, then point your toes away"),
        ("Left Step-Edge Calf Drop Stretch", "Let your heel drop below the step"),
    ]

    func testFixedAnkleExercisesDropTheInaccuracyMessaging() throws {
        let app = launchApp()
        openExercisesTab(app)
        let field = search(app)

        for (index, item) in fixed.enumerated() {
            searchFor(app, field, item.name)
            let row = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", item.name))
                .firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 8), "Row not found for \(item.name)")
            row.tap()

            let heading = app.descendants(matching: .any)[item.name].firstMatch
            XCTAssertTrue(heading.waitForExistence(timeout: 8), "Detail screen did not open for \(item.name)")

            usleep(700_000)
            attach(app, "\(index)-\(item.name)-frameA")
            usleep(1_300_000)
            attach(app, "\(index)-\(item.name)-frameB")

            let note = app.descendants(matching: .any)["Note: this animation may not be 100% accurate to the exercise."].firstMatch
            XCTAssertFalse(note.exists, "Accuracy note still shown on \(item.name)")
            let callout = app.descendants(matching: .any)[item.oldCallout].firstMatch
            XCTAssertFalse(callout.exists, "Old callout still shown on \(item.name)")

            navigateBack(app)
        }
    }
}
