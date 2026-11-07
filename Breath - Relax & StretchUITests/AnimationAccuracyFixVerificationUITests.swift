import XCTest

/// Verifies the 3 animations fixed in the 2026-09-05 accuracy re-audit
/// (see Tools/blender/exercises/ANIMATION_HANDOFF.md) actually show visible
/// motion live in the app, not just that the demo video resolves. Opens each
/// exercise's detail screen and takes two screenshots a beat apart so the
/// looping video is caught at two different points in its cycle.
final class AnimationAccuracyFixVerificationUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-appLanguage", "en", "-hasCompletedOnboarding", "YES",
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

    private func openExercisesTab(_ app: XCUIApplication) {
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

    private let fixedNames = [
        "Shoulder Pendulum Swing (Left)",
        "Shoulder Pendulum Swing (Right)",
        "Standing Lumbar Side Glide (Lateral Shift)",
    ]

    func testFixedAnimationsShowMotionAtTwoPointsInTheLoop() throws {
        let app = launchApp()
        openExercisesTab(app)
        let field = search(app)

        for (index, name) in fixedNames.enumerated() {
            searchFor(app, field, name)
            let row = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", name))
                .firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 8), "Row not found for \(name)")
            row.tap()

            let heading = app.descendants(matching: .any)[name].firstMatch
            XCTAssertTrue(heading.waitForExistence(timeout: 8), "Detail screen did not open for \(name)")

            // First frame as soon as the video has had a moment to start.
            usleep(700_000)
            attach(app, "\(index)-\(name)-frameA")
            // A beat later — the loop is 4s, so ~1.3s later lands at a
            // clearly different point in the cycle.
            usleep(1_300_000)
            attach(app, "\(index)-\(name)-frameB")

            navigateBack(app)
        }
    }
}
