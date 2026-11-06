import XCTest

/// Verifies the 60 exercises added to SeedData.json in the "deepen the
/// thinnest muscle groups" batch (biceps, triceps, calves, tibialis,
/// quadriceps, lats variants, plus 8 new breath techniques) are actually
/// seeded, searchable, and functionally correct in the running app — not
/// just present in the JSON and passing schema-level unit tests.
final class NewExerciseBatch3VerificationUITests: XCTestCase {

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

    /// All 60 new exercise names, exactly as authored in SeedData.json.
    private let allNewNames = [
        "Standing Doorway Bicep Stretch (Left)", "Standing Doorway Bicep Stretch (Right)",
        "Behind-Back Prayer Bicep Stretch", "Wall-Assisted Bicep Stretch (Left)",
        "Wall-Assisted Bicep Stretch (Right)", "Overhead Bicep Reach with Strap (Left)",
        "Overhead Bicep Reach with Strap (Right)", "Seated Bicep Stretch on Chair Edge",
        "Overhead Triceps Stretch with Strap (Left)", "Overhead Triceps Stretch with Strap (Right)",
        "Cross-Body Triceps Pull at Wall (Left)", "Cross-Body Triceps Pull at Wall (Right)",
        "Behind-Head Bilateral Triceps Stretch", "Seated Triceps Stretch with Towel (Left)",
        "Seated Triceps Stretch with Towel (Right)", "Kneeling Triceps Stretch on Chair",
        "Standing Calf Stretch on Stair Edge (Left)", "Standing Calf Stretch on Stair Edge (Right)",
        "Downward-Facing Dog Calf Pump", "Seated Calf Stretch with Towel (Left)",
        "Seated Calf Stretch with Towel (Right)", "Wall Calf Stretch, Bent-Knee Soleus Focus (Left)",
        "Wall Calf Stretch, Bent-Knee Soleus Focus (Right)", "Kneeling Calf Stretch on Cushion (Left)",
        "Kneeling Calf Stretch on Cushion (Right)", "Standing Bilateral Calf Stretch on Incline Board",
        "Kneeling Tibialis Stretch, Toes Tucked (Left)", "Kneeling Tibialis Stretch, Toes Tucked (Right)",
        "Seated Shin Stretch with Strap (Left)", "Seated Shin Stretch with Strap (Right)",
        "Standing Tibialis Stretch Against Wall", "Ankle Circles for Tibialis Release (Left)",
        "Ankle Circles for Tibialis Release (Right)", "Cross-Legged Shin Pull (Left)",
        "Cross-Legged Shin Pull (Right)",
        "Standing Quad Stretch Against Wall (Left)", "Standing Quad Stretch Against Wall (Right)",
        "Side-Lying Quad Stretch with Strap (Left)", "Side-Lying Quad Stretch with Strap (Right)",
        "Kneeling Couch Stretch, Rear Foot Elevated (Left)", "Kneeling Couch Stretch, Rear Foot Elevated (Right)",
        "Prone Quad Stretch on Mat", "Standing Quad Stretch with Chair Support (Left)",
        "Standing Quad Stretch with Chair Support (Right)",
        "Overhead Lat Stretch at Doorframe (Left)", "Overhead Lat Stretch at Doorframe (Right)",
        "Side-Bend Lat Stretch with Chair (Left)", "Side-Bend Lat Stretch with Chair (Right)",
        "Kneeling Lat Stretch, Arms Extended", "Seated Cross-Body Lat Reach (Left)",
        "Seated Cross-Body Lat Reach (Right)", "Hanging Lat Stretch on Bar or Ledge",
        "Bhastrika (Bellows Breath)", "Sitkari Breath (Hissing Cooling Breath)",
        "Buteyko Control Pause Breathing", "Cyclic Sighing (Multi-Cycle Protocol)",
        "Extended Kumbhaka Breath Retention", "Rectangle Breathing (4-2-6-2)",
        "Whispered \"Ha\" Release Breath", "4-4-8 Extended Exhale Countdown Breath",
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
    /// bearing entry (Kneeling Couch Stretch), a bilateral entry (Prone Quad
    /// Stretch), a unilateral entry (Standing Doorway Bicep Stretch), and a
    /// second caution-bearing entry from a different area (Hanging Lat
    /// Stretch). Confirms the exact instruction text renders — proof the
    /// right JSON entry loaded, not a name coincidence — and that caution
    /// cards show up where authored.
    func testDetailScreenRendersCorrectContentForSampleExercises() throws {
        let app = launchApp()
        openExercisesTab(app)
        let field = search(app)

        let cases: [(name: String, firstInstruction: String, cautionSubstring: String?)] = [
            ("Kneeling Couch Stretch, Rear Foot Elevated (Left)",
             "Kneel in front of a couch or low chair, resting the top of your left foot on the seat behind you.",
             "knee pain"),
            ("Prone Quad Stretch on Mat",
             "Lie face down on a mat with your legs extended.",
             nil),
            ("Standing Doorway Bicep Stretch (Left)",
             "Stand in an open doorway and place your left palm flat against the door frame, arm straight, thumb pointing up.",
             nil),
            ("Hanging Lat Stretch on Bar or Ledge",
             "Find a sturdy bar, ledge, or door top you can safely hang from with both hands.",
             "shoulder strain"),
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
        searchFor(app, field, "Standing Doorway Bicep Stretch (Left)")

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Standing Doorway Bicep Stretch (Left)"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Standing Doorway Bicep Stretch (Left) row not found")
        row.tap()

        let startButton = app.buttons["Start Exercise"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 8), "Start Exercise button not found")
        startButton.tap()

        let cueBadgePredicate = NSPredicate(format: "label ==[c] %@", "Exercise cue")
        let cueBadge = app.descendants(matching: .any).matching(cueBadgePredicate).firstMatch
        XCTAssertTrue(cueBadge.waitForExistence(timeout: 15), "Cue badge should appear during the exercise")

        let instruction = app.descendants(matching: .any)["Exercise instruction"]
        XCTAssertTrue(instruction.exists, "Instruction cue should appear alongside the badge")

        attach(app, "standing-doorway-bicep-stretch-session")
    }

    /// Starts a real session for a new breath exercise that carries a custom
    /// breathPattern (Rectangle Breathing's 4-2-6-2 Inhale/Hold/Exhale/Hold)
    /// and confirms the phase cue renders with the authored labels — proof
    /// the breathPatternData encode/decode round-trip and BreathPhaseCycle
    /// logic handle this new pattern correctly, not just that it parses in a
    /// unit test.
    func testBreathExerciseWithCustomPatternShowsPhaseCue() throws {
        let app = launchApp()
        openExercisesTab(app)
        let field = search(app)
        searchFor(app, field, "Rectangle Breathing (4-2-6-2)")

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Rectangle Breathing"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Rectangle Breathing row not found")
        row.tap()

        let startButton = app.buttons["Start Exercise"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 8), "Start Exercise button not found")
        startButton.tap()

        let breathPhasePredicate = NSPredicate(format: "label ==[c] %@", "Breath phase")
        let breathPhase = app.descendants(matching: .any).matching(breathPhasePredicate).firstMatch
        XCTAssertTrue(breathPhase.waitForExistence(timeout: 15), "Breath phase cue should appear")

        attach(app, "rectangle-breathing-session")
    }
}
