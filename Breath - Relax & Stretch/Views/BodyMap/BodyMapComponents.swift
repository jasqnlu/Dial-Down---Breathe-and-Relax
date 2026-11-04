import SwiftUI
import SwiftData

// MARK: - Region action bar
//
// Rises once the muscle picker collapses back to its zoomed region view
// (tapping off the picker, or Cancel) — or, rarely, when a tap resolves a
// region with no hit-volume candidates at all. One tap from here to that
// region's stretches.

struct RegionActionBar: View {
    let regionName: String
    let onFind: () -> Void

    var body: some View {
        Button(action: onFind) {
            HStack(spacing: 14) {
                LuminaIconBadge(systemName: "figure.flexibility", tint: .pastelPeach, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stretches for")
                        .font(.luminaCaption)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                    Text(regionName)
                        .font(.luminaTitle)
                        .foregroundStyle(Color.luminaOnSurface)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.luminaOnPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.luminaPrimary, in: Circle())
            }
            .luminaCard(padding: 16)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bodymap.regionActionBar")
        .accessibilityLabel("Find stretches for \(regionName)")
    }
}

// MARK: - Region → exercise resolution
//
// Marked regions use the body map's COARSE names ("Core", "Left Arm", "Hips"),
// but exercises target the FINE muscle-group names the seed data uses ("Abs",
// "Left Biceps", "Left Hip Flexors"). The old code matched the two with a naive
// bidirectional substring test, so coarse regions that don't share a substring
// with any muscle name ("Core"↛"Abs", "Left Arm"↛"Left Biceps") silently
// matched nothing.
//
// This resolver instead translates coarse → fine via `MuscleGroup.migrate`
// (the same mapping the rest of the app uses), matches exactly, and then adds a
// same-category fallback: exercises in the marked region's `ExerciseCategory`
// that don't directly hit the muscle group. So a region with few specific
// stretches surfaces related ones from the same area instead of nothing — and
// never the whole catalog.
struct RegionExerciseResolver {
    /// Exercises that directly target one of the marked muscle groups.
    let direct: [Exercise]
    /// Other exercises in the same body-area category (the "related" fallback).
    let related: [Exercise]

    init(regions: [String], exercises: [Exercise]) {
        // A marked region is a muscle group / coarse name, an anatomical
        // sub-head ("Left Triceps Long Head"), or a joint region ("Left Hip").
        // Heads and joints both match their own tagged exercises directly
        // (distinct, dedicated content), and fall back to the parent/crossing
        // muscles' exercises as "related" so a region with no curated
        // stretches yet still shows something useful. Group/coarse names keep
        // the original behaviour: migrate coarse → fine, then category fallback.
        var directNames: [String] = []
        var parentNames: [String] = []
        for region in regions {
            if let parent = MuscleGroup.parentOfHead(region) {
                directNames.append(region)
                parentNames.append(parent)
            } else if JointRegion.isJoint(region) {
                directNames.append(region)
                parentNames.append(contentsOf: MuscleGroup.migrate([region]))
            } else {
                directNames.append(contentsOf: MuscleGroup.migrate([region]))
            }
        }
        let directSet = Set(directNames.map { $0.lowercased() })
        let parentSet = Set(MuscleGroup.migrate(parentNames).map { $0.lowercased() })
        let categories = ExerciseCategory.categories(for: directNames + parentNames)

        var directList: [Exercise] = []
        var relatedList: [Exercise] = []
        for exercise in exercises {
            // Pure breathing exercises have no body-part target of their own;
            // never let one leak into a body-map region via the same-area
            // fallback below (mirrors ExerciseGraphView's type filtering).
            guard exercise.type != .breath else { continue }
            let targets = exercise.targetBodyParts
            let lowered = targets.map { $0.lowercased() }
            if lowered.contains(where: { directSet.contains($0) }) {
                directList.append(exercise)
            } else if lowered.contains(where: { parentSet.contains($0) }) {
                relatedList.append(exercise)                       // parent-muscle fallback
            } else if !categories.isEmpty,
                      !categories.isDisjoint(with: ExerciseCategory.categories(for: targets)) {
                relatedList.append(exercise)                       // same-area fallback
            }
        }
        self.direct = directList.sorted { $0.name < $1.name }
        self.related = relatedList.sorted { $0.name < $1.name }
    }

    var isEmpty: Bool { direct.isEmpty && related.isEmpty }
}

// MARK: - Filtered exercise list for one or more body parts

struct BodyPartExercisesView: View {
    let bodyParts: [String]
    @Query private var allExercises: [Exercise]
    // Same cross-tab picking session the Exercises tab's own "Select" mode
    // uses (see `ExerciseListView`) — this screen used to keep its own
    // standalone `MiniRoutineState` and could only ever build a throwaway
    // mini routine. Sharing `ExercisePickingSession` instead gets Body Map
    // the exact same Select/Cancel toggle, picking bar, and three-way
    // "Create New Routine / Add to Existing Routine / Start Mini-Routine"
    // review screen the Exercises tab has, for free.
    @EnvironmentObject private var pickingSession: ExercisePickingSession
    @State private var selectedExercise: Exercise?

    private var isShowingDetail: Binding<Bool> {
        Binding(get: { selectedExercise != nil }, set: { if !$0 { selectedExercise = nil } })
    }

    init(bodyPart: String)        { self.bodyParts = [bodyPart] }

    private var resolver: RegionExerciseResolver {
        RegionExerciseResolver(regions: bodyParts, exercises: allExercises)
    }

    private var navTitle: String {
        bodyParts.count == 1 ? bodyParts[0] : "\(bodyParts.count) Areas"
    }

    var body: some View {
        let resolver = resolver
        return Group {
            if resolver.isEmpty {
                ContentUnavailableView(
                    "No Exercises Found",
                    systemImage: "figure.mind.and.body",
                    description: Text(emptyDescription)
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if bodyParts.count > 1 {
                            Text(bodyParts.joined(separator: ", "))
                                .font(.luminaCaption)
                                .foregroundStyle(Color.luminaOnSurfaceVariant)
                        }
                        if !resolver.direct.isEmpty {
                            exerciseSection(title: "\(resolver.direct.count) exercise\(resolver.direct.count == 1 ? "" : "s")", exercises: resolver.direct)
                        }
                        if !resolver.related.isEmpty {
                            exerciseSection(title: relatedSectionTitle, footer: relatedFooterText, exercises: resolver.related)
                        }
                    }
                    .padding()
                }
                .tourAnchor("bodymap.regionResults")
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Mirrors ExerciseListView's own Select/Cancel toggle exactly —
            // same environment object, same "toggling while already active
            // cancels the picks" behavior. Placed in the nav bar here since
            // this screen (reached only after a region is picked) has no
            // header row of its own to host it in.
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if pickingSession.isActive {
                        pickingSession.cancel()
                    } else {
                        pickingSession.begin()
                    }
                } label: {
                    Label(pickingSession.isActive ? "Cancel" : "Select",
                          systemImage: pickingSession.isActive ? "xmark.circle" : "checkmark.circle")
                }
                .accessibilityIdentifier("bodyMapSelectToggle")
            }
        }
        // `.safeAreaInset` stacks bottom-up in application order: the LAST
        // one applied claims the outermost slot, right at the screen edge —
        // exactly the 80pt zone the real floating `CustomTabBar` overlay
        // occupies. `PickingBar` must be applied BEFORE
        // `.floatingTabBarClearance()` so it lands just above that reserved
        // zone instead of underneath the tab bar (where its taps would be
        // swallowed by the tab bar sitting on top of it).
        .safeAreaInset(edge: .bottom) {
            if pickingSession.isActive {
                PickingBar(originTab: 1) // Body tab
            }
        }
        .floatingTabBarClearance()
        .navigationDestination(isPresented: isShowingDetail) {
            if let selectedExercise {
                ExerciseDetailView(exercise: selectedExercise)
            }
        }
    }

    @ViewBuilder
    private func exerciseSection(title: String, footer: String? = nil, exercises: [Exercise]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.luminaLabel)
                .foregroundStyle(Color.luminaOnSurfaceVariant)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(exercises, id: \.uuid) { exercise in
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
            }

            if let footer {
                Text(footer)
                    .font(.luminaCaption)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
            }
        }
    }

    // A single tapped region is named directly ("Spinal Erectors") rather
    // than lumped into generic "this area" copy, so a specific muscle/joint
    // reads as its own distinct thing even when it has no exercises of its
    // own yet and is falling back to a nearby one's stretches.
    private var relatedSectionTitle: String {
        bodyParts.count == 1 ? "Related to \(bodyParts[0])" : "More from this area"
    }

    private var relatedFooterText: String {
        guard bodyParts.count == 1 else {
            return resolver.direct.isEmpty
                ? "No exercises target this exact spot yet — here are related ones for the same area."
                : "Other exercises that work the same area."
        }
        return resolver.direct.isEmpty
            ? "No exercises target \(bodyParts[0]) directly yet — here are ones for nearby muscles."
            : "Other exercises that work near \(bodyParts[0])."
    }

    private var emptyDescription: String {
        bodyParts.count == 1
            ? "No exercises target \(bodyParts[0]) yet."
            : "No exercises target the marked areas yet."
    }
}
