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
    @State private var selectedPremade: PremadeRoutine?
    @State private var showingAllPremade = false

    var body: some View {
        NavigationStack {
            List {
                // Premade strip — same tiles as Today's "Premade Routines" row.
                Section {
                    premadeStrip
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .tourAnchor("routines.sharedList")
                }

                Section {
                    yourRoutinesHeader
                        .tourAnchor("routines.yourRoutines")
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    if routines.isEmpty {
                        emptyStateCard
                            .tourAnchor("routines.yourRoutines#first")
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    ForEach(Array(sortedRoutines.enumerated()), id: \.element.id) { index, routine in
                        RoutineRow(
                            routine: routine,
                            resolvedCount: resolvedExercises(for: routine).count,
                            minutes: totalMinutes(for: routine),
                            pastel: Color.pastels[index % Color.pastels.count]
                        ) {
                            routineToPlay = routine
                        }
                        // The tour's "Your Routines" spotlight covers the header
                        // plus the first card; other rows get unused ids.
                        .tourAnchor(index == 0 ? "routines.yourRoutines#first" : "routines.row\(index)")
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
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
                            // appended to the end of the priority order; the
                            // reorder sheet on Today arranges priority.
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
                    Button(action: startNewRoutine) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Routine")
                }
            }
            .navigationDestination(isPresented: $showingAllPremade) {
                PremadeRoutinesView()
            }
            .sheet(item: $selectedPremade) { routine in
                PremadeRoutineCustomizeSheet(routine: routine, exercises: exercises)
            }
            .sheet(item: $routineToEdit) { routine in
                RoutineBuilderView(routineToEdit: routine)
            }
            .onReceive(NotificationCenter.default.publisher(for: .exercisePickingFinished)) { _ in
                // Peek first and check originTab before consuming — Customize (Home,
                // tab 0) can also finish a pick, and this same notification fires at
                // every mounted listener. See TodayView.swift's identical handler for
                // the full rationale.
                guard let result = pickingSession.lastFinished, result.context.originTab == AppTab.routines.rawValue else { return }
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

    /// Pinned routines first (in Today's priority order), then newest first.
    private var sortedRoutines: [Routine] {
        routines.sorted { a, b in
            if a.isPinnedToToday != b.isPinnedToToday { return a.isPinnedToToday }
            if a.isPinnedToToday { return a.pinnedOrder < b.pinnedOrder }
            return a.createdAt > b.createdAt
        }
    }

    /// Total play time in whole minutes, honoring per-routine duration overrides.
    private func totalMinutes(for routine: Routine) -> Int {
        let secs = resolvedExercises(for: routine).reduce(0) {
            $0 + (routine.exerciseDurationOverrides[$1.uuid] ?? $1.durationSeconds)
        }
        return max(1, Int((Double(secs) / 60).rounded()))
    }

    private func premadeMeta(for routine: PremadeRoutine) -> (count: Int, minutes: Int)? {
        let resolved = routine.resolvedExercises(in: exercises)
        guard !resolved.isEmpty else { return nil }
        let totalSecs = resolved.reduce(0) { $0 + $1.durationSeconds }
        return (resolved.count, max(1, Int((Double(totalSecs) / 60).rounded())))
    }

    /// "+ New Routine" jumps straight into the Exercises tab's picking flow;
    /// the `.exercisePickingFinished` handler routes the result into
    /// RoutineBuilderView for naming/saving.
    private func startNewRoutine() {
        pickingSession.begin(context: .init(
            title: "",
            isPinned: false,
            baseExercises: [],
            originTab: AppTab.routines.rawValue,
            editingRoutineID: nil,
            durationOverrides: [:]
        ))
        NotificationCenter.default.post(name: .browseExercisesRequested, object: nil)
    }

    // MARK: Sections

    private var premadeStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Premade")
                    .font(.luminaTitle)
                    .foregroundStyle(Color.luminaOnSurface)
                Spacer()
                Button {
                    showingAllPremade = true
                } label: {
                    HStack(spacing: 4) {
                        Text("See all")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(.luminaLabel)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.luminaCardFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Premade Routines")
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(PremadeRoutine.all) { routine in
                        let meta = premadeMeta(for: routine)
                        Button {
                            selectedPremade = routine
                        } label: {
                            PremadeRoutineCard(routine: routine, meta: meta)
                        }
                        .buttonStyle(.plain)
                        .disabled(meta == nil)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
    }

    private var yourRoutinesHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Your Routines")
                    .font(.luminaTitle)
                    .foregroundStyle(Color.luminaOnSurface)
                if !routines.isEmpty {
                    LuminaCountBadge(count: routines.count)
                }
                Spacer()
            }
            if !routines.isEmpty {
                Text("Swipe right to pin to Today, left to edit or share.")
                    .font(.luminaCaption)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
            }
        }
    }

    private var emptyStateCard: some View {
        VStack(spacing: 14) {
            LuminaIconBadge(systemName: "rectangle.stack.badge.plus", tint: .pastelLavender, size: 64)
            VStack(spacing: 4) {
                Text("No Routines Yet")
                    .font(.luminaHeadline)
                    .foregroundStyle(Color.luminaOnSurface)
                Text("Build your own from your favorite exercises, or save a premade one above.")
                    .font(.luminaBody)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
            Button(action: startNewRoutine) {
                // Explicit style: inside a List row a bare Label can collapse to icon-only.
                Label("Create a Routine", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(LuminaPillButtonStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .luminaCard(padding: 20)
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
    var minutes: Int = 0
    var pastel: Color = .pastelMint
    let onPlay: () -> Void

    private var initial: String {
        routine.name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "R"
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(initial)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.onPastel)
                .frame(width: 46, height: 46)
                .background(pastel, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(routine.name)
                        .font(.luminaCardTitle)
                        .foregroundStyle(Color.luminaOnSurface)
                        .lineLimit(1)
                    if routine.isPinnedToToday {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.onPastel)
                            .frame(width: 18, height: 18)
                            .background(Color.pastelYellow, in: Circle())
                            .accessibilityLabel("Pinned to Today")
                    }
                }

                HStack(spacing: 6) {
                    if resolvedCount == 0 {
                        Text("Unavailable")
                    } else {
                        Text("\(resolvedCount) exercise\(resolvedCount == 1 ? "" : "s") · \(minutes) min")
                    }
                    if routine.borrowedFromID != nil {
                        Label("Borrowed", systemImage: "arrow.triangle.branch")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.luminaContainer, in: Capsule())
                    }
                }
                .font(.luminaCaption)
                .foregroundStyle(Color.luminaOnSurfaceVariant)
            }

            Spacer(minLength: 8)

            Button(action: onPlay) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.luminaOnPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.luminaPrimary, in: Circle())
                    .opacity(resolvedCount == 0 ? 0.35 : 1)
            }
            .buttonStyle(.plain)
            .disabled(resolvedCount == 0)
            .accessibilityLabel("Play \(routine.name)")
        }
        .luminaCard(padding: 14)
        .contentShape(Rectangle())
    }
}

#Preview {
    RoutineListView()
        .modelContainer(for: [Routine.self, Exercise.self], inMemory: true)
        .environmentObject(AuthManager.shared)
}
