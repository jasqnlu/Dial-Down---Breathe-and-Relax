import SwiftUI
import SwiftData

struct ExerciseListView: View {
    @Query private var exercises: [Exercise]
    @State private var searchText = ""
    @State private var selectedType: ExerciseType? = nil
    @State private var selectedDifficulties: Set<Int> = []
    @State private var durationBucket: ExerciseDurationBucket = .any
    @State private var showingFilterSheet = false
    @State private var selectedExercise: Exercise?
    @State private var visibleSearchCount = ExerciseSearchResults.pageSize
    @FocusState private var isSearchFocused: Bool
    @EnvironmentObject private var pickingSession: ExercisePickingSession

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasActiveFilters: Bool {
        selectedType != nil || !selectedDifficulties.isEmpty || durationBucket != .any
    }

    private var searchResults: ExerciseSearchResults {
        ExerciseSearchResults(
            exercises: exercises,
            searchText: normalizedSearchText,
            selectedType: selectedType,
            visibleCount: visibleSearchCount,
            selectedDifficulties: selectedDifficulties,
            durationBucket: durationBucket
        )
    }

    private var isShowingDetail: Binding<Bool> {
        Binding(get: { selectedExercise != nil }, set: { if !$0 { selectedExercise = nil } })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .background(Color.luminaSurface)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // `.safeAreaInset` stacks bottom-up in application order: the LAST
            // one applied claims the outermost slot, right at the screen edge —
            // exactly the 80pt zone the real floating `CustomTabBar` overlay
            // occupies. `pickingBar` must be applied BEFORE
            // `.floatingTabBarClearance()` so it lands just above that reserved
            // zone instead of underneath the tab bar (where its taps would be
            // swallowed by the tab bar sitting on top of it).
            .safeAreaInset(edge: .bottom) {
                if pickingSession.isActive {
                    PickingBar()
                }
            }
            .floatingTabBarClearance()
            .onChange(of: normalizedSearchText) { _, _ in
                resetSearchPage()
            }
            .onChange(of: selectedType) { _, _ in
                resetSearchPage()
            }
            .onChange(of: selectedDifficulties) { _, _ in
                resetSearchPage()
            }
            .onChange(of: durationBucket) { _, _ in
                resetSearchPage()
            }
            .navigationDestination(isPresented: isShowingDetail) {
                if let selectedExercise {
                    ExerciseDetailView(exercise: selectedExercise)
                }
            }
            .sheet(isPresented: $showingFilterSheet) {
                ExerciseFilterSheet(
                    selectedType: $selectedType,
                    selectedDifficulties: $selectedDifficulties,
                    durationBucket: $durationBucket
                )
            }
            .overlay {
                if exercises.isEmpty {
                    ContentUnavailableView(
                        "No Exercises",
                        systemImage: "figure.mind.and.body",
                        description: Text("Seed exercises will load on first launch.")
                    )
                }
            }
        }
    }

    /// Difficulty/duration applied ahead of the graph-browse vs. search-grid
    /// split below: `ExerciseGraphView` only understands a type filter today
    /// (its zoom/pan node layout is keyed off category, not an arbitrary
    /// predicate), so pre-filtering here is what makes Difficulty/Duration
    /// apply while browsing by category, not just once text is typed into
    /// search. `ExerciseSearchResults` re-derives the same two filters
    /// independently for the search-grid path (see `searchResults` below).
    private var difficultyAndDurationFilteredExercises: [Exercise] {
        exercises.filter { exercise in
            (selectedDifficulties.isEmpty || selectedDifficulties.contains(exercise.difficulty))
                && durationBucket.matches(exercise.durationSeconds)
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if normalizedSearchText.isEmpty {
                ExerciseGraphView(exercises: difficultyAndDurationFilteredExercises, typeFilter: selectedType) { exercise in
                    selectedExercise = exercise
                }
                // Panned/zoomed bubbles stay inside the map's own area
                // instead of sliding over the header.
                .clipped()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(searchResults.visible, id: \.uuid) { exercise in
                            ExerciseGridTile(
                                exercise: exercise,
                                badge: pickingSession.isActive ? .add(isSelected: pickingSession.isPicked(exercise)) : .none
                            ) {
                                if pickingSession.isActive {
                                    pickingSession.toggle(exercise)
                                } else {
                                    selectedExercise = exercise
                                }
                            } onBadgeTap: {
                                if pickingSession.isActive { pickingSession.toggle(exercise) }
                            }
                        }

                        if searchResults.canLoadMore {
                            ProgressView()
                                .gridCellColumns(2)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .onAppear {
                                    visibleSearchCount = searchResults.nextVisibleCount
                                }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .overlay {
                    if searchResults.matches.isEmpty {
                        ContentUnavailableView(
                            "No Exercises",
                            systemImage: "figure.mind.and.body",
                            description: Text("No results for your search.")
                        )
                    }
                }
            }
        }
        .tourAnchor("exercises.browseByArea")
    }

    private func resetSearchPage() {
        visibleSearchCount = ExerciseSearchResults.pageSize
    }

    /// Large title + count, the search row, and quick type chips — the
    /// seperate-main restyle's header (no Liquid Glass container anymore).
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Exercises")
                    .font(.luminaDisplay)
                    .tracking(-0.6)
                Spacer()
                Text("\(exercises.count) total")
                    .font(.luminaCaption)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
            }

            HStack(spacing: 10) {
                searchBar
                    .tourAnchor("exercises.search")

                Button {
                    showingFilterSheet = true
                } label: {
                    Label("Filter", systemImage: hasActiveFilters
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(hasActiveFilters ? Color.onPastel : Color.luminaOnSurfaceVariant)
                        .frame(width: 36, height: 36)
                }
                .background(hasActiveFilters ? Color.pastelMint : Color.luminaContainer, in: Circle())
                .accessibilityIdentifier("exerciseFilterButton")

                // Standalone entry into picking mode — no Customize context, so
                // `PickingBar`'s action button reads "Continue" and opens
                // `MiniRoutineReviewView` instead of merging into a routine.
                // Toggling while already active cancels the picks, mirroring
                // how tapping "Select" again is expected to back out.
                Button {
                    if pickingSession.isActive {
                        pickingSession.cancel()
                    } else {
                        pickingSession.begin()
                    }
                } label: {
                    Label(pickingSession.isActive ? "Cancel" : "Select",
                          systemImage: pickingSession.isActive ? "xmark.circle" : "checkmark.circle")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(pickingSession.isActive ? Color.onPastel : Color.luminaOnSurfaceVariant)
                        .frame(width: 36, height: 36)
                }
                .background(pickingSession.isActive ? Color.pastelMint : Color.luminaContainer, in: Circle())
                .accessibilityIdentifier("exerciseSelectToggle")
            }

            typeChips
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// Quick type filter, mirroring the filter sheet's Type section (both
    /// bind `selectedType`, so they stay in sync).
    private var typeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                LuminaChip(title: "All", isSelected: selectedType == nil) { selectedType = nil }
                ForEach(ExerciseType.allCases, id: \.self) { type in
                    LuminaChip(title: type.rawValue, isSelected: selectedType == type) {
                        selectedType = selectedType == type ? nil : type
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    /// A flat iOS-style search field (neutral gray rounded rect, gray
    /// glyph) — the seperate-main restyle replaced the amber-tinted glass.
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.luminaOnSurfaceVariant)

            TextField("Search exercises", text: $searchText)
                .font(.luminaSubheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .padding(.horizontal, 12)
        .background(Color.luminaContainer, in: RoundedRectangle(cornerRadius: LuminaRadius.badge, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// The count/time/Done bar shown while an `ExercisePickingSession` is active.
///
/// Extracted into its own view because it has to be attached on BOTH the
/// Exercises tab root (`ExerciseListView`, which owns the search-results grid)
/// and on `ExerciseGroupCorpusSheet` — the pushed tile grid that is the primary
/// picking surface. A `.safeAreaInset` applied to a NavigationStack's root
/// never reaches its pushed destinations (the UINavigationController bridge
/// owns those insets; see `HomeView.swift`'s `.floatingTabBarClearance()`
/// note), so the bar genuinely has to be applied in both places.
///
/// Deliberately NOT wrapped in `.accessibilityElement(children: .combine)`:
/// matching `BodyMapComponents.swift`'s `miniRoutineBar`, the counts and the
/// action button stay separate elements so "Done" remains individually
/// focusable and actionable for VoiceOver.
struct PickingBar: View {
    /// Which HomeView tab hosts the screen this bar is attached to —
    /// forwarded to `MiniRoutineReviewView` so its own Customize sheets
    /// route "Add Exercises" back to the right tab. Defaults to 2
    /// (Exercises), this bar's original home; `BodyPartExercisesView`
    /// passes 1 (Body) since it hosts the same bar.
    var originTab: Int = 2
    @EnvironmentObject private var pickingSession: ExercisePickingSession
    @State private var showingReview = false

    private var pickedMinutes: Int {
        pickingSession.picked.isEmpty ? 0 : max(1, Int((Double(pickingSession.pickedTotalSeconds) / 60).rounded()))
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(pickingSession.picked.count) exercise\(pickingSession.picked.count == 1 ? "" : "s")")
                    .font(.luminaCardTitle)
                    .accessibilityIdentifier("pickingBarCount")
                Text("\(pickedMinutes) min")
                    .font(.luminaCaption)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                    .accessibilityIdentifier("pickingBarMinutes")
            }
            Spacer(minLength: 8)
            Button {
                if pickingSession.hasContext {
                    // Customize's "Add Exercises" flow — unchanged: merge
                    // straight back into the routine being built there.
                    pickingSession.finish()
                    NotificationCenter.default.post(name: .exercisePickingFinished, object: nil)
                } else {
                    // Standalone picking, started from this tab's own
                    // "Select" button — review before committing to one of
                    // the three destinations.
                    showingReview = true
                }
            } label: {
                Text(pickingSession.hasContext ? "Done" : "Continue")
            }
            .buttonStyle(LuminaPillButtonStyle(kind: .prominent, compact: true))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.luminaCardFill)
        .overlay(alignment: .top) { Rectangle().fill(Color.luminaHairline).frame(height: 0.5) }
        .sheet(isPresented: $showingReview) {
            MiniRoutineReviewView(pickedExercises: pickingSession.picked, originTab: originTab) {
                pickingSession.cancel()
            }
        }
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fixed rather than proportional-to-row-width: a `GeometryReader`
    /// measuring this view's own width, fed back into `@State` that this same
    /// view's layout then depends on, is a measure→re-render→re-measure loop
    /// — SwiftUI doesn't always settle it in one pass, and with many rows
    /// alive at once (a `List`/`LazyVStack` of ~180 exercises) it can pin the
    /// main thread relaying out indefinitely. A constant sidesteps the loop
    /// entirely; the `stats` column still flexes to fill the rest of the row.
    private let thumbnailSide: CGFloat = 120

    var difficultyLabel: String {
        switch exercise.difficulty {
        case 1: return "Easy"
        case 2: return "Medium"
        case 3: return "Hard"
        default: return ""
        }
    }

    private var hasDemo: Bool {
        exercise.demoVideoURL != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exercise.name)
                .font(.luminaCardTitle)
                .foregroundStyle(Color.luminaOnSurface)
                .lineLimit(2)

            HStack(alignment: .top, spacing: 12) {
                thumbnail
                    .frame(width: thumbnailSide, height: thumbnailSide)
                    .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous))
                    .accessibilityHidden(true)

                stats
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(exercise.name), \(exercise.type.rawValue), \(exercise.durationFormatted), \(difficultyLabel)\(hasDemo ? ", has animated demo" : "")\(exercise.caution.map { ", caution: \($0)" } ?? "")")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = exercise.demoVideoURL {
            LoopingVideoThumbnail(url: url, reduceMotion: reduceMotion)
        } else {
            ZStack {
                Color.luminaContainer
                Image(systemName: "figure.mind.and.body")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
            }
        }
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(exercise.type.rawValue)
                    .font(.luminaLabel)
                    .foregroundStyle(Color.onPastel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.pastelBlue, in: Capsule())

                difficultyDots
            }

            Label(exercise.durationFormatted, systemImage: "clock")
                .font(.luminaCaption)
                .foregroundStyle(Color.luminaOnSurfaceVariant)

            if let caution = exercise.caution, !caution.isEmpty {
                cautionLine(caution)
            }
        }
    }

    private var difficultyDots: some View {
        HStack(spacing: 3) {
            ForEach(1...3, id: \.self) { level in
                Circle()
                    .fill(level <= exercise.difficulty ? Color.luminaPrimary : Color.luminaOutline)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityLabel(difficultyLabel)
    }

    private func cautionLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.pastelPeach)
            Text(text)
                .font(.luminaCaption)
                .foregroundStyle(Color.luminaOnSurface)
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.pastelPeach.opacity(0.14), in: RoundedRectangle(cornerRadius: LuminaRadius.tag, style: .continuous))
    }
}

#Preview {
    ExerciseListView()
        .modelContainer(for: Exercise.self, inMemory: true)
}
