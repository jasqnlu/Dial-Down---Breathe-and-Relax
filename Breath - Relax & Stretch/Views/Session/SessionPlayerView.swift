import SwiftUI
import SwiftData
import Combine
import StoreKit

struct SessionPlayerView: View {
    let exercises: [Exercise]
    var routineID: UUID = UUID()
    var isBorrowedRoutine: Bool = false   // true when playing a forked public routine
    var onComplete: ((Int) -> Void)? = nil
    /// Per-exercise duration overrides from the Routine being played, keyed
    /// by exercise UUID — absent key means "use the exercise's own
    /// durationSeconds." Empty by default for sessions not started from a
    /// saved routine (quick sessions, mini-routines, premade previews).
    var durationOverrides: [UUID: Int] = [:]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("totalSessionsCompleted") private var totalSessionsCompleted = 0
    @AppStorage("calendarSyncEnabled") private var calendarSyncEnabled = false

    @State private var currentIndex = 0
    @State private var secondsRemaining = 0
    @State private var isPaused = false
    @State private var showingSummary = false
    @State private var totalPointsEarned = 0
    @State private var streakOutcome = SessionRecorder.Outcome(streak: 0, streakIncreased: false)
    @State private var sessionStarted = Date()
    @State private var shouldRequestReview = false
    /// Each exercise's own completion fraction, so the session's overall
    /// completionPercent reflects everything done, not just the last exercise.
    @State private var exerciseCompletions: [Double] = []

    // Big countdown numerals aren't inside any fixed-size container here (just
    // a plain VStack with Spacers), so unlike the breathing circle / graph
    // node labels there's no overflow risk in letting these scale.
    @ScaledMetric(relativeTo: .largeTitle) private var exerciseTimerSize: CGFloat = 64
    @ScaledMetric(relativeTo: .largeTitle) private var getReadyCountSize: CGFloat = 72

    // Wall-clock end of the current exercise's countdown. `secondsRemaining` is
    // a display value derived from this each tick, so backgrounding the app
    // (a call, app-switch) doesn't stall the countdown — real elapsed time
    // still counts down, and `scenePhase` catches us up on return.
    @State private var phaseEndDate = Date()
    @State private var pausedRemaining: TimeInterval? = nil

    @AppStorage("autoSkipGetReadyCountdown") private var autoSkipGetReadyCountdown = false
    @State private var isShowingGetReady = false
    @State private var getReadyExerciseName = ""
    @State private var getReadyCount = 3
    @State private var getReadyTask: Task<Void, Never>? = nil

    // Side-switch cue for unilateral (one-side-at-a-time) stretches. The switch
    // point is anchored to `phaseEndDate` (via a lead offset) rather than a
    // fixed wall-clock date, so it survives pause/resume and background
    // catch-up, which already restore `phaseEndDate` as the source of truth.
    @State private var sideSwitchPending = false
    @State private var sideSwitchLeadFromEnd: TimeInterval = 0

    // Haptics
    private let impactLight   = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium  = UIImpactFeedbackGenerator(style: .medium)
    private let notifySuccess = UINotificationFeedbackGenerator()

    @State private var breathTick = 0  // counts seconds to fire cue every 4s
    @State private var cueBadgePulsing = false
    @State private var instructionCueIndex = 0
    @State private var instructionCueTask: Task<Void, Never>? = nil
    @State private var currentBreathPhaseStepIndex = 0
    @State private var breathPhaseSecondsRemaining = 0

    var currentExercise: Exercise? {
        guard currentIndex < exercises.count else { return nil }
        return exercises[currentIndex]
    }

    /// Non-nil only for a Breath exercise with an authored pattern — everything
    /// else (Stretch exercises, Breath exercises with no pattern yet) falls
    /// back to the existing flat instructionCueTask cycling untouched.
    private var activeBreathPattern: [BreathPhaseStep]? {
        guard let pattern = currentExercise?.breathPattern, !pattern.isEmpty else { return nil }
        return pattern
    }

    private var totalSessionSeconds: Int {
        exercises.reduce(0) { total, exercise in
            total + effectiveDuration(for: exercise)
        }
    }

    private var elapsedSessionSeconds: Int {
        guard currentIndex < exercises.count else { return totalSessionSeconds }

        let completed = exercises.prefix(currentIndex).reduce(0) { total, exercise in
            total + effectiveDuration(for: exercise)
        }
        let currentDuration = effectiveDuration(for: exercises[currentIndex])
        let currentElapsed = max(0, min(currentDuration, currentDuration - secondsRemaining))
        return completed + currentElapsed
    }

    /// The exercise coming up after the current one, or nil on the last
    /// exercise — drives the "Up Next" preview card.
    private var nextExercise: Exercise? {
        let nextIndex = currentIndex + 1
        return nextIndex < exercises.count ? exercises[nextIndex] : nil
    }

    private var sessionProgress: Double {
        guard totalSessionSeconds > 0 else { return 0 }
        return min(1, Double(elapsedSessionSeconds) / Double(totalSessionSeconds))
    }

    var body: some View {
        Group {
            if showingSummary {
                SessionSummaryView(
                    pointsEarned: totalPointsEarned,
                    streak: streakOutcome.streak,
                    streakIncreased: streakOutcome.streakIncreased,
                    newlyEarnedBadges: streakOutcome.newlyEarnedBadges
                ) {
                    onComplete?(totalPointsEarned)
                    dismiss()
                }
            } else if exercises.isEmpty {
                ContentUnavailableView {
                    Label("No Exercises", systemImage: "figure.mind.and.body")
                } description: {
                    Text("There are no exercises to play.")
                } actions: {
                    Button {
                        dismiss()
                        NotificationCenter.default.post(name: .browseExercisesRequested, object: nil)
                    } label: {
                        Label("Browse Exercises", systemImage: "list.bullet")
                    }
                    .buttonStyle(LuminaPillButtonStyle())
                }
                .background(Color.luminaSurface.ignoresSafeArea())
                .overlay(alignment: .topLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            } else if isShowingGetReady {
                getReadyView(name: getReadyExerciseName)
            } else if let exercise = currentExercise {
                playerContent(exercise: exercise)
            }
        }
        .onAppear {
            sessionStarted = Date()
            SoundCueService.shared.prepare()
            beginNextExercise()
            impactLight.prepare()
            impactMedium.prepare()
            notifySuccess.prepare()
            // Keep the screen awake — the user is mid-stretch and not touching
            // the screen; auto-lock would freeze the main-runloop timer.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            VoiceCueService.shared.stop()
            getReadyTask?.cancel()
            instructionCueTask?.cancel()
        }
        .task {
            for await _ in Timer.publish(every: 1, on: .main, in: .common).autoconnect().values {
                guard !isPaused, !showingSummary, !isShowingGetReady else { continue }
                let remaining = Int(phaseEndDate.timeIntervalSinceNow.rounded(.up))
                if remaining > 0 {
                    secondsRemaining = remaining
                    checkSideSwitch()
                    updateBreathPhaseStepIfNeeded()
                    breathTick += 1
                    // Legacy fixed-4s metronome; superseded by the authored
                    // phase-transition beeps for pattern exercises, whose
                    // phase boundaries don't align with a 4s grid (e.g.
                    // 4-7-8 Breathing's 19s cycle) — suppress it there.
                    if breathTick % 4 == 0, activeBreathPattern == nil { SoundCueService.shared.play(.tick) }
                } else {
                    SoundCueService.shared.play(.cueBeep)
                    advanceToNext(completion: 1.0)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, !isPaused, !showingSummary, !isShowingGetReady else { return }
            catchUpAfterBackground()
        }
        .onChange(of: showingSummary) { _, showing in
            guard showing, shouldRequestReview else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                requestReview()
                shouldRequestReview = false
            }
        }
    }

    // MARK: - Player UI

    @ViewBuilder
    private func playerContent(exercise: Exercise) -> some View {
        VStack(spacing: 0) {

            // Top bar
            HStack {
                TapAgainToConfirmButton(
                    captionAlignment: .leading,
                    captionAnchor: .leading,
                    captionOffset: CGSize(width: 36, height: 0),
                    action: { dismiss() }
                ) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("sessionCloseButton")
                Spacer()
                Text("\(currentIndex + 1) / \(exercises.count)")
                    .font(.luminaCaption)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
            }
            .padding()

            ProgressView(value: sessionProgress)
                .tint(Color.luminaPrimary)
                .padding(.horizontal)
                .animation(.linear(duration: 1), value: sessionProgress)
                .accessibilityLabel("Session progress")
                .accessibilityValue("\(Int((sessionProgress * 100).rounded())) percent")

            // Everything between the top bar and the transport controls is
            // sized to the space actually available (via GeometryReader)
            // rather than scrolling — the name, instruction/cue text, and
            // countdown timer always keep their full size and stay on
            // screen; the media card / breathing circle is the one thing
            // capped and shrunk to whatever room is left, so a tall device
            // and an SE-class one both show everything at once.
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Text(exercise.name)
                        .font(.luminaDisplay)
                        .foregroundStyle(Color.luminaOnSurface)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal)
                        .padding(.top, 16)

                    Spacer(minLength: 8)

                    // The type ("STRETCH"/"BREATH") and hold/keep-going cue
                    // used to be two separate full-width lines stacked above
                    // the media, eating a chunk of vertical space on every
                    // exercise. For a stretch, they live as a small badge
                    // cluster overlaid on the media's corner; for a breath
                    // exercise there's no media card to anchor a corner to,
                    // so they instead sit right under the inhale/exhale
                    // phase readout below, grouped with the reading they
                    // actually describe.
                    ZStack(alignment: .topTrailing) {
                        if exercise.type != .breath {
                            ExerciseMediaCard(exercise: exercise)
                                .frame(maxHeight: proxy.size.height * 0.6)

                            indicatorCluster(for: exercise)
                                .padding(.top, 4)
                                .padding(.trailing, 20)
                        } else {
                            BreathingCircle(
                                isPaused: isPaused,
                                cycleDuration: breathingCycleDuration(for: exercise),
                                diameter: min(220, proxy.size.height * 0.5)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 4)

                    if let pattern = activeBreathPattern {
                        breathPhaseCue(pattern: pattern)
                        inlineIndicatorCluster(for: exercise)
                            .padding(.top, 6)
                    } else {
                        instructionCue(for: exercise)
                        if exercise.type == .breath {
                            inlineIndicatorCluster(for: exercise)
                                .padding(.top, 6)
                        }
                    }

                    Spacer(minLength: 2)

                    Text(timeString(secondsRemaining))
                        .font(.system(size: exerciseTimerSize, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.luminaOnSurface)
                        .padding(.bottom, 8)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Pinned outside the ScrollView, not part of its scrolling
            // content — always on screen regardless of how tall the
            // exercise's content above it is.
            HStack(spacing: 48) {
                Button {
                    impactLight.impactOccurred()
                    goToPrevious()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Previous exercise")

                Button {
                    impactLight.impactOccurred()
                    if isPaused {
                        phaseEndDate = Date().addingTimeInterval(pausedRemaining ?? 0)
                        pausedRemaining = nil
                    } else {
                        pausedRemaining = max(0, phaseEndDate.timeIntervalSinceNow)
                    }
                    isPaused.toggle()
                } label: {
                    Image(systemName: isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(Color.luminaPrimary)
                        .shadow(color: Color.luminaPrimary.opacity(0.25), radius: 10, y: 5)
                }
                .accessibilityLabel(isPaused ? "Resume session" : "Pause session")

                Button {
                    impactLight.impactOccurred()
                    advanceToNext(completion: skipCompletion())
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Skip exercise")
            }
            .padding(.top, 12)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
            .background(Color.luminaSurface)
        }
        .background(Color.luminaSurface.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            if let nextExercise, secondsRemaining <= Self.upNextLeadSeconds {
                upNextCard(for: nextExercise)
                    .padding(.top, 60)
                    .padding(.trailing, 16)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity)
                            .animation(.easeOut(duration: 0.35)),
                        removal: .opacity.animation(.easeIn(duration: 0.2))
                    ))
            }
        }
        .animation(.easeOut(duration: 0.35), value: secondsRemaining <= Self.upNextLeadSeconds)
    }

    /// Small preview card that slides in once the current exercise's
    /// countdown reaches `upNextLeadSeconds`, showing what's coming next —
    /// mirrors the "Up Next" treatment from Apple Fitness-style workout
    /// players. Tapping it jumps straight to that exercise, same as the
    /// skip button.
    @ViewBuilder
    private func upNextCard(for exercise: Exercise) -> some View {
        Button {
            impactLight.impactOccurred()
            advanceToNext(completion: skipCompletion())
        } label: {
            VStack(spacing: 0) {
                // Breath exercises don't carry a demo video/animation the
                // way stretches do, so ExerciseMediaCard would render
                // nothing here — use the same pose-glyph "profile picture"
                // the rest of the app falls back to instead.
                if exercise.type == .breath {
                    PoseGlyphIcon(
                        exercise: exercise,
                        category: ExerciseCategory.primary(for: exercise.targetBodyParts),
                        size: 96
                    )
                    .frame(width: 96, height: 96)
                } else {
                    ExerciseMediaCard(exercise: exercise)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Text("Up Next")
                    .font(.luminaCaption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.55))
            }
            .frame(width: 96)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Up next: \(exercise.name). Tap to skip ahead.")
    }

    @ViewBuilder
    private func typeBadge(for exercise: Exercise) -> some View {
        Text(exercise.type.rawValue)
            .font(.luminaCaption)
            .fontWeight(.semibold)
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.45), in: Capsule())
            .accessibilityLabel("Exercise type")
            .accessibilityValue(exercise.type.rawValue)
    }

    /// Small badge cluster overlaid on the media card's corner: the exercise
    /// type ("STRETCH") above the hold/keep-going cue. Kept together here
    /// (rather than as two separate full-width lines in the main flow) is
    /// what actually frees up the vertical space the no-scroll layout
    /// depends on. Stretch exercises only — breath uses
    /// `inlineIndicatorCluster` instead, since there's no media corner to
    /// anchor to.
    @ViewBuilder
    private func indicatorCluster(for exercise: Exercise) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            typeBadge(for: exercise)
            cueBadge(for: exercise.cueStyle)
        }
    }

    /// Same two badges as `indicatorCluster`, but side by side and meant to
    /// sit directly under the breath-phase readout (or instruction text for
    /// a pattern-less breath exercise) rather than floating on a media
    /// corner — visually groups "BREATH" + the cue with the phase reading
    /// they actually describe.
    @ViewBuilder
    private func inlineIndicatorCluster(for exercise: Exercise) -> some View {
        HStack(spacing: 8) {
            typeBadge(for: exercise)
            cueBadge(for: exercise.cueStyle)
        }
    }

    @ViewBuilder
    private func cueBadge(for cueStyle: ExerciseCueStyle) -> some View {
        Text(cueStyle == .hold ? "Hold" : "Keep Going")
            .font(.luminaLabel)
            .textCase(.uppercase)
            .foregroundStyle(Color.luminaPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.luminaMintTint, in: Capsule())
            .scaleEffect(cueStyle == .repeatMotion && cueBadgePulsing ? 1.07 : 1.0)
            .opacity(cueStyle == .repeatMotion && cueBadgePulsing ? 0.82 : 1.0)
            .accessibilityLabel("Exercise cue")
            .accessibilityValue(cueStyle == .hold ? "Hold" : "Keep going")
            .onAppear {
                guard cueStyle == .repeatMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    cueBadgePulsing = true
                }
            }
    }

    @ViewBuilder
    private func instructionCue(for exercise: Exercise) -> some View {
        if !exercise.instructions.isEmpty {
            let index = min(instructionCueIndex, exercise.instructions.count - 1)
            Text(exercise.instructions[index])
                .id(index)
                .font(.luminaLabel)
                .foregroundStyle(Color.luminaOnSurface)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 8)
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity)
                        .animation(.easeOut(duration: 0.35)),
                    removal: .opacity
                        .animation(.easeIn(duration: 0.25))
                ))
                .accessibilityLabel("Exercise instruction")
                .accessibilityValue(exercise.instructions[index])
        }
    }

    @ViewBuilder
    private func breathPhaseCue(pattern: [BreathPhaseStep]) -> some View {
        let index = min(currentBreathPhaseStepIndex, pattern.count - 1)
        let phase = pattern[index]

        VStack(spacing: 8) {
            Text("\(phase.label) · \(breathPhaseSecondsRemaining)")
                .id(index)
                .font(.luminaLabel)
                .foregroundStyle(Color.luminaOnSurface)
                .monospacedDigit()
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity)
                        .animation(.easeOut(duration: 0.35)),
                    removal: .opacity
                        .animation(.easeIn(duration: 0.25))
                ))

            HStack(spacing: 6) {
                ForEach(Array(pattern.enumerated()), id: \.offset) { dotIndex, _ in
                    Circle()
                        .fill(dotIndex == index ? Color.luminaPrimary : Color.luminaOutline)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .accessibilityLabel("Breath phase")
        .accessibilityValue("\(phase.label), \(breathPhaseSecondsRemaining) seconds remaining, phase \(index + 1) of \(pattern.count)")
    }

    @ViewBuilder
    private func getReadyView(name: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Get Ready")
                .font(.luminaLabel)
                .textCase(.uppercase)
                .foregroundStyle(Color.luminaOnSurfaceVariant)
            Text(name)
                .font(.luminaHeadline)
                .foregroundStyle(Color.luminaOnSurface)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            // The exercise's pose-glyph "profile picture" — centered as the
            // dominant visual on this screen, same icon the rest of the app
            // uses to represent the exercise when there's no demo media.
            if let exercise = currentExercise {
                PoseGlyphIcon(
                    exercise: exercise,
                    category: ExerciseCategory.primary(for: exercise.targetBodyParts),
                    size: 150
                )
            }
            Text("\(getReadyCount)")
                .font(.system(size: getReadyCountSize, weight: .thin, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.luminaPrimary)
            // Surface the exercise's safety caution here — this is the only
            // screen every session-launch path passes through, so users who
            // start a Quick / For You / guided-program session (skipping the
            // exercise detail page) still see it before the exercise begins.
            if let caution = currentExercise?.caution, !caution.isEmpty {
                CautionCard(text: caution)
                    .padding(.horizontal)
            }
            if let exercise = currentExercise, !exercise.breathPattern.isEmpty, !exercise.instructions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(exercise.instructions, id: \.self) { line in
                        Text(line)
                            .font(.luminaCaption)
                            .foregroundStyle(Color.luminaOnSurfaceVariant)
                    }
                }
                .padding(.horizontal)
            }
            Spacer()
            // Not a button — the whole screen already skips on tap via the
            // .onTapGesture below. This is just the hint telling the user
            // that tapping does something, not a second way to trigger it.
            Text("Tap anywhere to skip")
                .font(.luminaCaption)
                .foregroundStyle(Color.luminaOnSurfaceVariant)
        }
        // Without this, the VStack sizes to its widest child (usually an
        // instruction line or the name text) rather than the full screen —
        // its .background() below then only covers that narrower width,
        // leaving whatever's behind it (a different, grey-ish shade)
        // visible as vertical strips down both edges.
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.luminaSurface.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { skipGetReady() }
        .accessibilityLabel("Get ready for \(name), starting in \(getReadyCount). Tap anywhere to skip.")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Logic

    /// How many seconds are left in the current exercise when the "Up Next"
    /// preview slides in.
    static let upNextLeadSeconds = 5

    /// The exercise's duration after applying this session's routine-level
    /// override, if any — the single point every duration read in this view
    /// goes through, so a customized duration takes effect no matter which
    /// call site reads it.
    private func effectiveDuration(for exercise: Exercise) -> Int {
        durationOverrides[exercise.uuid] ?? exercise.durationSeconds
    }

    private func effectiveDuration(for exercise: Exercise?) -> Int? {
        exercise.map { effectiveDuration(for: $0) }
    }

    private func breathingCycleDuration(for exercise: Exercise) -> Double {
        let duration = effectiveDuration(for: exercise)
        // Breath exercises in the stretch player do not carry a phase model,
        // so tie the visual cadence to the exercise length instead of a fixed
        // 4s pulse. Longer holds breathe more slowly; short drills stay lively.
        return min(8, max(3, Double(duration) / 10))
    }

    private func beginNextExercise() {
        guard let exercise = currentExercise else {
            startExercise()
            return
        }
        // Auto-skip is a convenience preference for the get-ready countdown,
        // but we never skip it for an exercise that carries a safety caution —
        // the get-ready screen is the slot where that caution is surfaced.
        if autoSkipGetReadyCountdown && (exercise.caution ?? "").isEmpty {
            startExercise()
            return
        }
        getReadyExerciseName = exercise.name
        getReadyCount = 3
        isShowingGetReady = true
        runGetReadyCountdown()
    }

    private func runGetReadyCountdown() {
        getReadyTask = Task { @MainActor in
            while isShowingGetReady, getReadyCount > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard isShowingGetReady, !Task.isCancelled else { return }
                getReadyCount -= 1
            }
            guard isShowingGetReady, !Task.isCancelled else { return }
            isShowingGetReady = false
            startExercise()
        }
    }

    private func skipGetReady() {
        guard isShowingGetReady else { return }
        getReadyTask?.cancel()
        isShowingGetReady = false
        startExercise()
    }

    private func skipCompletion() -> Double {
        guard let duration = effectiveDuration(for: currentExercise) else { return 0.5 }
        return GamificationService.skipCompletion(elapsedSeconds: duration - secondsRemaining, durationSeconds: duration)
    }

    private func startExercise() {
        let duration = effectiveDuration(for: currentExercise) ?? 60
        secondsRemaining = duration
        phaseEndDate = Date().addingTimeInterval(TimeInterval(duration))
        pausedRemaining = nil
        isPaused = false
        // Unilateral stretches: cue a side switch at the halfway point, then
        // let the same exercise run the second half before advancing.
        if let exercise = currentExercise, exercise.isBilateral == false {
            sideSwitchPending = true
            sideSwitchLeadFromEnd = TimeInterval(duration) / 2
        } else {
            sideSwitchPending = false
            sideSwitchLeadFromEnd = 0
        }
        if let exercise = currentExercise, activeBreathPattern == nil {
            // Pattern exercises skip this announcement: VoiceCueService.speak
            // interrupts (not queues) in-progress speech, so the phase-0
            // announcement below would immediately cut off the exercise name
            // before it finished. The exercise name is still shown as
            // on-screen text; the phase label is the more actionable cue.
            VoiceCueService.shared.speak(exercise.name)
        }
        SoundCueService.shared.play(.cueBeep)
        instructionCueTask?.cancel()
        instructionCueIndex = 0
        if let pattern = activeBreathPattern {
            // Breath-pattern exercises are driven by the main 1Hz tick's
            // BreathPhaseCycle computation (see the .task loop below), not
            // a sleep-based task — reset to phase 0 and announce it here so
            // the first phase is correct immediately, before the first tick.
            currentBreathPhaseStepIndex = 0
            breathPhaseSecondsRemaining = pattern[0].seconds
            VoiceCueService.shared.speak(pattern[0].label)
        } else if let count = currentExercise?.instructions.count, count > 1 {
            instructionCueTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3.5))
                    guard !Task.isCancelled else { return }
                    // Mirrors the existing countdown `.task` loop's own
                    // `guard !isPaused` skip — while the session is paused,
                    // or during a get-ready transition / the summary screen,
                    // this tick is a no-op rather than advancing/beeping.
                    guard !isPaused, !isShowingGetReady, !showingSummary else { continue }
                    withAnimation(.easeOut(duration: 0.35)) {
                        instructionCueIndex = (instructionCueIndex + 1) % count
                    }
                    SoundCueService.shared.play(.cueBeep)
                }
            }
        }
    }

    /// Fires the "switch sides" haptic + voice cue once, when the current
    /// unilateral exercise passes its halfway point. Anchored to
    /// `phaseEndDate` so pause/resume and background catch-up stay correct.
    private func checkSideSwitch() {
        guard sideSwitchPending else { return }
        let switchDate = phaseEndDate.addingTimeInterval(-sideSwitchLeadFromEnd)
        guard Date() >= switchDate else { return }
        sideSwitchPending = false
        impactMedium.impactOccurred()
        VoiceCueService.shared.speak("Switch sides")
        SoundCueService.shared.play(.cueBeep)
    }

    /// Called every 1Hz tick when a breath pattern is active. Derives the
    /// current phase from elapsed time (not accumulated sleep), so it's
    /// automatically correct after pause/resume or backgrounding — no
    /// special-case handling needed, unlike instructionCueTask's cycling.
    private func updateBreathPhaseStepIfNeeded() {
        guard let pattern = activeBreathPattern, let exercise = currentExercise else { return }
        let totalDuration = effectiveDuration(for: exercise)
        let elapsed = max(0, totalDuration - secondsRemaining)
        guard let resolved = BreathPhaseCycle.resolve(pattern: pattern, elapsedSeconds: elapsed) else { return }

        breathPhaseSecondsRemaining = resolved.secondsRemainingInPhase
        guard resolved.phaseIndex != currentBreathPhaseStepIndex else { return }
        withAnimation(.easeOut(duration: 0.35)) {
            currentBreathPhaseStepIndex = resolved.phaseIndex
        }
        SoundCueService.shared.play(.cueBeep)
        VoiceCueService.shared.speak(pattern[resolved.phaseIndex].label)
    }

    /// Called when the app returns to the foreground. `Timer.publish` doesn't
    /// fire while backgrounded, so real elapsed time may have already blown
    /// past one or more exercises' durations — walk forward through them
    /// (each picking up a fresh full duration) until we land on one that's
    /// still in progress, or the session completes.
    private func catchUpAfterBackground() {
        while !showingSummary {
            let remaining = phaseEndDate.timeIntervalSinceNow
            if remaining > 0 {
                secondsRemaining = Int(remaining.rounded(.up))
                // If the halfway switch point elapsed while backgrounded, fire
                // the cue now (once) so the user isn't left on the wrong side.
                checkSideSwitch()
                break
            }
            advanceToNext(completion: 1.0, showGetReady: false)
        }
    }

    private func advanceToNext(completion: Double, showGetReady: Bool = true) {
        totalPointsEarned += GamificationService.points(for: currentExercise, completion: completion)
        exerciseCompletions.append(completion)

        if currentIndex + 1 < exercises.count {
            impactMedium.impactOccurred()
            SoundCueService.shared.play(.transition)
            currentIndex += 1
            breathTick = 0
            if showGetReady {
                beginNextExercise()
            } else {
                startExercise()
            }
        } else {
            // Session complete
            instructionCueTask?.cancel()
            notifySuccess.notificationOccurred(.success)
            SoundCueService.shared.play(.complete)
            saveSession()
            showingSummary = true
        }
    }

    /// Jumps to the previous exercise (or restarts the current one if
    /// already on the first) — the "up next"-style player's back button.
    /// Unlike `advanceToNext`, no points/completion is recorded for the
    /// exercise being left, and no get-ready countdown is shown: stepping
    /// back is meant to be instant, mirroring the forward skip's immediacy.
    private func goToPrevious() {
        if currentIndex > 0 {
            currentIndex -= 1
        }
        breathTick = 0
        startExercise()
    }

    // MARK: - Persistence

    private func saveSession() {
        let completedAt = Date()
        let bodyPartsCovered = Set(exercises.flatMap { $0.targetBodyParts })
        let difficultiesCovered = Set(exercises.map { $0.difficulty })
        let exerciseNames = exercises.map { $0.name }.joined(separator: ", ")

        totalSessionsCompleted += 1
        streakOutcome = SessionRecorder.record(
            SessionRecorder.Input(
                routineID: routineID,
                startedAt: sessionStarted,
                completedAt: completedAt,
                completionPercent: GamificationService.aggregateCompletion(exerciseCompletions),
                pointsEarned: totalPointsEarned,
                exerciseIDs: exercises.map { $0.uuid },
                bodyPartsCovered: bodyPartsCovered,
                difficultiesCovered: difficultiesCovered,
                isBorrowedRoutine: isBorrowedRoutine,
                calendarTitle: "Stretch Session: \(exerciseNames)",
                healthKitKind: .stretch
            ),
            modelContext: modelContext,
            calendarSyncEnabled: calendarSyncEnabled
        )

        let reviewMilestones: Set<Int> = [10, 25]
        if reviewMilestones.contains(totalSessionsCompleted) {
            shouldRequestReview = true
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Breathing animation

struct BreathingCircle: View {
    let isPaused: Bool
    let cycleDuration: Double
    /// Base diameter of the mid/outer rings — defaults to the original fixed
    /// size, but the session player passes a smaller value on tight screens
    /// so this shrinks along with everything else that needs the room.
    var diameter: CGFloat = 160
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.luminaGradientStart.opacity(0.10))
                .frame(width: diameter, height: diameter)
                .scaleEffect(scale * 1.2)

            Circle()
                .fill(Color.luminaPrimary.opacity(0.15))
                .frame(width: diameter, height: diameter)
                .scaleEffect(scale)

            Circle()
                .fill(Color.luminaPrimary.opacity(0.25))
                .frame(width: diameter * 0.625, height: diameter * 0.625)
        }
        .onAppear { animate() }
        .onChange(of: cycleDuration) { _, _ in
            guard !isPaused else { return }
            scale = 1.0
            animate()
        }
        .onChange(of: isPaused) { _, paused in
            if paused {
                withAnimation(.easeOut(duration: 0.3)) { scale = 1.0 }
            } else {
                animate()
            }
        }
    }

    private func animate() {
        withAnimation(.easeInOut(duration: cycleDuration).repeatForever(autoreverses: true)) {
            scale = 1.35
        }
    }
}

#Preview {
    SessionPlayerView(exercises: [
        Exercise(
            name: "Deep Belly Breath",
            type: .breath,
            targetBodyParts: ["Core", "Chest"],
            durationSeconds: 120,
            difficulty: 1,
            instructions: ["Breathe in slowly.", "Hold.", "Breathe out."]
        )
    ])
    .modelContainer(for: [Session.self, UserProfile.self], inMemory: true)
}
