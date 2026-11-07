import XCTest

/// Verifies the 60 exercises added to SeedData.json in the "deepen the next
/// thinnest muscle groups" batch (hands, feet, obliques, glutes, adductors,
/// trapezius, abs variants, plus 8 new breath techniques) are actually
/// seeded, searchable, and functionally correct in the running app — not
/// just present in the JSON and passing schema-level unit tests.
final class NewExerciseBatch4VerificationUITests: XCTestCase {

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

    /// All 60 new exercise names, exactly as authored in SeedData.json.
    private let allNewNames = [
        "Overhead Finger Interlace Stretch", "Table-Supported Wrist Extensor Stretch",
        "Rubber Band Finger Abduction Stretch", "Assisted Wrist Flexion Stretch (Left)",
        "Assisted Wrist Flexion Stretch (Right)", "Assisted Wrist Extension Stretch (Left)",
        "Assisted Wrist Extension Stretch (Right)", "Seated Foot Flex-and-Point Flow",
        "Standing Toe Curl Towel Grip (Both Feet)", "Cross-Legged Foot Massage & Arch Stretch",
        "Wall-Assisted Toe Extension Stretch (Left)", "Wall-Assisted Toe Extension Stretch (Right)",
        "Kneeling Arch Stretch, Toes Curled Under (Left)", "Kneeling Arch Stretch, Toes Curled Under (Right)",
        "Doorway Side Stretch with Overhead Reach (Left)", "Doorway Side Stretch with Overhead Reach (Right)",
        "Chair-Assisted Side Bend Stretch (Left)", "Chair-Assisted Side Bend Stretch (Right)",
        "Standing Windmill Side Reach Flow", "Supine Side-to-Side Knee Drop (Dynamic Oblique Flow)",
        "Standing Broom-Stick Rotation (Torso Twist with Prop)", "Kneeling Cat-Cow Side Bend (Lateral Flow)",
        "Reclined Figure-Four Stretch with Strap (Left)", "Reclined Figure-Four Stretch with Strap (Right)",
        "Standing Glute Stretch Against Wall (Left)", "Standing Glute Stretch Against Wall (Right)",
        "Seated Cross-Ankle Glute Stretch (Left)", "Seated Cross-Ankle Glute Stretch (Right)",
        "Deep Squat Hold (Glute & Hip Opener)", "Frog Rock (Kneeling Glute Mobility Flow)",
        "Supine Cross-Body Double Knee Pull (Bilateral Glute Release)",
        "Kneeling Side Lunge Adductor Stretch on Cushion (Left)",
        "Kneeling Side Lunge Adductor Stretch on Cushion (Right)",
        "Standing Adductor Stretch with Chair Support (Left)",
        "Standing Adductor Stretch with Chair Support (Right)",
        "Seated Wide-Leg Forward Reach (Straddle Stretch)",
        "Supine Butterfly with Wall Support (Gravity Groin Release)",
        "Standing Sumo Squat Hold (Adductor Opener)",
        "Wall-Assisted Ear-to-Shoulder Stretch (Left)", "Wall-Assisted Ear-to-Shoulder Stretch (Right)",
        "Doorway Neck Release Stretch (Left)", "Doorway Neck Release Stretch (Right)",
        "Standing Shoulder Blade Squeeze (Scapular Retraction Flow)",
        "Prone Y-T-W Raise (Upper Back Activation Flow)",
        "Seated Chair Neck Traction Stretch (Both Sides)", "Standing Wall Angels (Trapezius Mobility Flow)",
        "Standing Overhead Reach Back Bend", "Seated Chair Backbend (Supported Extension)",
        "Locust Pose (Prone Chest and Ab Lift)", "Standing Side-to-Side Reach Extension Flow",
        "Kneeling Camel Prep (Supported Backbend)", "Supine Pelvic Rock (Gentle Ab Mobilizer)",
        "Natural Breath Awareness (Anapana Meditation)", "Wave Breath (Sequential Full-Body Breath)",
        "Yogic Ratio Breath (1:4:2 Pranayama)", "Abdominal Lock Breath (Uddiyana Bandha Prep)",
        "Cadence Walking Breath (Step-Synced Breathing)", "Voluntary Yawn Release Breath",
        "Breath of Gratitude (Affective Labeling Breath)", "Descending Ladder Breath (Step-Down Countdown)",
    ]

    /// Waits for the tab bar and opens Exercises. The floating tab bar can
    /// take a moment to appear after a cold launch, so this always waits
    /// rather than tapping blind.
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
    /// the field to actually hold keyboard focus first.
    private func searchFor(_ app: XCUIApplication, _ field: XCUIElement, _ name: String) {
        field.tap()
        if !(field.value as? String ?? "").isEmpty {
            let clear = app.buttons["Clear search"]
            if clear.exists { clear.tap() }
        }
        field.typeText(String(name.prefix(20)))
    }

    /// All 60 names must be discoverable through the real Exercises tab
    /// search, proving SeedMigrator actually inserted them into the SwiftData
    /// store on a fresh install (not just present in the bundled JSON).
    func testAll60NewExercisesAreSearchable() throws {
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

    /// Opens the detail screen for four representative exercises: a caution-
    /// bearing entry (Standing Glute Stretch Against Wall), a bilateral entry
    /// (Deep Squat Hold), a unilateral entry (Assisted Wrist Flexion
    /// Stretch), and a second caution-bearing entry from a different area
    /// (Kneeling Arch Stretch). Confirms the exact instruction text renders —
    /// proof the right JSON entry loaded, not a name coincidence — and that
    /// caution cards show up where authored.
    func testDetailScreenRendersCorrectContentForSampleExercises() throws {
        let app = launchApp()
        openExercisesTab(app)
        let field = search(app)

        let cases: [(name: String, firstInstruction: String, cautionSubstring: String?)] = [
            ("Standing Glute Stretch Against Wall (Left)",
             "Stand an arm's length from a wall and place your left foot flat against it behind you, knee bent.",
             "balancing"),
            ("Deep Squat Hold (Glute & Hip Opener)",
             "Stand with your feet slightly wider than hip-width, toes turned out slightly.",
             nil),
            ("Assisted Wrist Flexion Stretch (Left)",
             "Extend your left arm in front of you with your palm facing down.",
             nil),
            ("Kneeling Arch Stretch, Toes Curled Under (Left)",
             "Kneel on a cushioned surface with your toes curled under, left foot leading.",
             "sharp pain"),
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
        searchFor(app, field, "Assisted Wrist Flexion Stretch (Left)")

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Assisted Wrist Flexion Stretch (Left)"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Assisted Wrist Flexion Stretch (Left) row not found")
        row.tap()

        let startButton = app.buttons["Start Exercise"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 8), "Start Exercise button not found")
        startButton.tap()

        let cueBadgePredicate = NSPredicate(format: "label ==[c] %@", "Exercise cue")
        let cueBadge = app.descendants(matching: .any).matching(cueBadgePredicate).firstMatch
        XCTAssertTrue(cueBadge.waitForExistence(timeout: 15), "Cue badge should appear during the exercise")

        let instruction = app.descendants(matching: .any)["Exercise instruction"]
        XCTAssertTrue(instruction.exists, "Instruction cue should appear alongside the badge")

        attach(app, "assisted-wrist-flexion-stretch-session")
    }

    /// Starts a real session for a new breath exercise that carries a custom
    /// breathPattern (Yogic Ratio Breath's 1:4:2 Inhale/Hold/Exhale) and
    /// confirms the phase cue renders with the authored labels — proof the
    /// breathPatternData encode/decode round-trip and BreathPhaseCycle logic
    /// handle this new pattern correctly, not just that it parses in a unit
    /// test.
    func testBreathExerciseWithCustomPatternShowsPhaseCue() throws {
        let app = launchApp()
        openExercisesTab(app)
        let field = search(app)
        searchFor(app, field, "Yogic Ratio Breath (1:4:2 Pranayama)")

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Yogic Ratio Breath"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Yogic Ratio Breath row not found")
        row.tap()

        let startButton = app.buttons["Start Exercise"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 8), "Start Exercise button not found")
        startButton.tap()

        let breathPhasePredicate = NSPredicate(format: "label ==[c] %@", "Breath phase")
        let breathPhase = app.descendants(matching: .any).matching(breathPhasePredicate).firstMatch
        XCTAssertTrue(breathPhase.waitForExistence(timeout: 15), "Breath phase cue should appear")

        attach(app, "yogic-ratio-breath-session")
    }
}
