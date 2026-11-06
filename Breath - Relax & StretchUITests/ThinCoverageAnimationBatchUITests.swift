import XCTest

/// Verifies the 20 exercises newly animated in the "thin coverage" batch
/// (biceps/forearm, lats, hand, foot, calves, neck, temple/head families)
/// actually resolve a demo video in the running app — not just that
/// `animationName` is set in SeedData.json, but that the bundled mp4 loads
/// and `ExerciseMediaCard` renders it instead of falling back to the
/// placeholder. Same technique as `HandWristAnimationVerificationUITests`.
final class ThinCoverageAnimationBatchUITests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-carousel.paused", "YES", "-hasCompletedOnboarding", "YES",
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

    /// Flagged `animationIsApproximate: true` — the disclaimer note is proof
    /// the animation actually loaded (see AnimationAccuracyNote in
    /// SafetyComponents.swift; it only renders once `demoVideoURL` resolves).
    private let approximateNames = [
        "Thumb Extension Stretch (Left)",
        "Thumb Extension Stretch (Right)",
        "Fist-to-Fan Tendon Gliding Flow",
        "Left Toe Spread & Stretch",
        "Right Toe Spread & Stretch",
        "Towel Scrunch (Toe Flexor Stretch)",
        "Big Toe Extension Stretch (Left)",
        "Big Toe Extension Stretch (Right)",
        "Seated Toe-to-Shin Stretch (Left)",
        "Seated Toe-to-Shin Stretch (Right)",
        "Left Seated Calf Stretch with Towel",
        "Right Seated Calf Stretch with Towel",
        "Neck Isometric Front-and-Back Press",
        "Circular Temple Self-Massage",
        "Full Scalp Massage (Tension Release)",
    ]

    /// Not flagged approximate — real motion, no rig-limitation disclaimer
    /// expected. Only checked for the detail screen opening (the media card
    /// renders a `LoopingVideoPlayer`, which has no distinct accessibility
    /// marker of its own beyond "not the placeholder").
    private let exactNames = [
        "Table-Edge Bicep Stretch (Left)",
        "Table-Edge Bicep Stretch (Right)",
        "Left Kneeling Lat Stretch (Hands on Chair)",
        "Right Kneeling Lat Stretch (Hands on Chair)",
        "Seated Neck Half-Circles (Ear-to-Shoulder Arc)",
    ]

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

    func testAll20AnimatedExercisesOpenAndTheApproximateOnesShowTheNote() throws {
        let app = launchApp()
        openExercisesTab(app)
        let field = search(app)

        var missingRow: [String] = []
        var missingHeading: [String] = []
        var missingNote: [String] = []

        let allNames = approximateNames + exactNames
        for (index, name) in allNames.enumerated() {
            searchFor(app, field, name)
            let row = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", name))
                .firstMatch
            guard row.waitForExistence(timeout: 8) else {
                missingRow.append(name)
                continue
            }
            row.tap()

            let heading = app.descendants(matching: .any)[name].firstMatch
            guard heading.waitForExistence(timeout: 8) else {
                missingHeading.append(name)
                app.navigationBars.buttons.element(boundBy: 0).tap()
                continue
            }

            if approximateNames.contains(name) {
                let note = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS %@", "may not be 100% accurate"))
                    .firstMatch
                if !note.waitForExistence(timeout: 8) {
                    missingNote.append(name)
                }
            }

            attach(app, "\(index)-\(name)-detail")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        if !missingRow.isEmpty || !missingHeading.isEmpty || !missingNote.isEmpty {
            attach(app, "missing-summary")
        }
        XCTAssertTrue(missingRow.isEmpty, "Rows not found via search: \(missingRow)")
        XCTAssertTrue(missingHeading.isEmpty, "Detail screen did not open for: \(missingHeading)")
        XCTAssertTrue(missingNote.isEmpty, "Approximate-animation note not found for: \(missingNote)")
    }
}
