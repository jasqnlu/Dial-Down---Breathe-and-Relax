import Testing
@testable import BreathRelaxStretch

struct TourCoordinatorTests {
    @Test func catalogHasUniqueIDs() {
        let steps = TourStep.allSteps
        #expect(Set(steps.map(\.id)).count == steps.count)
    }

    /// One section per tab, in tab-bar order.
    @Test func catalogHasOneSectionPerTab() {
        let sectionStarts = TourStep.allSteps.filter { $0.tabIndex != nil }
        #expect(sectionStarts.count == AppTab.allCases.count)
        #expect(sectionStarts.map(\.tabIndex) == AppTab.allCases.map(\.rawValue))
    }

    /// Opens on the welcome card and closes on the finish card.
    @Test func tourStartsWithWelcomeAndEndsWithFinish() {
        #expect(TourStep.allSteps.first?.id == TourStep.welcomeID)
        #expect(TourStep.allSteps.last?.id == TourStep.finishID)
    }

    /// Every tab gets at least one spotlight step, not just a section start.
    @Test func everySectionHasASpotlightStep() {
        let coordinator = TourCoordinator()
        coordinator.restart()
        var tabsWithSpotlight = Set<Int>()
        while coordinator.isActive {
            if let step = coordinator.currentStep, !TourCoordinator.isCardOnly(step),
               let tab = coordinator.currentSectionTab {
                tabsWithSpotlight.insert(tab)
            }
            coordinator.advance()
        }
        #expect(tabsWithSpotlight == Set(AppTab.allCases.map(\.rawValue)))
    }

    private func makeCoordinator() -> TourCoordinator {
        let coordinator = TourCoordinator()
        coordinator.restart()
        return coordinator
    }

    /// Advances (Next, or the interactive step's tap) until `id` is current.
    private func walk(_ coordinator: TourCoordinator, to id: String) {
        while coordinator.isActive, coordinator.currentStep?.id != id { coordinator.advance() }
    }

    @Test func restartActivatesAtStepZero() {
        let coordinator = makeCoordinator()
        #expect(coordinator.isActive == true)
        #expect(coordinator.currentStepIndex == 0)
        #expect(coordinator.currentStep?.id == TourStep.welcomeID)
    }

    @Test func advanceMovesToNextStep() {
        let coordinator = makeCoordinator()
        coordinator.advance()
        #expect(coordinator.currentStep?.id == "today.heroCard")
    }

    @Test func advanceOnLastStepFinishes() {
        let coordinator = TourCoordinator(steps: [
            TourStep(id: "only", tabIndex: 0, title: "T", message: "M"),
        ])
        coordinator.restart()
        coordinator.advance()
        #expect(coordinator.isActive == false)
    }

    @Test func backStaysWithinASection() {
        let coordinator = makeCoordinator()
        walk(coordinator, to: "exercises.browseByArea")
        coordinator.back()
        #expect(coordinator.currentStep?.id == "exercises.search") // first step of the section — back() stops here
        coordinator.back()
        #expect(coordinator.currentStep?.id == "exercises.search") // no-op past the section boundary
    }

    @Test func skipToNextSectionJumpsToNextTabsFirstStep() {
        let coordinator = makeCoordinator()
        walk(coordinator, to: "bodymap.tapRegion") // still the Exercises section
        coordinator.skipToNextSection()
        #expect(coordinator.currentStep?.id == "breathe.patternPicker")
    }

    @Test func skipFromLastSectionFinishesTheTour() {
        let coordinator = makeCoordinator()
        walk(coordinator, to: "profile.stats")
        coordinator.skipToNextSection()
        #expect(coordinator.isActive == false)
    }

    @Test func notifyInteractionAdvancesOnlyWhenIDMatchesTheCurrentInteractiveStep() {
        let coordinator = makeCoordinator()
        walk(coordinator, to: "bodymap.tapRegion")

        coordinator.notifyInteraction(id: "some.other.id")
        #expect(coordinator.currentStep?.id == "bodymap.tapRegion") // no-op: id doesn't match

        coordinator.notifyInteraction(id: "bodymap.tapRegion")
        #expect(coordinator.currentStep?.id == "bodymap.findStretches") // matches: advances
    }

    /// The Areas / Body switch step waits for the Body tap, then hands off
    /// to the body map.
    @Test func modeSwitchStepAdvancesOnBodyTap() {
        let coordinator = makeCoordinator()
        walk(coordinator, to: "exercises.modeSwitch")
        coordinator.notifyInteraction(id: "exercises.modeSwitch")
        #expect(coordinator.currentStep?.id == "bodymap.tapRegion")
    }

    @Test func notifyInteractionIsNoOpOnANonInteractiveStep() {
        let coordinator = makeCoordinator() // welcome card — not interactive
        coordinator.notifyInteraction(id: TourStep.welcomeID)
        #expect(coordinator.currentStep?.id == TourStep.welcomeID)
    }

    @Test func notifyInteractionIsNoOpWhenTourIsInactive() {
        let coordinator = TourCoordinator()
        coordinator.notifyInteraction(id: TourStep.welcomeID)
        #expect(coordinator.isActive == false)
    }

    @Test func restartFromAlreadyIndexZeroStillActivates() {
        let coordinator = TourCoordinator()
        #expect(coordinator.isActive == false)
        #expect(coordinator.currentStepIndex == 0)
        coordinator.restart()
        #expect(coordinator.isActive == true)
        #expect(coordinator.currentStepIndex == 0)
        #expect(coordinator.currentStep?.id == TourStep.welcomeID)
    }

    @Test func interactiveStepsAreTheSwitchAndBodyMapSteps() {
        let interactiveIDs = Set(TourStep.allSteps.filter(\.isInteractive).map(\.id))
        #expect(interactiveIDs == ["exercises.modeSwitch", "bodymap.tapRegion", "bodymap.findStretches"])
        #expect(TourStep.allSteps.filter(\.isInteractive).allSatisfy { $0.hint != nil })
    }

    @Test func noStepHasFixedFrame() {
        let fixedFrameIDs = Set(TourStep.allSteps.filter { $0.fixedFrame != nil }.map(\.id))
        #expect(fixedFrameIDs.isEmpty)
    }

    // MARK: Card progress

    @Test func positionInSectionSkipsTheWelcomeAndFinishCards() {
        let coordinator = makeCoordinator()
        #expect(coordinator.positionInSection == nil) // welcome card
        coordinator.advance()
        #expect(coordinator.positionInSection?.index == 1) // today.heroCard
        #expect(coordinator.positionInSection?.count == 2) // hero + recommended
        walk(coordinator, to: TourStep.finishID)
        #expect(coordinator.positionInSection == nil)
    }

    @Test func positionInSectionCountsTheExercisesSection() {
        let coordinator = makeCoordinator()
        walk(coordinator, to: "bodymap.findStretches")
        #expect(coordinator.positionInSection?.index == 5)
        #expect(coordinator.positionInSection?.count == 5)
    }

    @Test func sectionTabsFollowTabBarOrder() {
        #expect(TourCoordinator().sectionTabs == AppTab.allCases.map(\.rawValue))
    }
}
