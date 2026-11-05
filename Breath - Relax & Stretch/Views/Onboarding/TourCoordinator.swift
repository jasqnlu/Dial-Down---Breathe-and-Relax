import SwiftUI
import Combine

/// One stop on the coach-mark tour. `id` matches a `.tourAnchor(id:)` tag
/// on the real view being called out (or is used purely as a lookup key
/// for `fixedFrame` steps, which skip anchor tracking entirely — see the
/// spec's "Toolbar items" section for why).
struct TourStep: Identifiable {
    let id: String
    /// Which `HomeView` tab this step needs. `nil` means "stay on whatever
    /// tab the previous step left us on" — every section's first step
    /// carries a tabIndex, no other step does.
    let tabIndex: Int?
    let title: String
    let message: String
    /// True for steps that wait for a real tap (the Areas / Body switch and
    /// the two body-map steps) instead of a Next button.
    let isInteractive: Bool
    /// Short "do this to continue" line shown on interactive steps.
    let hint: String?
    /// Screen-relative fallback for a toolbar-hosted callout, where
    /// `.tourAnchor` can't cross the `NavigationStack` → `UINavigationController`
    /// boundary reliably. No current step needs this (the tour is anchor-only
    /// now), but the mechanism stays available for a future toolbar callout.
    let fixedFrame: ((GeometryProxy) -> CGRect)?

    init(id: String, tabIndex: Int? = nil, title: String, message: String,
         isInteractive: Bool = false, hint: String? = nil,
         fixedFrame: ((GeometryProxy) -> CGRect)? = nil) {
        self.id = id
        self.tabIndex = tabIndex
        self.title = title
        self.message = message
        self.isInteractive = isInteractive
        self.hint = hint
        self.fixedFrame = fixedFrame
    }
}

extension TourStep: Equatable {
    // Closures aren't Equatable — steps are uniquely identified by id anyway,
    // so equality only needs to compare that.
    static func == (lhs: TourStep, rhs: TourStep) -> Bool { lhs.id == rhs.id }
}

extension TourStep {
    /// Ids of the two full-screen cards that open and close the tour. They
    /// have no spotlight target and aren't counted in a section's "x / y".
    static let welcomeID = "tour.welcome"
    static let finishID = "tour.finish"

    /// A walk through every part of the app, one section per tab. Each
    /// section's first step carries its tab's `tabIndex` (HomeView switches
    /// tabs on it); the steps after it stay on that tab. Three steps wait for
    /// a real tap: flipping the Exercises switch to Body, then tapping a sore
    /// spot and "Find Stretches" — the flow worth teaching by doing.
    /// `ExercisesTabView` flips the Areas / Body switch to match each step.
    static let allSteps: [TourStep] = [
        // MARK: Welcome
        TourStep(id: welcomeID, tabIndex: AppTab.today.rawValue,
                 title: "Welcome to Dial Down",
                 message: "Here's a quick look around — about a minute. You can skip ahead or leave anytime."),

        // MARK: Today
        TourStep(id: "today.heroCard",
                 title: "Today's Session",
                 message: "A short routine picked for you each day. Tap Begin to start, or the sliders to change what's in it. Days you stretch fill in on the week strip."),
        TourStep(id: "today.recommended",
                 title: "Recommended for You",
                 message: "Stretches for the areas you chose at sign-up. Swipe through and tap one to see how it's done."),

        // MARK: Exercises
        TourStep(id: "exercises.search", tabIndex: AppTab.exercises.rawValue,
                 title: "Find Any Exercise",
                 message: "Search the full library by name, filter by type, difficulty or length, or tap the check to pick a few and build a quick routine."),
        TourStep(id: "exercises.browseByArea",
                 title: "Browse by Area",
                 message: "Each bubble is a body area. Tap one to see its stretches, and pinch or drag to explore."),
        TourStep(id: "exercises.modeSwitch",
                 title: "Switch to the Body",
                 message: "Know where it hurts but not what it's called? The 3D body map finds stretches for the exact spot.",
                 isInteractive: true, hint: "Tap Body to continue"),
        TourStep(id: "bodymap.tapRegion",
                 title: "Tap a Sore Spot",
                 message: "Tap anywhere that feels tense or sore — the body turns to face it and zooms in to the exact muscle.",
                 isInteractive: true, hint: "Tap the body to continue"),
        TourStep(id: "bodymap.findStretches",
                 title: "Find Stretches",
                 message: "Pick the muscle, then tap here for stretches that target it. Tap outside the body anytime to zoom back out.",
                 isInteractive: true, hint: "Tap the bar to continue"),

        // MARK: Breathe
        TourStep(id: "breathe.patternPicker", tabIndex: AppTab.breathe.rawValue,
                 title: "Pick a Pattern",
                 message: "Box breathing, 4-7-8, belly breathing and more — each tuned for calm, sleep or energy."),
        TourStep(id: "breathe.previewCircle",
                 title: "Breathe Along",
                 message: "Tap the circle to try one round, then start a full session when you're ready."),

        // MARK: Routines
        TourStep(id: "routines.sharedList", tabIndex: AppTab.routines.rawValue,
                 title: "Premade Routines",
                 message: "Ready-made routines for the office, recovery, sleep and more. Open one to tweak it and save it as your own."),
        TourStep(id: "routines.yourRoutines",
                 title: "Your Routines",
                 message: "Everything you save lands here. Swipe right to pin one to Today, or left to edit or share it."),

        // MARK: Profile
        TourStep(id: "profile.stats", tabIndex: AppTab.profile.rawValue,
                 title: "Your Progress",
                 message: "Points, streaks and badges add up as you go. Progress & Charts shows the bigger picture."),
        TourStep(id: finishID,
                 title: "You're All Set",
                 message: "Take a breath and start with Today's session. You can replay this tour anytime from Profile → Settings."),
    ]
}

/// Drives the coach-mark tour: which step is current, and how
/// Back/Next/Skip/Restart move through the step catalog. Pure state —
/// `TourSpotlightOverlay` renders whatever `currentStep` says, and
/// `HomeView`/`ProfileView` read it to drive their own tab state.
final class TourCoordinator: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var currentStepIndex = 0

    let steps: [TourStep]

    init(steps: [TourStep] = TourStep.allSteps) {
        self.steps = steps
    }

    var currentStep: TourStep? {
        steps.indices.contains(currentStepIndex) ? steps[currentStepIndex] : nil
    }

    var stepNumber: Int { currentStepIndex + 1 }
    var totalSteps: Int { steps.count }

    /// True on the first step of the tour, or any step that switches tabs —
    /// `back()` refuses to walk past this, so it never re-triggers a
    /// backward tab switch.
    var isFirstStepInSection: Bool {
        guard currentStepIndex > 0 else { return true }
        return steps[currentStepIndex].tabIndex != nil
    }

    func restart() {
        currentStepIndex = 0
        isActive = true
    }

    func advance() {
        guard isActive else { return }
        if currentStepIndex >= steps.count - 1 {
            finish()
        } else {
            currentStepIndex += 1
        }
    }

    func back() {
        guard isActive, !isFirstStepInSection else { return }
        currentStepIndex -= 1
    }

    /// Jumps to the next section's first step (the next step with a
    /// non-nil tabIndex different from the current section's), or finishes
    /// the tour if already in the last section.
    func skipToNextSection() {
        guard isActive else { return }
        let currentTab = sectionTab(atOrBefore: currentStepIndex)
        let remaining = steps[(currentStepIndex + 1)...]
        if let nextIndex = remaining.firstIndex(where: { $0.tabIndex != nil && $0.tabIndex != currentTab }) {
            currentStepIndex = nextIndex
        } else {
            finish()
        }
    }

    func finish() {
        isActive = false
    }

    /// Real views call this when the user performs the action an
    /// interactive step is waiting for. No-op unless the current step is
    /// interactive and its id matches — so a stray call from an unrelated
    /// screen, or a call after the tour already moved on, does nothing.
    func notifyInteraction(id: String) {
        guard isActive, let step = currentStep, step.isInteractive, step.id == id else { return }
        advance()
    }

    /// The tab of the section the current step belongs to.
    var currentSectionTab: Int? { sectionTab(atOrBefore: currentStepIndex) }

    /// Each section's tab, in tour order — one entry per progress segment.
    var sectionTabs: [Int] {
        var seen: [Int] = []
        for tab in steps.compactMap(\.tabIndex) where !seen.contains(tab) { seen.append(tab) }
        return seen
    }

    /// Where the current step sits within its section ("2 of 3"), counting
    /// only spotlight steps — the welcome and finish cards aren't counted.
    /// Nil on those cards.
    var positionInSection: (index: Int, count: Int)? {
        guard let step = currentStep, !Self.isCardOnly(step) else { return nil }
        var start = currentStepIndex
        while start > 0, steps[start].tabIndex == nil { start -= 1 }
        var end = currentStepIndex + 1
        while end < steps.count, steps[end].tabIndex == nil { end += 1 }
        let counted = steps[start..<end].enumerated().filter { !Self.isCardOnly($0.element) }
        guard let index = counted.firstIndex(where: { $0.offset + start == currentStepIndex }) else { return nil }
        return (index + 1, counted.count)
    }

    /// The welcome and finish cards: centered, no spotlight target.
    static func isCardOnly(_ step: TourStep) -> Bool {
        step.id == TourStep.welcomeID || step.id == TourStep.finishID
    }

    /// Walks backward from `index` to the most recent step that declared a
    /// tabIndex — needed because most steps in a section (including both
    /// interactive body-map steps) carry `tabIndex == nil`.
    private func sectionTab(atOrBefore index: Int) -> Int? {
        for i in stride(from: index, through: 0, by: -1) {
            if let tab = steps[i].tabIndex { return tab }
        }
        return nil
    }
}
