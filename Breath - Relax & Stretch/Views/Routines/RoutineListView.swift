import SwiftUI
import SwiftData

struct RoutineListView: View {
    @Query private var allRoutines: [Routine]
    @Query private var exercises: [Exercise]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var pickingSession: ExercisePickingSession
    @EnvironmentObject private var auth: AuthManager

    /// Only the current account's routines — `allRoutines` holds every
    /// routine ever created on this device, across every account that's
    /// signed in on it. See `Routine.ownerID`.
    private var routines: [Routine] {
        allRoutines.filter { $0.ownerID == auth.backendID && $0.deletedAt == nil }
    }

    @State private var routineToPlay: Routine?
    @State private var routineToEdit: Routine?
    @State private var routinePendingDelete: Routine?
    /// Snapshot to restore into RoutineBuilderView after a cross-tab
    /// "Add Exercise" round trip — set by the `.exercisePickingFinished`
    /// handler below, consumed by the `showingBuilderAfterPick` sheet.
    @State private var builderRestoredState: (routineToEdit: Routine?, name: String, exerciseIDs: [UUID], durationOverrides: [UUID: Int])?
    @State private var showingBuilderAfterPick = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(destination: PremadeRoutinesView()) {
                        entryRow(title: "Premade Routines", systemImage: "sparkles")
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .tourAnchor("routines.sharedList")
                }

                ForEach(routines) { routine in
                    RoutineRow(routine: routine, resolvedCount: resolvedExercises(for: routine).count) {
                        routineToPlay = routine
                    }
                    .listRowBackground(Color.luminaCardFill)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            routinePendingDelete = routine
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            routineToEdit = routine
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(Color.luminaContainer)

                        if let url = shareURL(for: routine) {
                            ShareLink(item: url) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .tint(Color(red: 0.36, green: 0.45, blue: 0.62))
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        // Toggles instantly, no confirmation — same as
                        // flipping a switch. Newly pinned routines are
                        // appended to the end of the priority order rather
                        // than jumping to the front; the reorder sheet on
                        // Today (once 2+ are pinned) is where the user
                        // actually arranges priority.
                        Button {
                            togglePin(routine)
                        } label: {
                            Label(
                                routine.isPinnedToToday ? "Unpin" : "Pin to Today",
                                systemImage: routine.isPinnedToToday ? "pin.slash.fill" : "pin.fill"
                            )
                        }
                        .tint(Color.luminaPrimary)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.luminaSurface)
            .navigationTitle("Routines")
            // Left unset before, which defaults to a large title at the root
            // of a NavigationStack — made explicit and aligned to .inline to
            // match the other tab roots (see page-title convention audit).
            .navigationBarTitleDisplayMode(.large)
            .floatingTabBarClearance()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // "+ New Routine" now jumps straight into the Exercises
                    // tab's picking flow — same pickingSession the old empty
                    // CustomizeRoutineView screen's own "Add Exercises"
                    // button used to require a second tap for. The
                    // `.exercisePickingFinished` handler below still routes
                    // the result into RoutineBuilderView for naming/saving.
                    Button {
                        pickingSession.begin(context: .init(
                            title: "",
                            isPinned: false,
                            baseExercises: [],
                            originTab: 4, // Routines tab
                            editingRoutineID: nil,
                            durationOverrides: [:]
                        ))
                        NotificationCenter.default.post(name: .browseExercisesRequested, object: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .overlay {
                if routines.isEmpty {
                    ContentUnavailableView {
                        VStack(spacing: 16) {
                            Image(systemName: "rectangle.stack.badge.plus")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.luminaOnSurfaceVariant)
                                .frame(width: 88, height: 88)
                                .background(Color.luminaContainer, in: Circle())
                            Text("No Routines Yet")
                                .font(.luminaHeadline)
                                .foregroundStyle(Color.luminaOnSurface)
                        }
                    } description: {
                        Text("Create your own routine from your favorite exercises.")
                            .font(.luminaBody)
                            .foregroundStyle(Color.luminaOnSurfaceVariant)
                    }
                }
            }
            .sheet(item: $routineToEdit) { routine in
                RoutineBuilderView(routineToEdit: routine)
            }
            .onReceive(NotificationCenter.default.publisher(for: .exercisePickingFinished)) { _ in
                // Peek first and check originTab before consuming — Customize (Home,
                // tab 0) can also finish a pick, and this same notification fires at
                // every mounted listener. See TodayView.swift's identical handler for
                // the full rationale.
                guard let result = pickingSession.lastFinished, result.context.originTab == 4 else { return }
                _ = pickingSession.consumeFinished()
                let editingRoutine = result.context.editingRoutineID.flatMap { id in
                    routines.first(where: { $0.uuid == id })
                }
                builderRestoredState = (
                    routineToEdit: editingRoutine,
                    name: result.context.title,
                    exerciseIDs: result.merged.map(\.uuid),
                    durationOverrides: result.context.durationOverrides
                )
                showingBuilderAfterPick = true
            }
            .sheet(isPresented: $showingBuilderAfterPick, onDismiss: {
                builderRestoredState = nil
            }) {
                RoutineBuilderView(
                    routineToEdit: builderRestoredState?.routineToEdit,
                    restoredState: builderRestoredState.map {
                        (name: $0.name, exerciseIDs: $0.exerciseIDs, durationOverrides: $0.durationOverrides)
                    }
                )
            }
            .confirmationDialog(
                "Delete this routine?",
                isPresented: Binding(
                    get: { routinePendingDelete != nil },
                    set: { if !$0 { routinePendingDelete = nil } }
                ),
                presenting: routinePendingDelete
            ) { routine in
                Button("Delete", role: .destructive) {
                    routine.markDeleted(in: modelContext)
                    routinePendingDelete = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: { routine in
                Text("\"\(routine.name)\" will be permanently deleted. This can't be undone.")
            }
            .sheet(item: $routineToPlay) { routine in
                let resolved = resolvedExercises(for: routine)
                if resolved.isEmpty {
                    ContentUnavailableView(
                        "No Exercises Found",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The exercises in this routine couldn't be loaded.")
                    )
                } else {
                    SessionPlayerView(
                        exercises: resolved,
                        routineID: routine.uuid,
                        isBorrowedRoutine: routine.borrowedFromID != nil,
                        durationOverrides: routine.exerciseDurationOverrides
                    )
                }
            }
        }
    }

    private func resolvedExercises(for routine: Routine) -> [Exercise] {
        let byID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.uuid, $0) })
        return routine.exerciseIDs.compactMap { byID[$0] }
    }

    /// Pins/unpins a routine as a Today launch candidate. A newly-pinned
    /// routine is appended to the end of the current priority order — same
    /// "don't jump the queue" rule Customize's own pin toggle follows (see
    /// `TodayView.nextPinnedOrder()`), so pinning several routines in a row
    /// from here lands them in the order you pinned them, still reorderable
    /// afterward from Today.
    private func togglePin(_ routine: Routine) {
        if routine.isPinnedToToday {
            routine.isPinnedToToday = false
        } else {
            let maxOrder = routines.filter(\.isPinnedToToday).map(\.pinnedOrder).max() ?? -1
            routine.isPinnedToToday = true
            routine.pinnedOrder = maxOrder + 1
        }
        routine.markUpdated(in: modelContext)
    }

    private func shareURL(for routine: Routine) -> URL? {
        let names = resolvedExercises(for: routine).map { $0.name }
        guard !names.isEmpty else { return nil }
        return RoutineSharePayload(name: routine.name, exerciseNames: names).shareURL
    }

    private func entryRow(title: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            LuminaIconBadge(systemName: systemImage, tint: .pastelYellow, size: 44)

            Text(title)
                .font(.luminaCardTitle)
                .foregroundStyle(Color.luminaOnSurface)

            Spacer()
        }
        .luminaCard(padding: 14)
    }
}

// MARK: - Routine row

struct RoutineRow: View {
    let routine: Routine
    /// Count of exerciseIDs that actually resolve against the local catalog —
    /// can be lower than exerciseIDs.count (e.g. borrowed routines referencing
    /// exercises that don't exist on this install), so this is what actually
    /// determines whether the routine can play, not the raw ID count.
    let resolvedCount: Int
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(routine.name)
                        .font(.luminaCardTitle)
                    if routine.isPinnedToToday {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.luminaPrimary)
                            .accessibilityLabel("Pinned to Today")
                    }
                    if routine.borrowedFromID != nil {
                        Label("Borrowed", systemImage: "arrow.triangle.branch")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Label("\(resolvedCount) exercise\(resolvedCount == 1 ? "" : "s")",
                          systemImage: "list.number")
                }
                .font(.luminaCaption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onPlay) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.luminaOnPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.luminaPrimary, in: Circle())
                    .opacity(resolvedCount == 0 ? 0.35 : 1)
            }
            .buttonStyle(.plain)
            .disabled(resolvedCount == 0)
            .accessibilityLabel("Play \(routine.name)")
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RoutineListView()
        .modelContainer(for: [Routine.self, Exercise.self], inMemory: true)
        .environmentObject(AuthManager.shared)
}
