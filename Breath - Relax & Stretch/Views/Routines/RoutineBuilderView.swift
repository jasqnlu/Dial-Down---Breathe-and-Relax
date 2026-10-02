import SwiftUI
import SwiftData
import os

struct RoutineBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var pickingSession: ExercisePickingSession
    @EnvironmentObject private var auth: AuthManager

    @Query private var exercises: [Exercise]

    var routineToEdit: Routine? = nil
    /// Exercise IDs to fold in on appear — e.g. a set just picked in the
    /// Exercises tab's standalone picking mode (see
    /// `MiniRoutineReviewView`). Appended after `routineToEdit`'s existing
    /// exercises (or seeded fresh when creating), de-duped via
    /// `RoutineIDMerge` so a pick that's already in the routine isn't
    /// doubled.
    var initialExerciseIDs: [UUID] = []
    /// Suggested name to pre-fill when creating a brand-new routine from a
    /// template (e.g. a tapped PremadeRoutine card) — nil for the normal
    /// create/edit flows, which leave the name field blank or pull it from
    /// `routineToEdit`. Never applied when `routineToEdit` is set — editing
    /// an existing routine always keeps its own name.
    var initialName: String? = nil
    /// Which HomeView tab index to return to after a cross-tab "Add
    /// Exercise" round trip — must match wherever THIS view was actually
    /// presented from. Defaults to 4 (Routines), the common case
    /// (RoutineListView, PremadeRoutinesView); callers presenting this view
    /// from a different tab (e.g. TodayView's premade-routine sheet, tab 0)
    /// must override it, or the user gets returned to the wrong tab.
    var pickingOriginTab: Int = 4
    /// Whether "Add Exercise" should be offered at all. False for
    /// call sites where the cross-tab picking flow would conflict with an
    /// already-in-progress `ExercisePickingSession` this view is nested
    /// inside (MiniRoutineReviewView's two RoutineBuilderView sheets) —
    /// starting a second cross-tab session there would silently discard
    /// the outer review flow's own picks and leave two sheets fighting
    /// over one dismiss path.
    var allowsCrossTabAddExercise: Bool = true
    /// Called right after a successful save (create or update), before
    /// `dismiss()`. Distinct from dismissal itself so a caller driving this
    /// view from a review flow (`MiniRoutineReviewView`) can tell "saved"
    /// apart from "cancelled" — the sheet's own `onDismiss` fires either way
    /// and can't make that distinction.
    var onSaved: (() -> Void)? = nil
    /// Exact form state to restore after a cross-tab "Add Exercise" round
    /// trip — a hard replace, not a merge. Set only by RoutineListView's
    /// re-presentation after `.exercisePickingFinished`; nil for every
    /// other entry into this view. When set, takes priority over
    /// `routineToEdit`/`initialExerciseIDs`/`initialName` entirely — see
    /// this task's design note for why a merge here would be wrong.
    var restoredState: (name: String, exerciseIDs: [UUID], durationOverrides: [UUID: Int])? = nil

    @State private var routineName = ""
    @State private var selectedIDs: [UUID] = []
    /// Per-exercise duration overrides, keyed by exercise UUID — seconds.
    /// Absent key means "use the exercise's own durationSeconds." Persisted
    /// onto `Routine.exerciseDurationOverrides` on save.
    @State private var durationOverrides: [UUID: Int] = [:]
    /// Guards the "creating new" onAppear branch so initialExerciseIDs/
    /// initialName are only seeded once, even if onAppear re-fires for
    /// this same sheet instance. (A cross-tab exercise pick re-presents via
    /// the restoredState branch instead, which short-circuits before this
    /// branch runs — restoredState is checked first in onAppear.)
    @State private var didApplySeed = false

    private var isEditing: Bool { routineToEdit != nil }

    private var selectedExercises: [Exercise] {
        selectedIDs.compactMap { id in exercises.first { $0.uuid == id } }
    }

    private var totalDuration: Int {
        selectedExercises.reduce(0) { $0 + duration(for: $1) }
    }

    /// The exercise's duration after applying this form's own override, if
    /// any — the single point every duration read in this view goes
    /// through, mirroring SessionPlayerView's `effectiveDuration(for:)`.
    private func duration(for exercise: Exercise) -> Int {
        durationOverrides[exercise.uuid] ?? exercise.durationSeconds
    }

    private func adjustDuration(for exercise: Exercise, by delta: Int) {
        let next = max(5, duration(for: exercise) + delta)
        durationOverrides[exercise.uuid] = next
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        return s == 0 ? "\(m):00" : "\(m):\(String(format: "%02d", s))"
    }

    var body: some View {
        NavigationStack {
            // Form's own native `.onMove` drag-to-reorder — see
            // CustomizeRoutineView's matching comment for why this uses
            // List's/Form's built-in mechanism rather than a hand-built
            // gesture: a custom drag kept fighting the scroll gesture,
            // silently breaking swipe-to-scroll over the rows.
            Form {
                Section {
                    TextField("e.g. Morning Wake-Up", text: $routineName)
                        .font(.luminaBody)
                } header: {
                    Text("Routine Name")
                        .font(.luminaLabel)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                }

                Section {
                    ForEach(selectedIDs.indices, id: \.self) { index in
                        if let exercise = exercises.first(where: { $0.uuid == selectedIDs[index] }) {
                            exerciseRow(index: index, exercise: exercise)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .onMove { selectedIDs.move(fromOffsets: $0, toOffset: $1) }

                    if allowsCrossTabAddExercise {
                        Button {
                            pickingSession.begin(context: .init(
                                title: routineName,
                                isPinned: false,
                                baseExercises: selectedExercises,
                                originTab: pickingOriginTab,
                                editingRoutineID: routineToEdit?.uuid,
                                durationOverrides: durationOverrides
                            ))
                            dismiss()
                            // Same "dismiss + switch to Exercises tab" need
                            // CustomizeRoutineView's own Add Exercises button
                            // has — reusing the existing notification rather
                            // than adding a second one.
                            NotificationCenter.default.post(name: .browseExercisesRequested, object: nil)
                        } label: {
                            Label("Add Exercise", systemImage: "plus.circle")
                                .font(.luminaBody)
                                .foregroundStyle(Color.luminaPrimary)
                        }
                    }
                } header: {
                    HStack {
                        Text("Exercises")
                            .font(.luminaLabel)
                            .foregroundStyle(Color.luminaOnSurfaceVariant)
                        Spacer()
                        if !selectedIDs.isEmpty {
                            Text(totalDuration < 60 ? "\(totalDuration)s total" : "\(totalDuration / 60)m total")
                                .font(.luminaCaption)
                                .foregroundStyle(Color.luminaOnSurfaceVariant)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.luminaSurface)
            .listRowBackground(Color.luminaCardFill)
            .navigationTitle(isEditing ? "Edit Routine" : "New Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Update" : "Save") { saveRoutine() }
                        .disabled(routineName.isEmpty || selectedIDs.isEmpty)
                }
            }
            .onAppear {
                if let restoredState {
                    routineName       = restoredState.name
                    selectedIDs       = restoredState.exerciseIDs
                    durationOverrides = restoredState.durationOverrides
                } else if let r = routineToEdit {
                    routineName  = r.name
                    selectedIDs  = RoutineIDMerge.appending(initialExerciseIDs, to: r.exerciseIDs)
                    durationOverrides = r.exerciseDurationOverrides
                } else if !didApplySeed && (!initialExerciseIDs.isEmpty || initialName != nil) {
                    didApplySeed = true
                    selectedIDs = RoutineIDMerge.appending(initialExerciseIDs, to: selectedIDs)
                    if let initialName {
                        routineName = initialName
                    }
                }
            }
        }
    }

    private func saveRoutine() {
        if let r = routineToEdit {
            r.name        = routineName
            r.exerciseIDs = selectedIDs
            r.exerciseDurationOverrides = durationOverrides
            r.markUpdated(in: modelContext)
        } else {
            let routine = Routine(
                name: routineName,
                exerciseIDs: selectedIDs,
                exerciseDurationOverrides: durationOverrides,
                ownerID: auth.backendID
            )
            routine.insertAndQueueForSync(in: modelContext)

            if let profile = (try? modelContext.fetch(FetchDescriptor<UserProfile>()))?.first {
                GamificationService.awardBadge("Routine Builder", to: profile)
            }
        }

        do {
            try modelContext.save()
            onSaved?()
        } catch {
            Logger(subsystem: "com.jasonlu.breath", category: "routineBuilder").warning("Save failed: \(error)")
        }

        dismiss()
    }

    /// Same row look as CustomizeRoutineView's exerciseRow (numbered badge +
    /// PoseGlyphIcon + card) so the two "edit a routine's exercises" screens
    /// read as one design, not two — plus the stepper and remove button
    /// this screen already had.
    private func exerciseRow(index: Int, exercise: Exercise) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.luminaOnSurfaceVariant)
                .frame(width: 22, height: 22)
                .background(Color.luminaContainer, in: Circle())

            let category = ExerciseCategory.primary(for: exercise.targetBodyParts)
            PoseGlyphIcon(exercise: exercise, category: category, size: 46)

            Text(exercise.name)
                .font(.luminaCardTitle)
                .foregroundStyle(Color.luminaOnSurface)
                .lineLimit(1)

            Spacer(minLength: 8)

            durationStepper(for: exercise)

            TapAgainToConfirmButton(
                // Same trailing-edge clipping fix as CustomizeRoutineView's
                // identical remove button — see its comment for why.
                captionAlignment: .topTrailing,
                captionAnchor: .topTrailing,
                action: {
                    let removedID = selectedIDs[index]
                    selectedIDs.remove(at: index)
                    durationOverrides.removeValue(forKey: removedID)
                }
            ) {
                Image(systemName: "minus.circle.fill")
            }
            .accessibilityLabel("Remove \(exercise.name)")
            .accessibilityIdentifier("removeExercise-\(exercise.uuid)")
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        // Keeps the remove button (and the duration stepper's +/- buttons)
        // independently reachable rather than getting merged into one
        // row-level accessibility element — see the matching comment in
        // CustomizeRoutineView.exerciseRow.
        .accessibilityElement(children: .contain)
        .luminaCard(padding: 12)
    }

    private func durationStepper(for exercise: Exercise) -> some View {
        HStack(spacing: 6) {
            // Outline icon here (vs. the row's own filled "minus.circle.fill"
            // remove button) so the two destructive-looking minus icons in
            // the same row read as visually distinct actions.
            Button {
                adjustDuration(for: exercise, by: -5)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.luminaPrimary)

            Text(formattedDuration(duration(for: exercise)))
                .font(.luminaCaption)
                .monospacedDigit()
                .foregroundStyle(Color.luminaOnSurfaceVariant)
                .frame(minWidth: 40)

            Button {
                adjustDuration(for: exercise, by: 5)
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.luminaPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(exercise.name) duration, \(formattedDuration(duration(for: exercise)))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjustDuration(for: exercise, by: 5)
            case .decrement: adjustDuration(for: exercise, by: -5)
            @unknown default: break
            }
        }
    }
}
