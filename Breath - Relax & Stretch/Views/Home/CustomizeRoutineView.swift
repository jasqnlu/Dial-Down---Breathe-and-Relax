import SwiftUI

/// The shared "preview a set of exercises, adjust duration/order, decide
/// what to do with it" screen. Originally just Today's Customize button,
/// now reused by three flows that all boil down to the same job — review a
/// roadmap of exercises, tweak per-exercise duration and ordering, then
/// commit to an action:
///   - Today: `showsNameField: false`, `showsPinToggle: true`, "Begin" —
///     preview today's session, optionally pin it as the permanent Today
///     routine, then play it.
///   - Create New Routine: `showsNameField: true`, `showsPinToggle: false`,
///     "Save Routine" — name it and save to the Routines list.
///   - Start Mini-Routine: `showsNameField: false`, `showsPinToggle: false`,
///     "Start" — play once, nothing saved.
/// `RoutineBuilderView` remains the separate screen for *editing* an
/// already-saved routine (it also owns the Save/Update toolbar semantics
/// that make sense there but not here).
struct CustomizeRoutineView: View {
    let title: String
    let isPinned: Bool
    /// Shows a routine-name text field at the top, for flows that create a
    /// new saved `Routine` (Create New Routine). Today and Start
    /// Mini-Routine leave this off — neither one names anything.
    var showsNameField: Bool = false
    var initialName: String = ""
    /// Shows the "Keep as my Today routine" pin toggle — only meaningful
    /// for Today's own Customize flow.
    var showsPinToggle: Bool = true
    var primaryActionLabel: String = "Begin"
    var primaryActionIcon: String = "play.fill"
    /// Which tab index the cross-tab "Add Exercises" picking session should
    /// return to — see `ExercisePickingSession.Context.originTab`. Today's
    /// Customize is opened from the Today tab (0); routine-creation flows
    /// pass the tab they were opened from instead.
    var pickingOriginTab: Int = AppTab.today.rawValue
    /// Hides the "Add Exercises" toolbar button — for flows already nested
    /// inside another `ExercisePickingSession` (MiniRoutineReviewView's
    /// "Create New Routine"/"Start Mini-Routine", both presented from a
    /// screen that only exists because a pick just finished). Beginning a
    /// second, cross-tab picking session from inside one of those doesn't
    /// have anywhere consistent to round-trip back to, so it mirrors
    /// RoutineBuilderView's own `allowsCrossTabAddExercise: false` for the
    /// same call sites, pre-unification.
    var showsAddExercisesButton: Bool = true
    let onDone: (_ name: String, _ exercises: [Exercise], _ pinned: Bool, _ durationOverrides: [UUID: Int]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pinnedToggle: Bool
    @State private var currentExercises: [Exercise]
    /// Per-exercise duration overrides, keyed by exercise UUID — seconds.
    /// Absent key means "use the exercise's own durationSeconds." Passed
    /// back through `onDone` so the caller can save it onto the pinned
    /// Today routine / new routine and thread it into the SessionPlayerView
    /// that follows.
    @State private var durationOverrides: [UUID: Int] = [:]
    @State private var routineName: String
    @EnvironmentObject private var pickingSession: ExercisePickingSession

    init(
        title: String, exercises: [Exercise], isPinned: Bool,
        showsNameField: Bool = false, initialName: String = "",
        showsPinToggle: Bool = true,
        primaryActionLabel: String = "Begin", primaryActionIcon: String = "play.fill",
        pickingOriginTab: Int = AppTab.today.rawValue, showsAddExercisesButton: Bool = true,
        onDone: @escaping (_ name: String, _ exercises: [Exercise], _ pinned: Bool, _ durationOverrides: [UUID: Int]) -> Void
    ) {
        self.title = title
        self.isPinned = isPinned
        self.showsNameField = showsNameField
        self.initialName = initialName
        self.showsPinToggle = showsPinToggle
        self.primaryActionLabel = primaryActionLabel
        self.primaryActionIcon = primaryActionIcon
        self.pickingOriginTab = pickingOriginTab
        self.showsAddExercisesButton = showsAddExercisesButton
        self.onDone = onDone
        self._pinnedToggle = State(initialValue: isPinned)
        self._currentExercises = State(initialValue: exercises)
        self._routineName = State(initialValue: initialName)
    }

    private var totalSeconds: Int { currentExercises.reduce(0) { $0 + duration(for: $1) } }
    private var totalMinutes: Int { max(1, Int((Double(totalSeconds) / 60).rounded())) }

    private var canSubmit: Bool {
        !currentExercises.isEmpty
            && (!showsNameField || !routineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// The exercise's duration after applying this session's own override,
    /// if any — mirrors RoutineBuilderView's/SessionPlayerView's identically
    /// named helper.
    private func duration(for exercise: Exercise) -> Int {
        durationOverrides[exercise.uuid] ?? exercise.durationSeconds
    }

    private func adjustDuration(for exercise: Exercise, by delta: Int) {
        let next = max(5, duration(for: exercise) + delta)
        durationOverrides[exercise.uuid] = next
    }

    private func formatted(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        return s == 0 ? "\(m):00" : "\(m):\(String(format: "%02d", s))"
    }

    var body: some View {
        NavigationStack {
            // A List (rather than the old plain ScrollView+VStack) so the
            // exercise section can use List's own native `.onMove`
            // drag-to-reorder — same mechanism RoutineBuilderView's own
            // exercise list already uses. That's a deliberate choice over
            // a hand-built drag gesture: a custom LongPressGesture+
            // DragGesture combo (tried first, to support picking a row up
            // from anywhere rather than just an edge) kept fighting the
            // List's own scroll gesture — `.simultaneousGesture` didn't
            // reliably extend simultaneous recognition to List's internal
            // scroll pan, so swiping over a row to scroll silently stopped
            // working. `.onMove` is Apple's own mechanism, engineered to
            // coexist with scrolling correctly (the same one Reminders/
            // Notes/Mail use) — a swipe scrolls, a brief hold lifts the
            // row, and the lifted row is drawn on top correctly, all for
            // free. The summary/roadmap/pin-toggle block above it rides
            // along as a second, non-reorderable section.
            List {
                // Modern black restyle (seperate-main): summary tiles in
                // the style of the reference's score cards replace the old
                // blurred RoadmapWave carousel — the list below already shows
                // the order, so the top of the screen answers "how long, and
                // what kind" at a glance instead.
                Section {
                    Group {
                        if showsNameField {
                            TextField("Routine name", text: $routineName)
                                .font(.luminaCardTitle)
                                .padding(.horizontal, 16)
                                .frame(height: 52)
                                .background(Color.luminaCardFill, in: RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous))
                        }

                        HStack(spacing: 12) {
                            timeTile
                            exercisesTile
                        }
                        // Both tiles stretch to the taller one's height.
                        .fixedSize(horizontal: false, vertical: true)

                        if showsPinToggle {
                            saveToggleRow
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text("Exercises")
                                .font(.luminaTitle)
                            Spacer()
                            Text("Hold a card to reorder")
                                .font(.luminaCaption)
                                .foregroundStyle(Color.luminaOnSurfaceVariant)
                        }
                        .padding(.top, 6)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section {
                    ForEach(Array(currentExercises.enumerated()), id: \.element.uuid) { index, exercise in
                        exerciseRow(index: index, exercise: exercise)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            // Stable, index-based (not name-based) hook for
                            // UI tests to drag-reorder by — a name-based
                            // query would break once two rows swap places.
                            .accessibilityIdentifier("customizeExerciseRow-\(index)")
                    }
                    .onMove { currentExercises.move(fromOffsets: $0, toOffset: $1) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.luminaSurface)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                // Lives in the toolbar, not the scrolling list — a real
                // XCUITest run caught the earlier in-list placement landing
                // right against the fixed Begin bar below it (same class of
                // bug as the floating-tab-bar/safeAreaInset issue Task 15
                // hit): a tap meant for "Add Exercises" as the list's last
                // row actually triggered Begin instead. The toolbar has no
                // such neighbor and needs no scrolling to reach.
                if showsAddExercisesButton {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            pickingSession.begin(context: .init(
                                title: title,
                                isPinned: pinnedToggle,
                                baseExercises: currentExercises,
                                originTab: pickingOriginTab,
                                editingRoutineID: nil,
                                durationOverrides: [:]
                            ))
                            dismiss()
                            // Same "dismiss + switch tabs" need SessionPlayerView
                            // already has (Views/Session/SessionPlayerView.swift)
                            // — reusing the existing notification rather than
                            // adding a second one.
                            NotificationCenter.default.post(name: .browseExercisesRequested, object: nil)
                        } label: {
                            Label("Add Exercises", systemImage: "plus")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Solid full-width action on a fade to the page color — no
                // material/glass behind it.
                Button {
                    onDone(routineName, currentExercises, pinnedToggle, durationOverrides)
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: primaryActionIcon)
                        Text(primaryActionLabel)
                        if !currentExercises.isEmpty {
                            Text("· \(totalMinutes) min")
                                .foregroundStyle(Color.luminaOnPrimary.opacity(0.55))
                        }
                    }
                    .font(.luminaCardTitle)
                    .foregroundStyle(Color.luminaOnPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.luminaPrimary, in: Capsule())
                    .opacity(canSubmit ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                // Keep the spoken/queryable name to just the action ("Save
                // Routine", "Start") — the minutes suffix is visual only.
                .accessibilityLabel(primaryActionLabel)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 8)
                .background(
                    LinearGradient(colors: [Color.luminaSurface.opacity(0), Color.luminaSurface],
                                   startPoint: .top, endPoint: .init(x: 0.5, y: 0.35))
                        .ignoresSafeArea()
                )
                .disabled(!canSubmit)
            }
        }
    }

    // MARK: - Summary tiles

    /// Total time as a ring gauge (the reference's score dials). The ring
    /// fills toward a 15-minute session; past that it simply reads full.
    private var timeTile: some View {
        let fraction = min(1, Double(totalSeconds) / 900)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Total time")
                .font(.luminaLabel)
                .foregroundStyle(Color.luminaOnSurfaceVariant)
            ZStack {
                Circle()
                    .stroke(Color.luminaContainer, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        AngularGradient(colors: [.pastelMint, .pastelBlue, .pastelLavender], center: .center),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: fraction)
                VStack(spacing: -2) {
                    Text(currentExercises.isEmpty ? "0" : "\(totalMinutes)")
                        .font(.luminaHeadline)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("min")
                        .font(.luminaCaption)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                }
            }
            .frame(width: 96, height: 96)
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.luminaCardFill, in: RoundedRectangle(cornerRadius: LuminaRadius.card - 4, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Total time, \(totalMinutes) minutes")
    }

    /// Exercise count plus a breakdown by type (Breath, Stretch…), each type
    /// marked with a stable pastel dot.
    private var exercisesTile: some View {
        let byType = Dictionary(grouping: currentExercises, by: { $0.type.rawValue })
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Exercises")
                .font(.luminaLabel)
                .foregroundStyle(Color.luminaOnSurfaceVariant)
            Text("\(currentExercises.count)")
                .font(.luminaDisplay)
                .monospacedDigit()
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 6) {
                ForEach(byType.prefix(3), id: \.name) { entry in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.pastel(for: entry.name))
                            .frame(width: 8, height: 8)
                        Text(entry.name)
                            .font(.luminaCaption)
                            .foregroundStyle(Color.luminaOnSurfaceVariant)
                        Spacer(minLength: 4)
                        Text("×\(entry.count)")
                            .font(.luminaCaption.monospacedDigit())
                            .foregroundStyle(Color.luminaOnSurface)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.luminaCardFill, in: RoundedRectangle(cornerRadius: LuminaRadius.card - 4, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var saveToggleRow: some View {
        HStack(spacing: 12) {
            LuminaIconBadge(systemName: "bookmark.fill", tint: .pastelLavender, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Keep as my Today routine")
                    .font(.luminaCardTitle)
                Text(pinnedToggle ? "Opens every day on Today" : "Just for this session")
                    .font(.luminaCaption)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
            }
            Spacer(minLength: 0)
            Toggle("Keep as my Today routine", isOn: $pinnedToggle)
                .labelsHidden()
        }
        .padding(14)
        .background(Color.luminaCardFill, in: RoundedRectangle(cornerRadius: LuminaRadius.card - 4, style: .continuous))
    }

    // MARK: - Exercise card

    private func exerciseRow(index: Int, exercise: Exercise) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // Pose glyph with its order number as a pastel badge.
            let category = ExerciseCategory.primary(for: exercise.targetBodyParts)
            PoseGlyphIcon(exercise: exercise, category: category, size: 52)
                .overlay(alignment: .topLeading) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.onPastel)
                        .frame(width: 22, height: 22)
                        .background(Color.pastels[index % Color.pastels.count], in: Circle())
                        .overlay(Circle().strokeBorder(Color.luminaCardFill, lineWidth: 2.5))
                        .offset(x: -5, y: -5)
                }

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.luminaCardTitle)
                        .foregroundStyle(Color.luminaOnSurface)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(exercise.type.rawValue)
                        .font(.luminaCaption)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                }
                durationStepper(for: exercise)
            }

            Spacer(minLength: 0)

            TapAgainToConfirmButton(
                // Default .top alignment centers the caption over the
                // button; since this remove button sits at the row's
                // trailing edge, the caption's right half clipped past
                // the card/screen edge. .topTrailing pins the caption's
                // trailing corner to the button's, so it grows leftward
                // and stays fully visible — mirrors SessionPlayerView's
                // own .leading override for its leading-edge close button.
                captionAlignment: .topTrailing,
                captionAnchor: .topTrailing,
                action: {
                    let removedID = currentExercises[index].uuid
                    currentExercises.remove(at: index)
                    durationOverrides.removeValue(forKey: removedID)
                }
            ) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Color.luminaContainer, in: Circle())
            }
            .accessibilityLabel("Remove \(exercise.name)")
            .accessibilityIdentifier("removeExercise-\(exercise.uuid)")
            .buttonStyle(.plain)
            .foregroundStyle(Color.luminaOnSurfaceVariant)
        }
        // Without this, the row's own "customizeExerciseRow-N" identifier
        // (used for drag-reorder testing) swallows this remove button's
        // identifier into one merged row-level element — this keeps the
        // remove button (and the duration stepper's +/- buttons)
        // independently reachable, both for VoiceOver and UI tests.
        .accessibilityElement(children: .contain)
        .padding(14)
        .background(Color.luminaCardFill, in: RoundedRectangle(cornerRadius: LuminaRadius.card - 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LuminaRadius.card - 4, style: .continuous)
                .strokeBorder(Color.luminaHairline, lineWidth: 0.5)
        )
    }

    /// Same stepper as RoutineBuilderView's identically named helper — 5s
    /// floor, 5s step — drawn as one compact pill: − time +.
    private func durationStepper(for exercise: Exercise) -> some View {
        HStack(spacing: 0) {
            Button {
                adjustDuration(for: exercise, by: -5)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 32, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(formatted(duration(for: exercise)))
                .font(.system(.footnote, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.luminaOnSurface)
                .frame(minWidth: 40)

            Button {
                adjustDuration(for: exercise, by: 5)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 32, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.luminaOnSurfaceVariant)
        .background(Color.luminaContainer, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.name) duration, \(formatted(duration(for: exercise)))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjustDuration(for: exercise, by: 5)
            case .decrement: adjustDuration(for: exercise, by: -5)
            @unknown default: break
            }
        }
    }
}
