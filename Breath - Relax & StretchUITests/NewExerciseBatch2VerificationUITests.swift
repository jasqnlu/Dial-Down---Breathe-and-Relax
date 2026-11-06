import XCTest

/// Verifies the 35 exercises added to SeedData.json in the "fill the thin
/// spots" batch (hands, feet, jaw, temple, forehead, eye, head, hip/shoulder
/// joints, lower spine, neck, plus biceps/triceps/tibialis/trapezius
/// variants, plus 5 breath exercises) are actually seeded, searchable, and
/// functionally correct in the running app — not just present in the JSON
/// and passing schema-level unit tests.
final class NewExerciseBatch2VerificationUITests: XCTestCase {

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

    /// All 35 new exercise names, exactly as authored in SeedData.json.
    private let allNewNames = [
        "Thumb Extension Stretch (Left)", "Thumb Extension Stretch (Right)",
        "Hook Fist Tendon Glide", "Fist-to-Fan Tendon Gliding Flow",
        "Towel Scrunch (Toe Flexor Stretch)",
        "Big Toe Extension Stretch (Left)", "Big Toe Extension Stretch (Right)",
        "Seated Toe-to-Shin Stretch (Left)", "Seated Toe-to-Shin Stretch (Right)",
        "Jaw Relaxation Drop", "Circular Temple Self-Massage",
        "Figure-8 Eye Tracking", "Full Scalp Massage (Tension Release)",
        "90/90 Hip Switch (Rotation Flow)",
        "Shoulder Pendulum Swing (Left)", "Shoulder Pendulum Swing (Right)",
        "Standing Lumbar Side Glide (Lateral Shift)",
        "Neck Isometric Front-and-Back Press",
        "Seated Neck Half-Circles (Ear-to-Shoulder Arc)",
        "Table-Edge Bicep Stretch (Left)", "Table-Edge Bicep Stretch (Right)",
        "Standing Cross-Body Triceps Press (Left)", "Standing Cross-Body Triceps Press (Right)",
        "Seated Assisted Tibialis Stretch (Left)", "Seated Assisted Tibialis Stretch (Right)",
        "Active Shoulder Shrug & Release (Left)", "Active Shoulder Shrug & Release (Right)",
        "Grip and Release (Hand Squeeze Stretch)",
        "Standing Waist Twist (Dynamic Rotation Flow)",
        "Wall Slide (Shoulder Blade Mobility)",
        "Triangle Breathing (3-3-3)", "So-Hum Mantra Breath",
        "Breath Counting Meditation", "Segmented Inhale Breathing (Viloma 2)",
        "5-4-3-2-1 Grounding Breath",
    ]

    /// Waits for the tab bar and opens Exercises. The floating tab bar can
    /// take a moment to appear after a cold launch, so this always waits
    /// rather than tapping blind (a bare `.firstMatch.tap()` on a
    /// not-yet-existing element is exactly what made the first run's tab
    /// tap flake).
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

    /// Focuses the search field, clears any existing text, and types `name`.
    /// `field.tap()` must happen before every `typeText` — XCUITest requires
    /// the field to actually hold keyboard focus first, which a bare
    /// `typeText` on an unfocused field fails with "Neither element nor any
    /// descendant has keyboard focus".
    private func searchFor(_ app: XCUIApplication, _ field: XCUIElement, _ name: String) {
        field.tap()
        if !(field.value as? String ?? "").isEmpty {
            let clear = app.buttons["Clear search"]
            if clear.exists { clear.tap() }
        }
        field.typeText(String(name.prefix(20)))
    }

    /// All 35 names must be discoverable through the real Exercises tab
    /// search, proving SeedMigrator actually inserted them into the SwiftData
    /// store on a fresh install (not just present in the bundled JSON).
    func testAll35NewExercisesAreSearchable() throws {
        let app = launchApp()
        openExercisesTab(app)
        let field = search(app)

        var missing: [String] = []
        for name in allNewNames {
            searchFor(app, field, name)
            let row = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", name))
                .firstMatch
            if !row.waitForExistence(timeout: 8) { missing.append(name) }
        }

        if !missing.isEmpty { attach(app, "missing-exercises") }
        XCTAssertTrue(missing.isEmpty, "Exercises not found via search: \(missing)")
    }

    /// Opens the detail screen for four exercises that each carry the
    /// highest-risk content from this batch: a caution string (Jaw
    /// Relaxation Drop), and the two entries whose targetBodyParts needed a
    /// companion muscle-group tag to resolve into an ExerciseCategory (90/90
    /// Hip Switch, Shoulder Pendulum Swing). Confirms the exact instruction
    /// text renders — proof the right JSON entry loaded, not a name
    /// coincidence — and that the caution card shows up.
    func testDetailScreenRendersCorrectContentForSampleExercises() throws {
        let app = launchApp()
        openExercisesTab(app)
        let field = search(app)

        let cases: [(name: String, firstInstruction: String, cautionSubstring: String?)] = [
            ("Jaw Relaxation Drop",
             "Sit or stand comfortably and let your shoulders relax.",
             "TMJ"),
            ("90/90 Hip Switch (Rotation Flow)",
             "Sit on the floor with both knees bent, one leg in front of you and one out to the side, each at roughly 90 degrees.",
             nil),
            ("Shoulder Pendulum Swing (Left)",
             "Lean forward slightly and support yourself with your right hand on a chair or table.",
             nil),
            ("Standing Lumbar Side Glide (Lateral Shift)",
             "Stand with your feet hip-width apart and arms relaxed at your sides.",
             nil),
        ]

        for (index, testCase) in cases.enumerated() {
            searchFor(app, field, testCase.name)
            let row = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", testCase.name))
                .firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 8), "\(testCase.name) row not found")
            row.tap()

            let heading = app.descendants(matching: .any)[testCase.name].firstMatch
            XCTAssertTrue(heading.waitForExistence(timeout: 8), "\(testCase.name) detail screen did not open")

            let instructionText = app.staticTexts[testCase.firstInstruction]
            XCTAssertTrue(instructionText.waitForExistence(timeout: 5),
                          "\(testCase.name) should show its authored first instruction verbatim")

            if let cautionSubstring = testCase.cautionSubstring {
                let cautionPredicate = NSPredicate(format: "label CONTAINS %@", cautionSubstring)
                let caution = app.staticTexts.matching(cautionPredicate).firstMatch
                XCTAssertTrue(caution.waitForExistence(timeout: 5),
                              "\(testCase.name) should show a caution card mentioning \(cautionSubstring)")
            }

            attach(app, "\(index)-\(testCase.name)-detail")

            // Back to the search list for the next case.
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    /// Starts a real session for a new unilateral stretch and confirms the
    /// session player renders the cue badge and instruction — the same
    /// live-rendering path every exercise in the app goes through, so a
    /// crash or blank player here would mean the seeded data is malformed in
    /// a way the schema checks didn't catch.
    func testUnilateralStretchStartsAndRendersInSessionPlayer() throws {
        let app = launchApp()
        openExercisesTab(app)
        let field = search(app)
        searchFor(app, field, "Table-Edge Bicep Stretch (Left)")

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Table-Edge Bicep Stretch (Left)"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Table-Edge Bicep Stretch (Left) row not found")
        row.tap()

        let startButton = app.buttons["Start Exercise"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 8), "Start Exercise button not found")
        startButton.tap()

        let cueBadgePredicate = NSPredicate(format: "label ==[c] %@", "Exercise cue")
        let cueBadge = app.descendants(matching: .any).matching(cueBadgePredicate).firstMatch
        XCTAssertTrue(cueBadge.waitForExistence(timeout: 15), "Cue badge should appear during the exercise")

        let instruction = app.descendants(matching: .any)["Exercise instruction"]
        XCTAssertTrue(instruction.exists, "Instruction cue should appear alongside the badge")

        attach(app, "table-edge-bicep-stretch-session")
    }

    /// Starts a real session for a new breath exercise that carries a custom
    /// breathPattern (Triangle Breathing's 3-3-3 Inhale/Hold/Exhale) and
    /// confirms the phase cue renders with the authored labels — proof the
    /// breathPatternData encode/decode round-trip and BreathPhaseCycle logic
    /// handle this new pattern correctly, not just that it parses in a unit
    /// test.
    func testBreathExerciseWithCustomPatternShowsPhaseCue() throws {
        let app = launchApp()
        openExercisesTab(app)
        let field = search(app)
        searchFor(app, field, "Triangle Breathing (3-3-3)")

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Triangle Breathing"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Triangle Breathing row not found")
        row.tap()

        let startButton = app.buttons["Start Exercise"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 8), "Start Exercise button not found")
        startButton.tap()

        let breathPhasePredicate = NSPredicate(format: "label ==[c] %@", "Breath phase")
        let breathPhase = app.descendants(matching: .any).matching(breathPhasePredicate).firstMatch
        XCTAssertTrue(breathPhase.waitForExistence(timeout: 15), "Breath phase cue should appear")

        let value = breathPhase.value as? String ?? ""
        XCTAssertTrue(value.contains("Inhale") || value.contains("Hold") || value.contains("Exhale"),
                      "Breath phase value should name one of Triangle Breathing's authored phases, got '\(value)'")

        attach(app, "triangle-breathing-phase-cue")
    }
}
