import XCTest

/// Verifies the 8 hand/wrist-family exercises newly animated in this batch
/// (Assisted Wrist Flexion/Extension Stretch L/R, Wrist & Forearm Release,
/// Overhead Finger Interlace Stretch, Table-Supported Wrist Extensor
/// Stretch, Hook Fist Tendon Glide) actually resolve a demo video in the
/// running app — not just that `animationName` is set in SeedData.json, but
/// that the bundled mp4 loads and the media card renders it instead of
/// falling back to the placeholder.
final class HandWristAnimationVerificationUITests: XCTestCase {

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

    private let animatedNames = [
        "Assisted Wrist Flexion Stretch (Left)",
        "Assisted Wrist Flexion Stretch (Right)",
        "Assisted Wrist Extension Stretch (Left)",
        "Assisted Wrist Extension Stretch (Right)",
        "Wrist & Forearm Release",
        "Overhead Finger Interlace Stretch",
        "Table-Supported Wrist Extensor Stretch",
        "Hook Fist Tendon Glide",
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

    /// Opens each of the 8 exercises' detail screens and confirms
    /// `AnimationAccuracyNote` renders — it only appears when
    /// `ExerciseMediaCard` actually took the `demoIsAnimation` branch AND
    /// `animationIsApproximate` is true (see SafetyComponents.swift), which
    /// only happens once `exercise.demoVideoURL` resolved a real bundled
    /// mp4. All 8 of this batch are flagged approximate, so its presence is
    /// proof the animation loaded — not just that `animationName` is set in
    /// SeedData.json, but that SeedMigrator actually seeded it and the
    /// bundled file resolved.
    func testAll8AnimatedExercisesShowTheApproximateAnimationNote() throws {
        let app = launchApp()
        openExercisesTab(app)
        let field = search(app)

        var missingRow: [String] = []
        var missingNote: [String] = []

        for (index, name) in animatedNames.enumerated() {
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
            XCTAssertTrue(heading.waitForExistence(timeout: 8), "\(name) detail screen did not open")

            let note = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "may not be 100% accurate"))
                .firstMatch
            if !note.waitForExistence(timeout: 8) {
                missingNote.append(name)
            }

            attach(app, "\(index)-\(name)-detail")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        if !missingRow.isEmpty || !missingNote.isEmpty { attach(app, "missing-summary") }
        XCTAssertTrue(missingRow.isEmpty, "Rows not found via search: \(missingRow)")
        XCTAssertTrue(missingNote.isEmpty, "Approximate-animation note not found for: \(missingNote)")
    }
}
