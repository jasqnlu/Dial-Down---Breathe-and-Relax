import XCTest

/// Verifies the 40 exercises newly animated in the "even split" batch
/// (quadriceps, calves/tibialis, neck/trapezius, lats, obliques, abs/
/// backbend, glutes/hip, and adductors — 5 exercises per family) actually
/// resolve a demo video in the running app. Same technique as
/// `ThinCoverageAnimationBatchUITests`.
final class EvenSplitAnimationBatch40UITests: XCTestCase {

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

    /// Flagged `animationIsApproximate: true` — the ankle-drop mechanism
    /// can't be shown on this rig (no independent ankle/foot bone).
    private let approximateNames = [
        "Standing Calf Stretch on Stair Edge (Left)",
        "Standing Calf Stretch on Stair Edge (Right)",
    ]

    /// Not flagged approximate — real motion.
    private let exactNames = [
        "Standing Quad Stretch Against Wall (Left)",
        "Standing Quad Stretch Against Wall (Right)",
        "Standing Quad Stretch with Chair Support (Left)",
        "Side-Lying Quad Stretch with Strap (Left)",
        "Side-Lying Quad Stretch with Strap (Right)",
        "Kneeling Tibialis Stretch, Toes Tucked (Left)",
        "Kneeling Tibialis Stretch, Toes Tucked (Right)",
        "Standing Tibialis Stretch Against Wall",
        "Wall-Assisted Ear-to-Shoulder Stretch (Left)",
        "Wall-Assisted Ear-to-Shoulder Stretch (Right)",
        "Doorway Neck Release Stretch (Left)",
        "Doorway Neck Release Stretch (Right)",
        "Standing Wall Angels (Trapezius Mobility Flow)",
        "Overhead Lat Stretch at Doorframe (Left)",
        "Overhead Lat Stretch at Doorframe (Right)",
        "Side-Bend Lat Stretch with Chair (Left)",
        "Side-Bend Lat Stretch with Chair (Right)",
        "Kneeling Lat Stretch, Arms Extended",
        "Doorway Side Stretch with Overhead Reach (Left)",
        "Doorway Side Stretch with Overhead Reach (Right)",
        "Chair-Assisted Side Bend Stretch (Left)",
        "Chair-Assisted Side Bend Stretch (Right)",
        "Standing Windmill Side Reach Flow",
        "Standing Overhead Reach Back Bend",
        "Seated Chair Backbend (Supported Extension)",
        "Locust Pose (Prone Chest and Ab Lift)",
        "Kneeling Camel Prep (Supported Backbend)",
        "Supine Pelvic Rock (Gentle Ab Mobilizer)",
        "Reclined Figure-Four Stretch with Strap (Left)",
        "Reclined Figure-Four Stretch with Strap (Right)",
        "Seated Cross-Ankle Glute Stretch (Left)",
        "Seated Cross-Ankle Glute Stretch (Right)",
        "Supine Cross-Body Double Knee Pull (Bilateral Glute Release)",
        "Seated Butterfly Stretch",
        "Frog Stretch (Kneeling Groin Stretch)",
        "Standing Adductor Rock (Side-to-Side)",
        "Seated Wide-Leg Forward Reach (Straddle Stretch)",
        "Supine Butterfly with Wall Support (Gravity Groin Release)",
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

    func testAll40AnimatedExercisesOpenAndTheApproximateOnesShowTheNote() throws {
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
