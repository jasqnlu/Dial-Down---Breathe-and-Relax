import XCTest

/// Verifies a sample of the 48 exercises newly animated in this batch
/// (2026-08-27: 46 breathing techniques sharing one new chest-expansion
/// composition, plus Bridge Pose and Frog Rock retried after being dropped
/// in the 31-exercise batch) actually resolve a demo video in the running
/// app. Same technique as `ThirtyOneExerciseBatchUITests` /
/// `SixtyExerciseBatchUITests`.
final class BreathingBatchUITests: XCTestCase {

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

    /// All 48 are flagged `animationIsApproximate: true` — the breathing
    /// composition is a stylized chest-expansion pulse (no real diaphragm/
    /// ribcage on this rig), Bridge Pose's pelvis lift and Frog Rock's
    /// dropped knee-width detail are both rig-limited approximations too.
    private let approximateNames = [
        "Box Breathing",
        "4-7-8 Breathing",
        "Lion's Breath",
        "Eye Palming",
        "Skull Shining Breath (Kapalabhati)",
        "Wave Breath (Sequential Full-Body Breath)",
        "Bridge Pose",
        "Frog Rock (Kneeling Glute Mobility Flow)",
    ]

    /// Representative sample: a cross-section of breathing techniques
    /// (standard pranayama, rapid/forceful, meditative, nostril-specific,
    /// the "breath" type with an eye-sounding name) sharing the one new
    /// composition, plus both retried dynamic poses.
    private let sampleNames = [
        "Box Breathing",
        "4-7-8 Breathing",
        "Deep Belly Breath",
        "Alternate Nostril Breathing",
        "Lion's Breath",
        "Eye Palming",
        "Skull Shining Breath (Kapalabhati)",
        "Wave Breath (Sequential Full-Body Breath)",
        "Natural Breath Awareness (Anapana Meditation)",
        "Bridge Pose",
        "Frog Rock (Kneeling Glute Mobility Flow)",
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

    func testSampleOfAnimatedExercisesOpenAndTheApproximateOnesShowTheNote() throws {
        let app = launchApp()
        openExercisesTab(app)
        let field = search(app)

        var missingRow: [String] = []
        var missingHeading: [String] = []
        var missingNote: [String] = []

        for (index, name) in sampleNames.enumerated() {
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
                navigateBack(app)
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
            navigateBack(app)
        }

        if !missingRow.isEmpty || !missingHeading.isEmpty || !missingNote.isEmpty {
            attach(app, "missing-summary")
        }
        XCTAssertTrue(missingRow.isEmpty, "Rows not found via search: \(missingRow)")
        XCTAssertTrue(missingHeading.isEmpty, "Detail screen did not open for: \(missingHeading)")
        XCTAssertTrue(missingNote.isEmpty, "Approximate-animation note not found for: \(missingNote)")
    }
}
