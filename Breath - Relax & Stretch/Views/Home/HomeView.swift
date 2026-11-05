import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var router: DeepLinkRouter
    @EnvironmentObject private var pickingSession: ExercisePickingSession
    @EnvironmentObject private var tourCoordinator: TourCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @Query private var exercises: [Exercise]
    @AppStorage("onboardingGoals") private var goalsStr = ""
    @Environment(\.locale) private var locale
    @State private var selectedTab: Int
    @AppStorage(ExercisesMode.storageKey) private var exercisesMode = ExercisesMode.areas.rawValue
    // Tabs are created on first visit and kept alive after, so nav/scroll
    // state survives switching (what TabView used to give us). See `AppTab` for
    // the tab order.
    @State private var visitedTabs: Set<Int>

    init() {
        // Overridable per-launch (-debugInitialTab N) so UI verification can
        // land on any tab directly — the simulator harness can't send taps.
        let initial = UserDefaults.standard.integer(forKey: "debugInitialTab")
        _selectedTab = State(initialValue: initial)
        _visitedTabs = State(initialValue: [initial])
    }

    private var pendingActionBinding: Binding<DeepLinkAction?> {
        Binding(get: { router.pendingAction }, set: { router.pendingAction = $0 })
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                ForEach(visitedTabs.sorted(), id: \.self) { index in
                    tabContent(index)
                        // Navigation titles are UIKit-owned and keep the string they
                        // first resolved; rebuilding the tab when the locale changes
                        // refreshes them. Keyed on the environment locale itself (not
                        // the stored preference) so the rebuild and the new locale land
                        // in the same update. `selectedTab` lives here, so the user stays put.
                        .id(locale.identifier)
                        .opacity(selectedTab == index ? 1 : 0)
                        .allowsHitTesting(selectedTab == index)
                        .accessibilityHidden(selectedTab != index)
                }
            }
            // NOTE: page clearance for the floating bar is applied INSIDE each
            // tab page (.floatingTabBarClearance()) — a safe-area inset added
            // here, outside the pages' NavigationStacks, never reaches their
            // content (the UINavigationController bridge owns those insets).

            CustomTabBar(selectedTab: $selectedTab)
                .tourAnchor("chrome.tabBar")
        }
        .overlayPreferenceValue(TourAnchorPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                TourSpotlightOverlay(anchors: anchors, proxy: proxy)
            }
            .ignoresSafeArea()
        }
        .onChange(of: tourCoordinator.isActive) { _, active in
            // Covers restart() from an already-index-0 coordinator (every
            // fresh app launch, and — critically — the ONLY entry point a
            // returning user has: Profile > Settings > Help > Restart App
            // Tutorial). currentStep?.tabIndex alone wouldn't change value
            // in that case, so this fires on activation itself instead.
            guard active, let tab = tourCoordinator.currentStep?.tabIndex else { return }
            selectedTab = tab
        }
        .onChange(of: tourCoordinator.currentStep?.tabIndex) { _, tab in
            // Drives every subsequent tab switch as the tour advances
            // through sections (step 4 -> Body, step 8 -> Exercises, etc.).
            // Without this, only the very first tab switch (handled above)
            // ever happens and the tour appears frozen from section 2 on.
            if let tab { selectedTab = tab }
        }
        .onChange(of: selectedTab) { _, tab in
            visitedTabs.insert(tab)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
        }
        .onReceive(NotificationCenter.default.publisher(for: .browseExercisesRequested)) { _ in
            // Picking from Today/Routines happens in the Areas view (search +
            // tiles), so land there even if the user last left Body open.
            exercisesMode = ExercisesMode.areas.rawValue
            selectedTab = AppTab.exercises.rawValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .exercisePickingFinished)) { _ in
            // Read lastFinishedOriginTab, NOT lastFinished — the destination
            // screen's own handler consumes lastFinished (clearing it), and
            // NotificationCenter delivery order between sibling .onReceive
            // subscribers on this same notification isn't guaranteed. If we
            // peeked at lastFinished here and the destination's handler ran
            // first, we'd find nil and silently skip the tab switch.
            // lastFinishedOriginTab is never consumed, so it's always safe
            // to read regardless of ordering.
            guard let originTab = pickingSession.lastFinishedOriginTab else { return }
            selectedTab = originTab
        }
        .ignoresSafeArea(.keyboard)
        .sheet(item: pendingActionBinding) { action in
            switch action {
            case .quickSession:
                SessionPlayerView(exercises: quickSessionExercises())
            case .importRoutine(let payload):
                ImportRoutineView(payload: payload) {
                    router.pendingAction = nil
                }
            case .viewChallenge(let payload):
                ChallengeInviteView(
                    payload: payload,
                    onAccept: { router.pendingAction = .quickSession },
                    onDismiss: { router.pendingAction = nil }
                )
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ index: Int) -> some View {
        switch AppTab(rawValue: index) ?? .profile {
        case .today:     TodayView()
        case .exercises: ExercisesTabView()
        case .breathe:   BreathingView()
        case .routines:  RoutineListView()
        case .profile:   ProfileView()
        }
    }

    private func quickSessionExercises() -> [Exercise] {
        let ids = Set(goalsStr.split(separator: ",").map(String.init))
        let recommended = GoalMeta.recommend(from: exercises, activeGoalIDs: ids, limit: 4)
        return recommended.isEmpty ? Array(exercises.prefix(4)) : recommended
    }

}

#Preview {
    let schema = Schema([Exercise.self, Routine.self, Session.self, UserProfile.self])
    let container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    HomeView()
        .modelContainer(container)
        .environmentObject(AuthManager.shared)
        .environmentObject(DeepLinkRouter())
}
