import SwiftUI
import SwiftData
import Combine
import StoreKit
import UIKit

// BreathingPattern and BreathPhase enums live in BreathingModels.swift

// MARK: - BreathingView

struct BreathingView: View {

    // MARK: Session state
    @State private var selectedPattern: BreathingPattern = .box
    @State private var isRunning:        Bool            = false
    @State private var isPaused:         Bool            = false
    @State private var currentPhase:     BreathPhase     = .inhale
    @State private var phaseSecondsLeft: Int             = 0
    @State private var round:            Int             = 0
    @State private var totalRounds:      Int             = 5
    @State private var activeRunPlan:    BreathingRunPlan = .session(selectedRounds: 5)
    @State private var sessionStarted:   Date            = Date()
    @State private var showCompletion:   Bool            = false
    @State private var showingCustomEditor: Bool         = false
    @State private var newlyEarnedBadges: [String]       = []

    // Animation
    @State private var circleScale:  CGFloat = 1.0
    @State private var circleColor:  Color   = BreathPhase.inhale.color

    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Wall-clock end of the current phase (inhale/hold/exhale/hold2).
    // `phaseSecondsLeft` is a display value derived from this each tick, so
    // backgrounding the app doesn't stall the countdown — `scenePhase`
    // catches us up on return.
    @State private var phaseEndDate = Date()
    @State private var pausedRemaining: TimeInterval? = nil

    @AppStorage("totalSessionsCompleted") private var totalSessionsCompleted = 0
    @AppStorage("calendarSyncEnabled") private var calendarSyncEnabled = false
    @State private var shouldRequestReview = false

    // Fixed breathing-session routine ID (not tied to a real Routine record).
    // NOTE: must be a valid hex UUID — the previous literal contained non-hex
    // characters (B,R,E,A,T,H,I,N,G) so UUID(uuidString:) returned nil and the
    // force-unwrap trapped on launch. Kept deterministic, with a safe fallback.
    private let breathingRoutineID = UUID(uuidString: "0B5EA7B0-0000-0000-0000-000000000001") ?? UUID()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Main content
                ScrollView {
                    VStack(spacing: 14) {
                        patternPicker
                        circleSection
                        sessionCard
                    }
                    .padding(.bottom, 24)
                }

                // Completion overlay
                if showCompletion {
                    completionOverlay
                        .zIndex(10)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .background(Color.luminaSurface.ignoresSafeArea())
            .navigationTitle("Breathing")
            // Every other tab root (Body Map, Exercises, Profile) uses .inline;
            // this was the one outlier at .large — aligned per the page-title
            // convention audit (docs/superpowers/plans/2026-07-04-5-page-titles.md).
            .navigationBarTitleDisplayMode(.large)
            .animation(.easeInOut(duration: 0.35), value: showCompletion)
            .floatingTabBarClearance()
        }
        .task {
            for await _ in Timer.publish(every: 1, on: .main, in: .common).autoconnect().values {
                tickTimer()
            }
        }
        // Keep the screen awake only while a session runs — this view is a
        // persistent tab, so appear/disappear would pin the idle timer forever.
        .onChange(of: isRunning) { _, running in
            UIApplication.shared.isIdleTimerDisabled = running
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: showCompletion) { _, showing in
            guard showing, shouldRequestReview else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                requestReview()
                shouldRequestReview = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, isRunning, !isPaused, !showCompletion else { return }
            catchUpAfterBackground()
        }
        .sheet(isPresented: $showingCustomEditor) {
            CustomPatternEditorView()
                .presentationDetents([.medium])
        }
    }

    // MARK: - Pattern picker

    private var patternPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(BreathingPattern.allCases) { pattern in
                    patternCard(pattern)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .tourAnchor("breathe.patternPicker")
    }

    /// Graphite tile with the pattern's pastel icon circle; the selected
    /// tile gets a white ring (same "selected" cue as Today's week strip).
    @ViewBuilder
    private func patternCard(_ pattern: BreathingPattern) -> some View {
        let isSelected = selectedPattern == pattern

        Button {
            guard !isRunning else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPattern = pattern
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                LuminaIconBadge(systemName: pattern.icon, tint: pattern.pastel, size: 34)
                Text(pattern.rawValue)
                    .font(.luminaCaption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.luminaOnSurface : Color.luminaOnSurfaceVariant)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(width: 104, alignment: .leading)
            .background(Color.luminaCardFill, in: RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
                    .strokeBorder(isSelected ? Color.luminaOnSurface : Color.luminaHairline,
                                  lineWidth: isSelected ? 1.5 : 0.5)
            )
            .opacity(isRunning && !isSelected ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .accessibilityLabel(pattern.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isRunning ? "Stop the session to change patterns" : "")
    }

    // MARK: - Circle section

    /// A graphite disc ringed in the current phase's pastel, with a soft
    /// pastel halo that breathes in and out — no saturated fills.
    private var circleSection: some View {
        let base: CGFloat = 148
        return ZStack {
            // Halo
            Circle()
                .fill(circleColor.opacity(0.10))
                .frame(width: base, height: base)
                .scaleEffect(circleScale * 1.32)
                .animation(circleAnimation, value: circleScale)

            // Disc
            Circle()
                .fill(Color.luminaCardFill)
                .overlay(Circle().strokeBorder(circleColor, lineWidth: 3))
                .frame(width: base, height: base)
                .scaleEffect(circleScale)
                .animation(circleAnimation, value: circleScale)

            // Center content
            VStack(spacing: 2) {
                if isRunning {
                    Text("\(phaseSecondsLeft)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.luminaOnSurface)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: phaseSecondsLeft)
                    Text(currentPhase.displayLabel.replacingOccurrences(of: "...", with: ""))
                        .font(.luminaCardTitle)
                        .foregroundStyle(circleColor)
                        .id(currentPhase)          // forces crossfade on phase change
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
                        .animation(.easeInOut(duration: 0.4), value: currentPhase)
                } else {
                    LuminaIconBadge(systemName: selectedPattern.icon,
                                    tint: selectedPattern.pastel, size: 56)
                    Text("Tap to preview")
                        .font(.luminaCaption)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                        .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: base * 1.4 * 1.02)   // room for the disc at full inhale scale
        .contentShape(Rectangle())
        .onTapGesture {
            startCirclePreview()
        }
        .animation(.easeInOut(duration: 0.4), value: circleColor)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Plays one round of the selected breathing pattern")
        .tourAnchor("breathe.previewCircle")
    }

    /// The animation duration mirrors the phase duration so the circle reaches full scale at the end of inhale / fully contracts at end of exhale.
    /// `nil` under Reduce Motion: the circle still resizes to mark each phase
    /// (phase label, color, and countdown text already carry the same
    /// information without motion), it just jumps instead of easing through
    /// a multi-second continuous zoom.
    private var circleAnimation: Animation? {
        guard !reduceMotion else { return nil }
        let duration: Double
        switch currentPhase {
        case .inhale:           duration = Double(selectedPattern.phases.inhale)
        case .hold, .hold2:     duration = 0.3
        case .exhale:           duration = Double(selectedPattern.phases.exhale)
        }
        return .easeInOut(duration: max(0.3, duration))
    }

    // MARK: - Session card
    //
    // Same build as Today's hero card: bold title + subtitle, a content row
    // (here the pattern's timing), then one full-width white button.

    private var sessionMinutes: Int {
        max(1, Int((Double(selectedPattern.roundDuration * totalRounds) / 60).rounded()))
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedPattern.rawValue)
                        .font(.luminaHeadline)
                        .tracking(-0.4)
                    Group {
                        if isRunning {
                            Text("Round \(round) of \(activeRunPlan.totalRounds)")
                                .monospacedDigit()
                                .animation(.easeInOut(duration: 0.3), value: round)
                        } else {
                            Text(selectedPattern.description)
                        }
                    }
                    .font(.luminaSubheadline)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if selectedPattern == .custom && !isRunning {
                    Button {
                        showingCustomEditor = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.luminaOnSurface)
                            .frame(width: 36, height: 36)
                            .background(Color.luminaContainer, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit Pattern")
                }
            }

            phaseChips

            if isRunning {
                HStack(spacing: 10) {
                    Button {
                        stopSession()
                    } label: {
                        Text("Stop")
                            .font(.luminaCardTitle)
                            .foregroundStyle(Color.luminaOnSurface)
                            .frame(width: 96, height: 52)
                            .background(Color.luminaContainer, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    primaryButton
                }
                .transition(.opacity)
            } else {
                HStack(spacing: 10) {
                    roundsStepper
                    primaryButton
                }
                .transition(.opacity)
            }
        }
        .foregroundStyle(Color.luminaOnSurface)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luminaCard(padding: 20)
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.3), value: isRunning)
    }

    /// One chip per non-zero phase. While running, the current phase's chip
    /// fills with its pastel so the card tracks where you are in the round.
    private var phaseChips: some View {
        let p = selectedPattern.phases
        let steps: [(BreathPhase, String, Int)] = [
            (.inhale, "In", p.inhale), (.hold, "Hold", p.hold),
            (.exhale, "Out", p.exhale), (.hold2, "Hold", p.hold2),
        ].filter { $0.2 > 0 }
        return HStack(spacing: 8) {
            ForEach(steps, id: \.0) { phase, label, secs in
                let active = isRunning && currentPhase == phase
                HStack(spacing: 6) {
                    Circle().fill(phase.color).frame(width: 8, height: 8)
                    Text("\(label) \(secs)s")
                        .font(.luminaCaption.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(active ? Color.onPastel : Color.luminaOnSurface)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(active ? phase.color : Color.luminaContainer, in: Capsule())
                .animation(.easeInOut(duration: 0.3), value: active)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Pill "− 5 rounds +" stepper — same shape as Customize's time stepper.
    private var roundsStepper: some View {
        HStack(spacing: 0) {
            Button {
                totalRounds = max(1, totalRounds - 1)
            } label: {
                Image(systemName: "minus").frame(width: 34, height: 52)
            }
            .disabled(totalRounds <= 1)
            .accessibilityLabel("Fewer rounds")

            VStack(spacing: 0) {
                Text("\(totalRounds)")
                    .font(.luminaCardTitle)
                    .monospacedDigit()
                Text("rounds")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
            }
            .frame(minWidth: 36)
            .accessibilityElement(children: .combine)

            Button {
                totalRounds = min(20, totalRounds + 1)
            } label: {
                Image(systemName: "plus").frame(width: 34, height: 52)
            }
            .disabled(totalRounds >= 20)
            .accessibilityLabel("More rounds")
        }
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(Color.luminaOnSurface)
        .buttonStyle(.plain)
        .background(Color.luminaContainer, in: Capsule())
    }

    /// Full-width white Start / Pause / Resume button, like Today's Begin.
    private var primaryButton: some View {
        Button {
            handleStartPause()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isRunning ? (isPaused ? "play.fill" : "pause.fill") : "play.fill")
                Text(isRunning ? (isPaused ? "Resume" : "Pause") : "Start")
                if !isRunning {
                    Text("· \(sessionMinutes) min")
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
        .accessibilityLabel(isRunning ? (isPaused ? "Resume" : "Pause") : "Start")
    }

    // MARK: - Completion overlay

    private var completionOverlay: some View {
        ZStack {
            Color.luminaSurface.ignoresSafeArea()

            NewBadgesOverlay(newlyEarnedBadges: newlyEarnedBadges)

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Color.onPastel)
                    .frame(width: 96, height: 96)
                    .background(Color.pastelMint, in: Circle())

                VStack(spacing: 8) {
                    Text("Session Complete")
                        .font(.luminaDisplay)

                    Text("Nice work!")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                // Stats card
                VStack(spacing: 12) {
                    statRow(icon: "arrow.triangle.2.circlepath",
                            color: .pastelBlue,
                            label: "Rounds completed",
                            value: "\(activeRunPlan.totalRounds)")

                    Divider()

                    statRow(icon: "star.fill",
                            color: .pastelYellow,
                            label: "Points earned",
                            value: "+\(totalRounds * 5)")

                    Divider()

                    statRow(icon: selectedPattern.icon,
                            color: selectedPattern.pastel,
                            label: "Pattern",
                            value: selectedPattern.rawValue)
                }
                .luminaCard(padding: 20)
                .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 12) {
                    // Go again
                    Button {
                        resetSession()
                    } label: {
                        Text("Go Again")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LuminaPillButtonStyle(kind: .ghost))

                    Button {
                        resetSession()
                    } label: {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LuminaPillButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    private func statRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            LuminaIconBadge(systemName: icon, tint: color, size: 30)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.luminaSubheadline)
    }

    // MARK: - Timer logic

    private func tickTimer() {
        guard isRunning, !isPaused, !showCompletion else { return }

        let remaining = Int(phaseEndDate.timeIntervalSinceNow.rounded(.up))
        if remaining > 0 {
            phaseSecondsLeft = remaining
        } else {
            advancePhase()
        }
    }

    /// Called when the app returns to the foreground. `tickTimer()` isn't
    /// driven while backgrounded, so real elapsed time may have already
    /// blown past the current phase (or several) — walk forward through
    /// phases (each picking up a fresh full duration) until we land on one
    /// still in progress, or the session completes.
    private func catchUpAfterBackground() {
        while isRunning, !showCompletion {
            let remaining = phaseEndDate.timeIntervalSinceNow
            if remaining > 0 {
                phaseSecondsLeft = Int(remaining.rounded(.up))
                break
            }
            advancePhase()
        }
    }

    private func advancePhase() {
        let p = selectedPattern.phases

        switch currentPhase {
        case .inhale:
            if p.hold > 0 {
                transition(to: .hold, duration: p.hold)
            } else {
                transition(to: .exhale, duration: p.exhale)
            }

        case .hold:
            transition(to: .exhale, duration: p.exhale)

        case .exhale:
            if p.hold2 > 0 {
                transition(to: .hold2, duration: p.hold2)
            } else {
                // End of round
                finishRound()
            }

        case .hold2:
            finishRound()
        }
    }

    private func finishRound() {
        if round < activeRunPlan.totalRounds {
            round += 1
            transition(to: .inhale, duration: selectedPattern.phases.inhale)
        } else {
            // Session complete
            completeSession()
        }
    }

    private func transition(to phase: BreathPhase, duration: Int) {
        VoiceCueService.shared.speak(phase.displayLabel.replacingOccurrences(of: "...", with: ""))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        phaseEndDate = Date().addingTimeInterval(TimeInterval(duration))
        withAnimation(.easeInOut(duration: 0.4)) {
            currentPhase    = phase
            circleColor     = phase.color
            phaseSecondsLeft = duration
        }

        // Drive the circle scale
        switch phase {
        case .inhale:
            withAnimation(.easeInOut(duration: Double(duration))) {
                circleScale = 1.4
            }
        case .exhale:
            withAnimation(.easeInOut(duration: Double(duration))) {
                circleScale = 1.0
            }
        case .hold, .hold2:
            // Hold at current scale — no change needed
            break
        }
    }

    // MARK: - Session control

    private func handleStartPause() {
        if !isRunning {
            startSession(plan: .session(selectedRounds: totalRounds))
        } else {
            if !isPaused {
                VoiceCueService.shared.stop()
                pausedRemaining = max(0, phaseEndDate.timeIntervalSinceNow)
            } else {
                phaseEndDate = Date().addingTimeInterval(pausedRemaining ?? 0)
                pausedRemaining = nil
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                isPaused.toggle()
            }
        }
    }

    private func startCirclePreview() {
        guard !isRunning else { return }
        startSession(plan: .circlePreview(selectedRounds: totalRounds))
    }

    private func startSession(plan: BreathingRunPlan) {
        let p = selectedPattern.phases
        activeRunPlan    = plan
        sessionStarted   = Date()
        round            = 1
        isPaused         = false
        showCompletion   = false
        pausedRemaining  = nil
        phaseEndDate     = Date().addingTimeInterval(TimeInterval(p.inhale))

        withAnimation(.easeInOut(duration: 0.4)) {
            isRunning        = true
            currentPhase     = .inhale
            circleColor      = BreathPhase.inhale.color
            phaseSecondsLeft = p.inhale
        }

        // Kick off the expand animation
        withAnimation(.easeInOut(duration: Double(p.inhale))) {
            circleScale = 1.4
        }
    }

    private func stopSession() {
        VoiceCueService.shared.stop()
        withAnimation(.easeInOut(duration: 0.35)) {
            isRunning  = false
            isPaused   = false
            circleScale = 1.0
            circleColor = BreathPhase.inhale.color
        }
        round            = 0
        phaseSecondsLeft = 0
        currentPhase     = .inhale
        pausedRemaining  = nil
        activeRunPlan    = .session(selectedRounds: totalRounds)
    }

    private func completeSession() {
        isRunning = false
        isPaused  = false

        withAnimation(.easeInOut(duration: 0.5)) {
            circleScale = 1.0
        }

        guard activeRunPlan.recordsCompletion else {
            resetPreviewSession()
            return
        }

        saveSession(roundsCompleted: activeRunPlan.totalRounds)

        withAnimation(.easeInOut(duration: 0.45).delay(0.1)) {
            showCompletion = true
        }
    }

    private func resetSession() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showCompletion = false
        }
        newlyEarnedBadges = []
        circleScale      = 1.0
        circleColor      = BreathPhase.inhale.color
        currentPhase     = .inhale
        phaseSecondsLeft = 0
        round            = 0
        isRunning        = false
        isPaused         = false
        activeRunPlan    = .session(selectedRounds: totalRounds)
    }

    private func resetPreviewSession() {
        VoiceCueService.shared.stop()
        circleColor      = BreathPhase.inhale.color
        currentPhase     = .inhale
        phaseSecondsLeft = 0
        round            = 0
        isRunning        = false
        isPaused         = false
        pausedRemaining  = nil
        activeRunPlan    = .session(selectedRounds: totalRounds)
    }

    // MARK: - Persistence

    private func saveSession(roundsCompleted: Int) {
        let completedAt  = Date()
        let pointsEarned = roundsCompleted * 5

        totalSessionsCompleted += 1
        let outcome = SessionRecorder.record(
            SessionRecorder.Input(
                routineID: breathingRoutineID,
                startedAt: sessionStarted,
                completedAt: completedAt,
                completionPercent: 1.0,
                pointsEarned: pointsEarned,
                sessionLabel: selectedPattern.rawValue,
                roundsCompleted: roundsCompleted,
                calendarTitle: "\(selectedPattern.rawValue) (\(roundsCompleted) rounds)",
                healthKitKind: .breathing
            ),
            modelContext: modelContext,
            calendarSyncEnabled: calendarSyncEnabled
        )
        newlyEarnedBadges = outcome.newlyEarnedBadges

        let reviewMilestones: Set<Int> = [10, 25]
        if reviewMilestones.contains(totalSessionsCompleted) {
            shouldRequestReview = true
        }
    }
}

// MARK: - Preview

#Preview {
    BreathingView()
        .modelContainer(for: [Session.self, UserProfile.self], inMemory: true)
}
