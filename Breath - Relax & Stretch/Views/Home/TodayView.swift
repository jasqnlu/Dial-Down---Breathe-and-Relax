import SwiftUI
import SwiftData

// MARK: - TodayView
// The landing tab. One job: get the user into today's session in a single
// tap. Momentum is a single glance, not a dashboard: the streak button in
// the header's top-right is the only stat on this screen — the old
// streak/minutes/points tile row and the starter-program promo card were
// both removed as clutter competing with that one job (their content is
// still reachable from Profile → Progress & Charts).
// Visually (seperate-main): a solid graphite hero card with a week strip
// and numbered exercise list, on a near-black page.

struct TodayView: View {
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Query private var exercises: [Exercise]
    @Query private var profiles: [UserProfile]
    @Query private var allRoutines: [Routine]
    @Query private var sessions: [Session]

    /// Only the current account's routines — see `Routine.ownerID`.
    private var routines: [Routine] {
        allRoutines.filter { $0.ownerID == auth.backendID && $0.deletedAt == nil }
    }
    @AppStorage("onboardingGoals") private var goalsStr = ""
    @AppStorage("onboardingAreas") private var onboardingAreas = ""
    @AppStorage("showStreakEmoji") private var showStreakEmoji = true
    /// Not the source of truth for which routine Today shows anymore (that's
    /// `Routine.isPinnedToToday`/`pinnedOrder`, which several routines can
    /// carry at once) — this is purely bookkeeping so Customize's own
    /// "Keep as my Today routine" toggle updates the *same* implicit
    /// routine in place across repeat customizations, instead of inserting
    /// a duplicate every time. Kept under its original key for continuity.
    @AppStorage("pinnedTodayRoutineID") private var customizeManagedRoutineIDString = ""
    /// One-time migration gate: the very first pin model was a single
    /// AppStorage UUID (still read via `customizeManagedRoutineIDString`
    /// above for its own purpose). Runs once to carry any pre-existing pin
    /// forward onto the new `isPinnedToToday`/`pinnedOrder` fields — see
    /// `.onAppear`.
    @AppStorage("didMigratePinnedRoutineToPriorityModel") private var didMigrateToPriorityModel = false
    @State private var showingPinnedOrderEditor = false

    @State private var showingSession = false
    @State private var showingCustomize = false
    @State private var pendingShowSessionAfterCustomize = false
    @State private var selectedPremadeRoutine: PremadeRoutine?
    @State private var brokenStreakValue: Int? = nil
    @EnvironmentObject private var pickingSession: ExercisePickingSession
    @State private var customizeOverride: (title: String, exercises: [Exercise], isPinned: Bool)?
    /// What Customize just returned, when the user adjusted exercises or
    /// durations without pinning them as the permanent Today routine.
    /// Without this, the un-pinned edits had nowhere to live: the session
    /// sheet re-derives `sessionExercises`/`sessionDurationOverrides` from
    /// the pinned routine or time-of-day recommendation, so a one-off
    /// duration tweak was silently discarded and the session started with
    /// the old defaults. Consumed once by the `showingSession` sheet, then
    /// cleared on dismiss so it doesn't stick around for a later, unrelated
    /// "Begin" tap.
    @State private var pendingSessionExercises: [Exercise]?
    @State private var pendingSessionDurationOverrides: [UUID: Int]?

    enum TimeOfDayFocus: Equatable {
        case wakeUp, unwind, none

        var heroTitle: String {
            switch self {
            case .wakeUp: return "Wake Up"
            case .unwind: return "Unwind"
            case .none:   return "Today's session"
            }
        }
    }

    static func timeOfDayFocus(forHour hour: Int) -> TimeOfDayFocus {
        switch hour {
        case 5..<11:         return .wakeUp
        case 20..<24, 0..<5: return .unwind
        default:             return .none
        }
    }

    private var timeOfDayFocus: TimeOfDayFocus {
        Self.timeOfDayFocus(forHour: Calendar.current.component(.hour, from: .now))
    }

    private var profile: UserProfile? { profiles.first }

    private var activeGoalIDs: Set<String> {
        Set(goalsStr.split(separator: ",").map(String.init))
    }

    /// Every routine the user has pinned as a Today launch candidate,
    /// highest-priority first. Several can be pinned at once (via
    /// Customize's toggle, or the Routines list's own pin action);
    /// `pinnedOrder` — user-arranged via the reorder sheet below — breaks
    /// the tie for which one Today actually shows.
    private var pinnedRoutinesInOrder: [Routine] {
        routines.filter(\.isPinnedToToday).sorted { $0.pinnedOrder < $1.pinnedOrder }
    }

    /// The priority value a newly-pinned routine should get — appended to
    /// the end of the current pinned list, never jumping ahead of routines
    /// the user already arranged.
    private func nextPinnedOrder() -> Int {
        (pinnedRoutinesInOrder.map(\.pinnedOrder).max() ?? -1) + 1
    }

    /// The highest-priority pinned routine that still resolves to at least
    /// one real exercise — lower-priority pins, or ones referencing exercises
    /// that no longer exist, are skipped rather than leaving Today empty.
    private var pinnedSessionRoutine: Routine? {
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.uuid, $0) })
        return pinnedRoutinesInOrder.first { routine in
            !routine.exerciseIDs.compactMap({ byID[$0] }).isEmpty
        }
    }

    /// The winning pinned routine's exercises, if any is set and resolves.
    /// Checked before any time-of-day-based recommendation.
    private var pinnedSessionExercises: [Exercise]? {
        guard let routine = pinnedSessionRoutine else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.uuid, $0) })
        let resolved = routine.exerciseIDs.compactMap { byID[$0] }
        return resolved.isEmpty ? nil : resolved
    }

    /// Whether the hero card is currently showing a pinned routine rather
    /// than a time-of-day/goal-based recommendation — drives the "Pinned as
    /// Today" tag next to the hero title.
    private var isPinnedActive: Bool {
        pinnedSessionExercises != nil
    }

    /// The winning pinned routine's per-exercise duration overrides, or
    /// empty when nothing is pinned — threaded into SessionPlayerView so
    /// durations customized (and saved) via Customize actually take effect
    /// during playback, not just in the preview.
    private var sessionDurationOverrides: [UUID: Int] {
        pinnedSessionRoutine?.exerciseDurationOverrides ?? [:]
    }

    /// Today's session: the pinned "Today" routine if one is set, else
    /// goal-based recommendations, falling back to the first few catalog
    /// exercises when no goals were picked during onboarding.
    ///
    /// The pin now applies regardless of time of day — a single "Today"
    /// routine, not one scoped to Wake Up hours.
    private var sessionExercises: [Exercise] {
        if let pinnedSessionExercises {
            return pinnedSessionExercises
        }
        switch timeOfDayFocus {
        case .wakeUp:
            let pool = GoalMeta.recommend(from: exercises, activeGoalIDs: ["wake_up"], limit: 4)
            if !pool.isEmpty { return pool }
        case .unwind:
            let pool = GoalMeta.recommend(from: exercises, activeGoalIDs: ["unwind"], limit: 4)
            if !pool.isEmpty { return pool }
        case .none:
            break
        }
        let recommended = GoalMeta.recommend(from: exercises, activeGoalIDs: activeGoalIDs, limit: 4)
        return recommended.isEmpty ? Array(exercises.prefix(4)) : recommended
    }

    /// Muscle groups under-trained in the last `ActivityInsightsEngine`
    /// window, used to nudge `forYouExercises`' ranking and drive the
    /// imbalance push notification. See `ActivityInsightsEngine`.
    private var neglectedMuscleGroups: [String] {
        let exercisesByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.uuid, $0) })
        let scores = ActivityInsightsEngine.coverageScores(sessions: sessions, exercisesByID: exercisesByID)
        return ActivityInsightsEngine.neglectedGroups(from: scores, threshold: 0.5)
    }

    private var forYouExercises: [Exercise] {
        GoalMeta.recommend(from: exercises, activeGoalIDs: activeGoalIDs, limit: 8, neglectedGroups: neglectedMuscleGroups)
    }

    /// Rides on the existing "Daily Reminders" toggle (`notificationsEnabled`)
    /// rather than a separate opt-in for v1. Re-evaluated on every appearance
    /// of Today so a session recorded elsewhere (or the passage of a day)
    /// updates what's scheduled.
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("reminderHour") private var reminderHour = 8

    private func rescheduleActivityInsightNotifications(for profile: UserProfile) {
        guard notificationsEnabled else {
            NotificationService.shared.cancelInsightNotifications()
            return
        }
        let groups = neglectedMuscleGroups
        Task {
            await NotificationService.shared.scheduleStreakRiskCheck(profile: profile, hour: reminderHour)
            await NotificationService.shared.scheduleImbalanceSummary(neglectedGroups: groups, weekday: 1, hour: reminderHour)
        }
    }

    /// Personalised recommendations for the rotating carousel, keyed off the
    /// focus areas the user picked at signup (`onboardingAreas`).
    private var recommendedItems: [RecommendedExercise] {
        ExerciseCategory.recommendedExercises(
            from: exercises,
            areas: ExerciseCategory.areas(from: onboardingAreas),
            limit: 10
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    greetingHeader
                    heroCard
                    recommendedSection
                    premadeRoutinesSection
                    forYouSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.luminaSurface)
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .floatingTabBarClearance()
        }
        .sheet(isPresented: $showingSession, onDismiss: {
            pendingSessionExercises = nil
            pendingSessionDurationOverrides = nil
        }) {
            SessionPlayerView(
                exercises: pendingSessionExercises ?? sessionExercises,
                durationOverrides: pendingSessionDurationOverrides ?? sessionDurationOverrides
            )
        }
        .sheet(isPresented: $showingCustomize, onDismiss: {
            // Present the session sheet only after Customize has fully
            // dismissed — two sibling .sheet(isPresented:) modifiers can't
            // both be driven true in the same tick, or the second one
            // silently never appears.
            if pendingShowSessionAfterCustomize {
                pendingShowSessionAfterCustomize = false
                showingSession = true
            }
            // Cleared here rather than only in `onDone`, so it is cleared no
            // matter HOW the re-presented Customize sheet was left (Done,
            // swipe-to-dismiss, or the toolbar X). Left set, a stale override
            // would silently win over the fresh `timeOfDayFocus` default the
            // next time Customize is opened — possibly hours or a day later.
            // Safe against the picking flow: its re-population happens in the
            // `.exercisePickingFinished` `.onReceive` below, which fires from
            // the NEXT session's Done, not from this dismissal.
            customizeOverride = nil
        }) {
            CustomizeRoutineView(
                title: customizeOverride?.title ?? timeOfDayFocus.heroTitle,
                exercises: customizeOverride?.exercises ?? sessionExercises,
                isPinned: customizeOverride?.isPinned ?? isPinnedActive,
                onDone: { _, exercises, pinned, durationOverrides in
                    customizeOverride = nil
                    if pinned {
                        if let existingID = UUID(uuidString: customizeManagedRoutineIDString),
                           let existing = routines.first(where: { $0.uuid == existingID }) {
                            // Update the already-pinned routine in place rather
                            // than inserting a duplicate every time the user
                            // re-pins from Customize.
                            existing.exerciseIDs = exercises.map(\.uuid)
                            existing.name = "Today"
                            existing.exerciseDurationOverrides = durationOverrides
                            if !existing.isPinnedToToday {
                                existing.isPinnedToToday = true
                                existing.pinnedOrder = nextPinnedOrder()
                            }
                            existing.markUpdated(in: modelContext)
                        } else {
                            let routine = Routine(
                                name: "Today",
                                exerciseIDs: exercises.map(\.uuid),
                                exerciseDurationOverrides: durationOverrides,
                                isPinnedToToday: true,
                                pinnedOrder: nextPinnedOrder(),
                                ownerID: auth.backendID
                            )
                            routine.insertAndQueueForSync(in: modelContext)
                            customizeManagedRoutineIDString = routine.uuid.uuidString
                        }
                    } else {
                        // Soft-deletes the underlying Routine on unpin, not
                        // just the AppStorage pointer to it — otherwise it
                        // survives as an orphan, and the next re-pin (with the
                        // ID already cleared) would insert a brand-new
                        // duplicate instead of ever finding it again. Soft
                        // (not hard) delete since 2026-09-23: a hard delete
                        // here would never reach the sync engine, so the
                        // routine would silently un-delete itself on other
                        // devices' next pull.
                        if let existingID = UUID(uuidString: customizeManagedRoutineIDString),
                           let existing = routines.first(where: { $0.uuid == existingID }) {
                            existing.markDeleted(in: modelContext)
                        }
                        customizeManagedRoutineIDString = ""
                        // Not pinned, so there's no Routine to persist these
                        // edits onto — carry them forward for just the
                        // session about to start instead of letting the
                        // sheet's default re-derivation discard them.
                        pendingSessionExercises = exercises
                        pendingSessionDurationOverrides = durationOverrides
                    }
                    pendingShowSessionAfterCustomize = true
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .exercisePickingFinished)) { _ in
            // Peek first and check originTab before consuming — a second screen
            // (RoutineBuilderView, via RoutineListView) can also finish a pick
            // now, and this same notification fires at every mounted listener.
            guard let result = pickingSession.lastFinished, result.context.originTab == 0 else { return }
            _ = pickingSession.consumeFinished()
            customizeOverride = (result.context.title, result.merged, result.context.isPinned)
            showingCustomize = true
        }
        .sheet(item: $selectedPremadeRoutine) { routine in
            PremadeRoutineCustomizeSheet(routine: routine, exercises: exercises)
        }
        .alert(
            "Streak Lost",
            isPresented: Binding(
                get: { brokenStreakValue != nil },
                set: { if !$0 { brokenStreakValue = nil } }
            )
        ) {
            if let profile, profile.streakFreezeTokens > 0 {
                Button("Restore Streak (\(profile.streakFreezeTokens) left)") {
                    GamificationService.restoreStreak(for: profile)
                    try? modelContext.save()
                    ProfileSyncService.upload(profile)
                    brokenStreakValue = nil
                }
            }
            if let profile, profile.streakFreezeTokens == 0, GamificationService.canBuySaver(profile) {
                Button("Buy & Restore (\(GamificationService.saverCost) pts)") {
                    if GamificationService.buyAndRestore(for: profile) {
                        try? modelContext.save()
                        ProfileSyncService.upload(profile)
                    }
                    brokenStreakValue = nil
                }
            }
            Button("Dismiss", role: .cancel) {
                if let profile {
                    GamificationService.dismissStreakBreak(for: profile)
                    try? modelContext.save()
                }
                brokenStreakValue = nil
            }
        } message: {
            if let brokenStreakValue {
                Text("Your \(brokenStreakValue)-day streak was lost.")
            }
        }
        .onAppear {
            // One-time migration: the pin used to be scoped to Wake Up hours
            // only, under this key. Carry an existing pin forward under the
            // new key rather than silently dropping it for upgrading users.
            // The old key is left in place (unused) rather than deleted —
            // there's no reader left for it either way.
            if customizeManagedRoutineIDString.isEmpty,
               let legacy = UserDefaults.standard.string(forKey: "pinnedWakeUpRoutineID"),
               !legacy.isEmpty {
                customizeManagedRoutineIDString = legacy
            }
            // Second one-time migration: carry the single old-model pin
            // forward onto the new isPinnedToToday/pinnedOrder fields, which
            // are what session selection actually reads now. Only needs to
            // run once — later pins (from here or the Routines list) set
            // these fields directly.
            if !didMigrateToPriorityModel {
                if let pinnedID = UUID(uuidString: customizeManagedRoutineIDString),
                   let routine = routines.first(where: { $0.uuid == pinnedID }),
                   !routine.isPinnedToToday {
                    routine.isPinnedToToday = true
                    routine.pinnedOrder = 0
                    routine.markUpdated(in: modelContext)
                }
                didMigrateToPriorityModel = true
            }
            if let profile {
                let broken = GamificationService.checkForBrokenStreak(for: profile)
                brokenStreakValue = broken
                if broken != nil {
                    try? modelContext.save()
                }
                rescheduleActivityInsightNotifications(for: profile)
            }
        }
    }

    // MARK: - Greeting

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Time to unwind"
        }
    }

    private var greetingHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(auth.greetingName.isEmpty
                     ? greeting
                     : "\(greeting), \(auth.greetingName)")
                    .font(.luminaDisplay)
                    .tracking(-0.6)
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.luminaSubheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Only worth showing once there's an actual order to arrange —
            // a single pin (or none) has nothing to reorder, and the icon
            // would just read as clutter next to the streak badge.
            if pinnedRoutinesInOrder.count > 1 {
                pinnedOrderButton
            }

            streakButton
        }
        .sheet(isPresented: $showingPinnedOrderEditor) {
            PinnedRoutineOrderView(routines: pinnedRoutinesInOrder) {
                for routine in pinnedRoutinesInOrder { routine.markUpdated(in: modelContext) }
            }
        }
    }

    /// Opens the reorder sheet for pinned routines — the "which one wins
    /// when you open the app" priority list. Lives next to the streak
    /// badge since that's the only existing top-of-screen chrome; there's
    /// no toolbar here to hang it on (the nav bar is hidden).
    private var pinnedOrderButton: some View {
        Button {
            showingPinnedOrderEditor = true
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.luminaOnSurfaceVariant)
                .frame(width: 34, height: 34)
                .background(Color.luminaContainer, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Arrange pinned routine order")
    }

    /// The only stat on this screen — always visible (even at a 0 streak,
    /// now that the removed stat-tile row isn't showing it as a fallback)
    /// and a real NavigationLink into Progress & Charts, not just a
    /// decorative badge. At 0 the flame+count reads as a small failure
    /// badge, so instead of swapping it out at 0 the same flame+count stays
    /// in place at every streak value — only the flame's own color changes,
    /// unlit (grey) at 0 and lit (orange) once today counts toward a
    /// streak, so the badge never reads as a bare failure state.
    private var streakButton: some View {
        let streak = profile?.streak ?? 0
        let isLit = streak > 0
        return NavigationLink(destination: ProgressChartsView()) {
            HStack(spacing: 5) {
                if showStreakEmoji {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isLit ? Color.luminaFlameLit : Color.luminaOnSurfaceVariant.opacity(0.5))
                }
                Text("\(streak)")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(isLit ? Color.luminaOnSurface : Color.luminaOnSurfaceVariant)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.luminaContainer, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLit ? "\(streak) day streak, view progress" : "No streak yet today, view progress")
    }

    // MARK: - Hero: today's session

    private var heroCard: some View {
        // Reads sessionDurationOverrides (a customized/lowered duration set
        // via Customize) rather than each exercise's raw durationSeconds —
        // otherwise this total silently drifted from what the session
        // actually plays at, the same class of bug the SessionPlayerView
        // timer fix addressed.
        let overrides = sessionDurationOverrides
        let totalSecs = sessionExercises.reduce(0) { $0 + (overrides[$1.uuid] ?? $1.durationSeconds) }
        // Round rather than truncate, so e.g. a 90s session reads "2m" instead
        // of always flooring to "1m" regardless of how much over a minute it is.
        let mins = totalSecs > 0 ? max(1, Int((Double(totalSecs) / 60).rounded())) : 0

        // Modern black restyle (seperate-main): a solid graphite card — no
        // Liquid Glass, blur or lens effects. Modeled on the reference
        // dashboards: a bold title row, a week strip (the Insights calendar),
        // a numbered exercise list (the grouped rows with pastel circles),
        // and one solid full-width Begin button.
        let shown = Array(sessionExercises.prefix(4))
        let hidden = sessionExercises.count - shown.count

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(timeOfDayFocus.heroTitle)
                        .font(.luminaHeadline)
                        .tracking(-0.4)
                    Text("\(sessionExercises.count) exercises · \(mins) min")
                        .font(.luminaSubheadline)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                }
                Spacer(minLength: 0)
                if isPinnedActive {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.onPastel)
                        .frame(width: 36, height: 36)
                        .background(Color.pastelLavender, in: Circle())
                        .accessibilityLabel("Pinned as Today")
                }
                Button {
                    showingCustomize = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.luminaOnSurface)
                        .frame(width: 36, height: 36)
                        .background(Color.luminaContainer, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Customize")
            }

            weekStrip

            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.uuid) { index, exercise in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.luminaOutline)
                            .frame(height: 0.5)
                            .padding(.leading, 46)
                    }
                    NumberedExerciseRow(index: index, exercise: exercise,
                                        seconds: overrides[exercise.uuid] ?? exercise.durationSeconds)
                }
                if hidden > 0 {
                    Text("+\(hidden) more")
                        .font(.luminaCaption)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 46)
                        .padding(.top, 8)
                }
            }

            Button {
                showingSession = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Begin")
                    if mins > 0 {
                        Text("· \(mins) min")
                            .foregroundStyle(Color.luminaOnPrimary.opacity(0.55))
                    }
                }
                .font(.luminaCardTitle)
                .foregroundStyle(Color.luminaOnPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.luminaPrimary, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Begin today's session: \(sessionExercises.count) exercises, \(mins) minutes")
        }
        .foregroundStyle(Color.luminaOnSurface)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.luminaCardFill, in: RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous)
                .strokeBorder(Color.luminaHairline, lineWidth: 0.5)
        )
        .tourAnchor("today.heroCard")
    }

    // MARK: - Hero pieces

    static func shortDuration(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : (seconds % 60 == 0 ? "\(seconds / 60)m" : "\(seconds / 60)m \(seconds % 60)s")
    }

    /// This week at a glance, like the reference's calendar: a filled
    /// pastel circle with a check on days with a completed session, a white
    /// ring on today, dim circles otherwise.
    private var weekStrip: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let doneDays = Set(sessions.compactMap { $0.completedAt == nil ? nil : cal.startOfDay(for: $0.startedAt) })

        return HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                let isToday = day == today
                let done = doneDays.contains(day)
                VStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 11, weight: isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? Color.luminaOnSurface : Color.luminaOnSurfaceVariant)
                    ZStack {
                        Circle()
                            .fill(done ? Color.pastels[i % Color.pastels.count] : Color.luminaContainer)
                        if done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.onPastel)
                        } else {
                            Text(day.formatted(.dateTime.day()))
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(isToday ? Color.luminaOnSurface : Color.luminaOnSurfaceVariant)
                        }
                    }
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(Color.luminaOnSurface, lineWidth: isToday ? 1.5 : 0).padding(-3))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide))): \(done ? "session done" : "no session")")
            }
        }
    }

    // MARK: - Section headers
    //
    // Title-case, bold, primary-colored — the "Calendar" / "Monthly Stats" /
    // "My Goal" headers of the reference designs. The hero still leads
    // because it is a filled card; these sit on the bare surface.
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.luminaTitle)
            .foregroundStyle(Color.luminaOnSurface)
    }

    // MARK: - Recommended (rotating carousel)

    @ViewBuilder
    private var recommendedSection: some View {
        let items = recommendedItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Recommended for You")
                RecommendedCarousel(items: items)
            }
            .tourAnchor("today.recommended")
        }
    }

    // MARK: - Premade Routines

    @ViewBuilder
    private var premadeRoutinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Premade Routines")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(PremadeRoutine.all) { routine in
                        let meta = premadeMeta(for: routine)
                        Button {
                            selectedPremadeRoutine = routine
                        } label: {
                            PremadeRoutineCard(routine: routine, meta: meta)
                        }
                        .buttonStyle(.plain)
                        .disabled(meta == nil)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// The raw (count, minutes) behind the card's meta line, or nil if the
    /// routine currently resolves to zero exercises. Kept as data rather
    /// than a formatted String so the call site can render a `Text` literal
    /// that participates in localization — see PremadeRoutineCard.
    private func premadeMeta(for routine: PremadeRoutine) -> (count: Int, minutes: Int)? {
        let resolved = routine.resolvedExercises(in: exercises)
        guard !resolved.isEmpty else { return nil }
        let totalSecs = resolved.reduce(0) { $0 + $1.durationSeconds }
        let mins = max(1, Int((Double(totalSecs) / 60).rounded()))
        return (resolved.count, mins)
    }

    // MARK: - For You

    @ViewBuilder
    private var forYouSection: some View {
        if !forYouExercises.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("For You")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(forYouExercises) { exercise in
                            NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                                ForYouCard(exercise: exercise)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

#Preview {
    let schema = Schema([Exercise.self, Routine.self, Session.self, UserProfile.self])
    let container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    TodayView()
        .modelContainer(container)
        .environmentObject(AuthManager.shared)
}

// MARK: - Numbered exercise row

/// One exercise in a numbered list: pastel number circle, name, type, and
/// duration on the right. Today's hero card and Review Picks share it.
struct NumberedExerciseRow: View {
    let index: Int
    let exercise: Exercise
    let seconds: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.onPastel)
                .frame(width: 34, height: 34)
                .background(Color.pastels[index % Color.pastels.count], in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(exercise.name)
                    .font(.luminaSubheadline.weight(.semibold))
                    .lineLimit(1)
                Text(exercise.type.rawValue)
                    .font(.luminaCaption)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
            }
            Spacer(minLength: 8)
            Text(TodayView.shortDuration(seconds))
                .font(.system(.footnote, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.luminaOnSurfaceVariant)
        }
        .padding(.vertical, 8)
    }
}
