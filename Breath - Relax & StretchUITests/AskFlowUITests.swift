import XCTest

/// End-to-end coverage for the floating Ask button: tap → ask bar → type →
/// chat sheet. On the simulator Apple Intelligence is usually unavailable, so
/// the keyword path answers — which is what these assertions rely on.
final class AskFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "YES", "-hasSeenAppGuide", "YES",
            "-auth.isSignedIn", "YES", "-auth.provider", "guest",
            "-appLanguage", "en",
            "-carousel.paused", "YES",
        ]
        app.launch()
        dismissSystemAlerts()
        return app
    }

    /// The simulator sometimes shows a system "Apple Account Verification"
    /// alert over the app, which swallows every tap. Dismiss it if present.
    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notNow = springboard.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 4) { notNow.tap() }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        // Let springs settle so the shot shows the finished layout.
        Thread.sleep(forTimeInterval: 0.8)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Taps the floating button, types `text` into the ask bar and submits.
    private func ask(_ text: String, in app: XCUIApplication) {
        let button = app.buttons["ask.button"]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "Ask button not found")
        attach(app, "1-resting")
        button.tap()

        let field = app.textFields["ask.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Ask field not found")
        XCTAssertTrue(app.buttons["ask.mic"].exists, "Ask bar mic not found")
        field.typeText(text)
        attach(app, "2-bar")
        field.typeText("\n")

        let sheet = app.descendants(matching: .any)["ask.sheet"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "Chat sheet not presented")
    }

    /// Sends `text` from the open chat's own field.
    private func say(_ text: String, in app: XCUIApplication) {
        let input = app.textFields["ask.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), "Chat input not found")
        XCTAssertTrue(focus(input), "Chat input never took keyboard focus")
        input.typeText(text + "\n")
    }

    /// Taps until `field` has keyboard focus. The panel slides while the ask bar's
    /// keyboard goes away, so the first tap can land where the field just was.
    private func focus(_ field: XCUIElement) -> Bool {
        for _ in 0..<3 {
            field.tap()
            let focused = NSPredicate(format: "hasKeyboardFocus == true")
            let wait = XCTNSPredicateExpectation(predicate: focused, object: field)
            if XCTWaiter().wait(for: [wait], timeout: 2) == .completed { return true }
        }
        return false
    }

    private func trayTotal(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["ask.trayTotal"]
    }

    /// Dictation heard "calf" as "cat" on device. The chat asks instead of guessing,
    /// and the tapped choice is added to (not replacing) the routine.
    func testMisheardWordOffersChoices() throws {
        let app = launch()
        ask("3 exercises for my lower back", in: app)
        let total = trayTotal(app)
        XCTAssertTrue(total.waitForExistence(timeout: 20), "Routine tray not shown")

        say("Can you add a cat exercise to this", in: app)
        let choices = app.buttons.matching(identifier: "ask.choice")
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 20), "No \"Did you mean\" choices")
        XCTAssertTrue(app.buttons["Calves"].exists, "The sound-alike area is offered")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Cat-Cow'")).count > 0, "Exercises named \"cat\" are offered")
        attach(app, "choice-1-offered")

        // Read the tray's own count: the Today page behind the panel has "4 exercises · 6 min".
        let before = total.label
        let offered = ["Upper-Back Cat-Cow (Seated)", "Kneeling Cat-Cow Side Bend (Lateral Flow)", "Cat-Cow Flow"]
        guard let pick = offered.first(where: { app.buttons[$0].exists }) else {
            return XCTFail("No Cat-Cow exercise offered")
        }
        app.buttons[pick].tap()
        let grew = NSPredicate(format: "label BEGINSWITH '4 exercises'")
        let wait = XCTNSPredicateExpectation(predicate: grew, object: total)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 10), .completed,
                       "Choice didn't add to the routine: \(before) → \(total.label)")
        XCTAssertFalse(app.buttons["Calves"].isEnabled, "A choice works once")
        attach(app, "choice-2-added")
    }

    func testRoutineBuildsUpAndSurvivesClosing() throws {
        let app = launch()
        ask("3 exercises for my lower back", in: app)
        let total = trayTotal(app)
        XCTAssertTrue(total.waitForExistence(timeout: 20), "Routine tray not shown")
        XCTAssertTrue(total.label.hasPrefix("3 exercises"), "got \(total.label)")
        attach(app, "side-1-first-request")

        say("2 for my neck", in: app)
        let five = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '5 exercises'")).firstMatch
        XCTAssertTrue(five.waitForExistence(timeout: 20), "Second request didn't add to the routine: \(total.label)")
        attach(app, "side-2-added")

        // The pages under the side panel stay usable.
        XCTAssertTrue(app.buttons["Profile"].isHittable, "Tab bar must stay reachable beside the panel")

        app.buttons["ask.close"].tap()
        let button = app.buttons["ask.button"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(button.value as? String, "5 exercises in your routine")
        attach(app, "side-3-closed-badge")

        button.tap()
        XCTAssertTrue(five.waitForExistence(timeout: 5), "Reopening must keep the routine")
    }

    func testFullScreenShrinkAndReopen() throws {
        let app = launch()
        ask("2 exercises for my neck", in: app)
        XCTAssertTrue(trayTotal(app).waitForExistence(timeout: 20))

        app.buttons["ask.resize"].tap()
        XCTAssertEqual(app.buttons["ask.resize"].label, "Exit full screen")
        attach(app, "full-1-full-screen")

        app.buttons["ask.shrink"].tap()
        let pill = app.buttons["ask.pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "Shrink must leave a pill")
        XCTAssertFalse(app.descendants(matching: .any)["ask.sheet"].firstMatch.exists)
        attach(app, "full-2-pill")

        pill.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ask.sheet"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["ask.resize"].label, "Full screen", "the pill reopens the side panel")
    }

    func testCustomizeOpensWithTheRoutineAndAddReturns() throws {
        let app = launch()
        ask("3 exercises for my lower back", in: app)
        XCTAssertTrue(trayTotal(app).waitForExistence(timeout: 20))
        app.buttons["ask.customize"].tap()

        let add = app.buttons["customize.addMore"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "Customize didn't open")
        attach(app, "customize-1-open")
        add.tap()
        XCTAssertTrue(app.textFields["ask.input"].waitForExistence(timeout: 5), "Add must return to the chat")
        XCTAssertTrue(trayTotal(app).label.hasPrefix("3 exercises"))
    }

    func testTypeLowerBackShowsRoutine() throws {
        let app = launch()
        ask("lower back pain", in: app)
        XCTAssertTrue(app.buttons["ask.start"].waitForExistence(timeout: 20), "Routine Start button not shown")
        attach(app, "3-routine")
    }

    func testMicCanBeTappedBeforeTyping() throws {
        let app = launch()
        let button = app.buttons["ask.button"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        button.tap()

        let field = app.textFields["ask.field"]
        let mic = app.buttons["ask.mic"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(mic.isHittable, "The mic should be tappable with an empty draft")
        mic.tap()

        // Setup may show a system permission alert or report voice unavailable.
        // The ask bar must remain responsive in either case.
        XCTAssertTrue(app.descendants(matching: .any)["ask.bar"].firstMatch.waitForExistence(timeout: 5))

        // Leave nothing listening: a mic still running when the app is killed can wedge
        // the simulator's dictation service and stall the next test's text-field queries.
        let active = app.buttons.matching(identifier: "ask.mic")
            .matching(NSPredicate(format: "label != %@", "Dictate")).firstMatch
        if active.exists { active.tap() }
    }

    func testChatMicCanBeTappedAgainDuringVoiceSetup() throws {
        let app = launch()
        ask("lower back pain", in: app)

        let mic = app.buttons["ask.mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5))
        mic.tap()

        let status = app.descendants(matching: .any)["ask.voiceStatus"].firstMatch
        if status.waitForExistence(timeout: 5) {
            XCTAssertTrue(mic.isHittable, "Voice status must not cover the chat mic")
            mic.tap()
            XCTAssertFalse(status.waitForExistence(timeout: 2), "Second tap must stop or cancel voice")
        } else {
            // A permission or model failure can make voice unavailable instead.
            XCTAssertTrue(app.descendants(matching: .any)["ask.voiceIssue"].firstMatch.exists)
        }
        XCTAssertTrue(app.buttons["Close"].isHittable, "The chat must remain dismissible")
    }

    func testChatVoiceSetupResolvesAndChatStaysUsable() throws {
        let app = launch()
        ask("lower back pain", in: app)

        let mic = app.buttons["ask.mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5))
        mic.tap()

        let stop = app.buttons.matching(identifier: "ask.mic")
            .matching(NSPredicate(format: "label == %@", "Stop and send")).firstMatch
        let issue = app.descendants(matching: .any)["ask.voiceIssue"].firstMatch
        let ready = stop.waitForExistence(timeout: 15)
        if ready {
            stop.tap()
        } else {
#if targetEnvironment(simulator)
            XCTAssertTrue(issue.waitForExistence(timeout: 3), "Voice never left setup")
#else
            XCTFail("On-device voice never began listening: \(issue.exists ? "unavailable" : "stuck preparing")")
#endif
        }
        XCTAssertFalse(app.descendants(matching: .any)["ask.voiceStatus"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Close"].isHittable)
    }

    func testUrgentShowsNoStart() throws {
        let app = launch()
        ask("chest pain", in: app)
        XCTAssertTrue(app.buttons["ask.emergency"].waitForExistence(timeout: 20), "Emergency button not shown")
        XCTAssertFalse(app.buttons["ask.start"].exists, "Urgent reply must not offer Start")
        attach(app, "4-urgent")
    }

    func testGentleAnywayKeepsSafetyAdvice() throws {
        let app = launch()
        ask("sharp pain in my lower back", in: app)
        let anyway = app.buttons["ask.gentleAnyway"]
        XCTAssertTrue(anyway.waitForExistence(timeout: 20), "Gentle-anyway option not shown")
        anyway.tap()
        XCTAssertTrue(app.buttons["ask.start"].waitForExistence(timeout: 10), "Gentle routine not shown")
        XCTAssertTrue(app.buttons["ask.emergency"].exists, "Safety card must stay visible")
        XCTAssertFalse(app.buttons["ask.gentleAnyway"].exists, "Gentle-anyway must hide once used")
        attach(app, "5-gentle-anyway")
    }
}
