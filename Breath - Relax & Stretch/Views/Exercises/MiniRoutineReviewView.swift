import SwiftUI
import SwiftData

/// Presented when "Continue" is tapped on the `PickingBar` for a standalone
/// (no-Customize-context) picking session — see `ExercisePickingSession
/// .begin()`. Shows the picks as a numbered roadmap, same look as
/// `CustomizeRoutineView`'s preview, then offers three terminal actions
/// instead of Customize's single "Begin".
struct MiniRoutineReviewView: View {
    let pickedExercises: [Exercise]
    /// Which HomeView tab this picking session started from — threaded into
    /// the Customize sheets below so their own "Add Exercises" cross-tab
    /// round trip (see `ExercisePickingSession.Context.originTab`) returns
    /// to the tab that actually opened this screen, not always Exercises.
    /// Defaults to 2 (Exercises) since that tab's own "Select" button was
    /// this view's original and, for a while, only entry point.
    var originTab: Int = 2
    /// Called once one of the three destinations actually completes (a
    /// routine was saved, or the mini-routine session was dismissed) so the
    /// caller can clear the picking session. Not called if the user just
    /// backs out without finishing any of them.
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthManager
    // "Create New Routine" and "Start Mini-Routine" both route through the
    // same customize-and-reorder screen Today's Customize button opens
    // (CustomizeRoutineView) instead of each having their own separate
    // review UI — see that view's doc comment for the shared-screen design.
    @State private var showingCustomizeForNewRoutine = false
    @State private var showingCustomizeForMiniSession = false
    @State private var showingRoutineChooser = false
    @State private var showingMiniSession = false
    /// What Customize returned for "Start Mini-Routine" — stashed here
    /// because the mini-session sheet can only be presented after
    /// Customize's own sheet has fully dismissed (two sibling
    /// `.sheet(isPresented:)`s can't both flip true in the same tick; see
    /// TodayView's identical `pendingShowSessionAfterCustomize` pattern).
    @State private var pendingMiniSessionExercises: [Exercise] = []
    @State private var pendingMiniSessionDurationOverrides: [UUID: Int] = [:]

    private var totalSeconds: Int { pickedExercises.reduce(0) { $0 + $1.durationSeconds } }
    private var totalMinutes: Int { max(1, Int((Double(totalSeconds) / 60).rounded())) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(pickedExercises.count) EXERCISE\(pickedExercises.count == 1 ? "" : "S") · \(totalMinutes) MIN")
                        .font(.luminaCaption)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)

                    RoadmapWave(exercises: pickedExercises, numbered: true)

                    VStack(spacing: 10) {
                        destinationRow(
                            title: "Create New Routine",
                            subtitle: "Name it and save these as a routine",
                            systemImage: "plus.circle.fill"
                        ) { showingCustomizeForNewRoutine = true }

                        destinationRow(
                            title: "Add to Existing Routine",
                            subtitle: "Append these to one you already have",
                            systemImage: "text.badge.plus"
                        ) { showingRoutineChooser = true }

                        destinationRow(
                            title: "Start Mini-Routine",
                            subtitle: "Play these now — nothing is saved",
                            systemImage: "play.fill"
                        ) { showingCustomizeForMiniSession = true }
                    }
                }
                .padding()
            }
            .background(Color.luminaSurface)
            .navigationTitle("Review Picks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .sheet(isPresented: $showingCustomizeForNewRoutine) {
                CustomizeRoutineView(
                    title: "New Routine",
                    exercises: pickedExercises,
                    isPinned: false,
                    showsNameField: true,
                    showsPinToggle: false,
                    primaryActionLabel: "Save Routine",
                    primaryActionIcon: "checkmark",
                    pickingOriginTab: originTab,
                    showsAddExercisesButton: false
                ) { name, exercises, _, durationOverrides in
                    let routine = Routine(
                        name: name,
                        exerciseIDs: exercises.map(\.uuid),
                        exerciseDurationOverrides: durationOverrides,
                        ownerID: auth.backendID
                    )
                    routine.insertAndQueueForSync(in: modelContext)
                    try? modelContext.save()
                    onFinished()
                    dismiss()
                }
            }
            .sheet(isPresented: $showingRoutineChooser) {
                RoutineChooserView(pickedExercises: pickedExercises) {
                    onFinished()
                    dismiss()
                }
            }
            // Same "Customize sheet, then the real session sheet" chaining
            // TodayView uses (pendingShowSessionAfterCustomize) — Customize
            // must fully dismiss before SessionPlayerView's own sheet can
            // present, so the follow-up session is presented from here
            // (onDismiss), not from Customize's own onDone.
            .sheet(isPresented: $showingCustomizeForMiniSession, onDismiss: {
                if !pendingMiniSessionExercises.isEmpty { showingMiniSession = true }
            }) {
                CustomizeRoutineView(
                    title: "Start Mini-Routine",
                    exercises: pickedExercises,
                    isPinned: false,
                    showsPinToggle: false,
                    primaryActionLabel: "Start",
                    pickingOriginTab: originTab,
                    showsAddExercisesButton: false
                ) { _, exercises, _, durationOverrides in
                    pendingMiniSessionExercises = exercises
                    pendingMiniSessionDurationOverrides = durationOverrides
                }
            }
            // Unlike the routine-builder destinations (which distinguish
            // Save from Cancel via `onSaved`), starting a mini-routine has
            // no "did nothing" outcome to guard against — any dismissal of
            // the player (finished or backed out early) ends this flow.
            .sheet(isPresented: $showingMiniSession, onDismiss: {
                onFinished()
                dismiss()
            }) {
                SessionPlayerView(exercises: pendingMiniSessionExercises, durationOverrides: pendingMiniSessionDurationOverrides)
            }
        }
    }

    private func destinationRow(title: String, subtitle: String, systemImage: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.luminaPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.luminaMintTint, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.luminaCardTitle)
                        .foregroundStyle(Color.luminaOnSurface)
                    Text(subtitle)
                        .font(.luminaCaption)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
            }
            .luminaCard(padding: 14)
        }
        .buttonStyle(.plain)
        // Overrides the default combined-children label (title + subtitle
        // concatenated) so both VoiceOver and UI tests can address the row
        // by its title alone — matches ExerciseGridTile's convention.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Existing-routine chooser

/// Lightweight routine picker for the "Add to Existing Routine" destination.
/// Selecting a routine pushes into `RoutineBuilderView` pre-seeded with the
/// picks, mirroring how `RoutineListView` presents editing.
private struct RoutineChooserView: View {
    let pickedExercises: [Exercise]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var allRoutines: [Routine]
    @EnvironmentObject private var auth: AuthManager
    @State private var routineToAddTo: Routine?

    /// Only the current account's routines — see `Routine.ownerID`.
    private var routines: [Routine] {
        allRoutines.filter { $0.ownerID == auth.backendID && $0.deletedAt == nil }
    }

    var body: some View {
        NavigationStack {
            List(routines) { routine in
                Button {
                    routineToAddTo = routine
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(routine.name)
                                .font(.luminaCardTitle)
                                .foregroundStyle(Color.luminaOnSurface)
                            Text("\(routine.exerciseIDs.count) exercise\(routine.exerciseIDs.count == 1 ? "" : "s")")
                                .font(.luminaCaption)
                                .foregroundStyle(Color.luminaOnSurfaceVariant)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.luminaOnSurfaceVariant)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.luminaSurface)
            .navigationTitle("Add to Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if routines.isEmpty {
                    ContentUnavailableView(
                        "No Routines Yet",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text("Create a routine first, or start this as a mini-routine instead.")
                    )
                }
            }
            .sheet(item: $routineToAddTo) { routine in
                RoutineBuilderView(routineToEdit: routine, initialExerciseIDs: pickedExercises.map(\.uuid), allowsCrossTabAddExercise: false) {
                    onSaved()
                    dismiss()
                }
                .environmentObject(AuthManager.shared)
            }
        }
    }
}
