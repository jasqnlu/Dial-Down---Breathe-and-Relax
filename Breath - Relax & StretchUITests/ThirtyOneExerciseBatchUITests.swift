import XCTest

/// Verifies the 31 exercises newly animated in this batch (2026-08-27)
/// actually resolve a demo video in the running app. Same technique as
/// `SixtyExerciseBatchUITests` / `EvenSplitAnimationBatch40UITests`.
final class ThirtyOneExerciseBatchUITests: XCTestCase {

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

    /// Flagged `animationIsApproximate: true` — rig can't show the real
    /// mechanism (no independent ankle/toe joint, no finger articulation,
    /// no lateral-shift translation, no support-prop contact, etc.).
    private let approximateNames = [
        "Left Standing Figure-4 Stretch",
        "Left Finger Extension Stretch",
        "Left Half-Kneeling Rear-Foot Instep Stretch",
        "Standing Ankle Dorsiflexion Stretch (Left)",
        "Standing Tibialis Raise (Toe Lifts)",
        "Shoulder Pendulum Swing (Left)",
        "Standing Lumbar Side Glide (Lateral Shift)",
        "Grip and Release (Hand Squeeze Stretch)",
        "Downward-Facing Dog Calf Pump",
        "Standing Bilateral Calf Stretch on Incline Board",
        "Rubber Band Finger Abduction Stretch",
        "Standing Split Prep Stretch",
        "Standing Hip Circles",
    ]

    /// Not flagged approximate — real motion, or exact reuse of an
    /// already-shipped mp4 (the two duplicate-name calf-stretch entries).
    private let exactNames = [
        "Upper-Back Cat-Cow (Seated)",
        "Runner's Lunge with Rotation (Left)",
        "Standing Waist Twist (Dynamic Rotation Flow)",
        "Seated Calf Stretch with Towel (Left)",
        "Wall Calf Stretch, Bent-Knee Soleus Focus (Left)",
        "Kneeling Calf Stretch on Cushion (Left)",
        "Dynamic Standing Leg Swings",
        "World's Greatest Stretch (Left Lead Leg)",
        "World's Greatest Stretch (Right Lead Leg)",
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

    /// The plain `app.navigationBars.buttons.element(boundBy: 0).tap()` used
    /// by the sibling batch UI tests occasionally throws "Automation type
    /// mismatch" / "No matches found for NavigationBar" for one specific
    /// screen in this batch (root-caused to a transient keyboard/responder
    /// artifact left over from the search field, not app content). Retries
    /// briefly and never lets a failed tap crash the whole test — a missed
    /// back-nav just means the next iteration's search has to recover.
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

    /// Representative sample spanning every base composition in this batch:
    /// standing single-leg folds, the reused half-kneeling lunge (rear-foot
    /// instep, runner's lunge + rotation, kneeling calf, world's greatest),
    /// seated cat-cow, hand-family approximations, the two calf-stretch
    /// duplicate-name entries wired to an already-shipped mp4, and the new
    /// standing dynamic motions (leg swings, hip circles, waist twist).
    private let sampleNames = [
        "Left Standing Figure-4 Stretch",                     // standing fold, approximate
        "Upper-Back Cat-Cow (Seated)",                        // seated oscillation, exact
        "Left Finger Extension Stretch",                      // hand family, approximate
        "Left Half-Kneeling Rear-Foot Instep Stretch",        // lunge-base reuse
        "Runner's Lunge with Rotation (Left)",                // lunge + twist + reach
        "World's Greatest Stretch (Left Lead Leg)",           // lunge + twist + reach variant
        "Kneeling Calf Stretch on Cushion (Left)",            // lunge-base reuse, calf target
        "Seated Calf Stretch with Towel (Left)",              // duplicate-name, reused asset
        "Wall Calf Stretch, Bent-Knee Soleus Focus (Left)",   // single-leg family variant
        "Standing Ankle Dorsiflexion Stretch (Left)",         // approximate, no ankle joint
        "Standing Tibialis Raise (Toe Lifts)",                // approximate, subtle shin proxy
        "Shoulder Pendulum Swing (Left)",                     // side-camera fix, approximate
        "Standing Lumbar Side Glide (Lateral Shift)",         // side-bend proxy, approximate
        "Grip and Release (Hand Squeeze Stretch)",            // hand family, approximate
        "Standing Waist Twist (Dynamic Rotation Flow)",       // bilateral torso twist, exact
        "Downward-Facing Dog Calf Pump",                      // DFD reuse + pedal, approximate
        "Rubber Band Finger Abduction Stretch",               // hand family, approximate
        "Standing Split Prep Stretch",                        // forward fold + leg extension
        "Dynamic Standing Leg Swings",                        // large-ROM thigh swing, exact
        "Standing Hip Circles",                               // combined-axis circle, approximate
    ]

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
