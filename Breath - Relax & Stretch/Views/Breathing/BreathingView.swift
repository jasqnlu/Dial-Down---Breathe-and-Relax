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
                    VStack(spacing: 28) {
                        patternPicker
                        circleSection
                        controlsSection
                    }
                    .padding(.bottom, 40)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .tourAnchor("breathe.patternPicker")
    }

    @ViewBuilder
    private func patternCard(_ pattern: BreathingPattern) -> some View {
        let isSelected = selectedPattern == pattern

        Button {
            guard !isRunning else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPattern = pattern
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: pattern.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.luminaOnPrimary : Color.luminaPrimary)

                Text(pattern.rawValue)
                    .font(.luminaCaption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.luminaOnPrimary : Color.luminaOnSurface)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 90, height: 72)
            .background(
                RoundedRectangle(cornerRadius: LuminaRadius.control)
                    .fill(isSelected ? Color.luminaPrimary : Color.luminaContainer)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LuminaRadius.control)
                    .strokeBorder(isSelected ? Color.luminaPrimary : Color.clear, lineWidth: 1.5)
            )
            .shadow(color: isSelected ? Color.luminaPrimary.opacity(0.3) : .clear, radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .accessibilityLabel(pattern.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isRunning ? "Stop the session to change patterns" : "")
    }

    // MARK: - Circle section

    private var circleSection: some View {
        VStack(spacing: 20) {
            // Concentric ring circle
            ZStack {
                // Outer ring
                Circle()
                    .fill(circleColor.opacity(0.08))
                    .frame(width: 200, height: 200)
                    .scaleEffect(circleScale * 1.4)
                    .animation(circleAnimation, value: circleScale)

                // Middle ring
                Circle()
                    .fill(circleColor.opacity(0.16))
                    .frame(width: 200, height: 200)
                    .scaleEffect(circleScale * 1.2)
                    .animation(circleAnimation, value: circleScale)

                // Inner filled circle
                Circle()
                    .fill(circleColor.opacity(0.35))
                    .frame(width: 200, height: 200)
                    .scaleEffect(circleScale)
                    .animation(circleAnimation, value: circleScale)

                // Center content
                VStack(spacing: 4) {
                    if isRunning {
                        Text("\(phaseSecondsLeft)")
                            .font(.system(size: 48, weight: .thin, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.3), value: phaseSecondsLeft)
                    } else {
                        Image(systemName: selectedPattern.icon)
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(circleColor)
                    }
                }
            }
            .frame(height: 200 * 1.4 * 1.1)   // reserve space for outermost ring at full scale
            .contentShape(Rectangle())
            .onTapGesture {
                startCirclePreview()
            }
            .animation(.easeInOut(duration: 0.4), value: circleColor)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Plays one round of the selected breathing pattern")

            // Phase label
            if isRunning {
                Text(currentPhase.displayLabel)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(circleColor)
                    .id(currentPhase)          // forces crossfade on phase change
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
                    .animation(.easeInOut(duration: 0.4), value: currentPhase)
            } else {
                Text(selectedPattern.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: selectedPattern)

                if selectedPattern == .custom {
                    Button {
                        showingCustomEditor = true
                    } label: {
                        Label("Edit Pattern", systemImage: "pencil")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.top, 4)
                }
            }

            // Round counter
            if isRunning {
                Text("Round \(round) / \(activeRunPlan.totalRounds)")
                    .font(.luminaSubheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .animation(.easeInOut(duration: 0.3), value: round)
            } else {
                // Round selector when idle
                HStack(spacing: 12) {
                    Text("Rounds:")
                        .font(.luminaSubheadline)
                        .foregroundStyle(.secondary)

                    Stepper("\(totalRounds)", value: $totalRounds, in: 1...20)
                        .labelsHidden()

                    Text("\(totalRounds)")
                        .font(.luminaCardTitle)
                        .monospacedDigit()
                        .frame(minWidth: 24)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
                .background(Color.luminaContainer, in: RoundedRectangle(cornerRadius: LuminaRadius.chip))
            }
        }
        .padding(.horizontal, 20)
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

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 14) {
            // Start / Pause pill button
            Button {
                handleStartPause()
            } label: {
                Label(
                    isRunning ? (isPaused ? "Resume" : "Pause") : "Start",
                    systemImage: isRunning ? (isPaused ? "play.fill" : "pause.fill") : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(LuminaPillButtonStyle())

            // Stop button (shown only while running)
            if isRunning {
                Button(role: .destructive) {
                    stopSession()
                } label: {
                    Text("Stop")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.luminaContainer)
                        .clipShape(Capsule())
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.3), value: isRunning)
    }

    // MARK: - Completion overlay

    private var completionOverlay: some View {
        ZStack {
            Color.luminaSurface.ignoresSafeArea()

            NewBadgesOverlay(newlyEarnedBadges: newlyEarnedBadges)

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)

                VStack(spacing: 8) {
                    Text("Session Complete")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Nice work!")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                // Stats card
                VStack(spacing: 12) {
                    statRow(icon: "arrow.triangle.2.circlepath",
                            color: .blue,
                            label: "Rounds completed",
                            value: "\(activeRunPlan.totalRounds)")

                    Divider()

                    statRow(icon: "star.fill",
                            color: .yellow,
                            label: "Points earned",
                            value: "+\(totalRounds * 5)")

                    Divider()

                    statRow(icon: selectedPattern.icon,
                            color: .accentColor,
                            label: "Pattern",
                            value: selectedPattern.rawValue)
                }
                .padding(20)
                .background(Color.luminaContainer)
                .clipShape(RoundedRectangle(cornerRadius: 18))
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
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 26)
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
