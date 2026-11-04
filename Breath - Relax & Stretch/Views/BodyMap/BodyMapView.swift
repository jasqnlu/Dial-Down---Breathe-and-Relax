import SwiftUI
import SwiftData

// MARK: - BodyMapView
//
// One freely-rotatable 3D body, one way in. A tap turns the body to face the
// tapped point and drills straight into the muscle picker — camera to the
// dot, skin fades, ≤4 candidate muscles. Tapping off the picker (missing the
// body) collapses it back to the zoomed region view — dot, bar, no picker —
// rather than fully resetting; tapping outside the body from THAT resting
// state (or from full rest) zooms back out to fit the whole body on screen.
// No modes, no sensation colours, no checkmark; see
// docs/superpowers/specs/2026-08-30-bodymap-tap-to-stretch-design.md (gesture
// roles have since swapped — single tap now does what double tap describes
// there).
//
// Hit-testing raycasts the skin mesh and resolves the point in pure Swift
// (MuscleHitResolver), so rotation stays free at all times.

struct BodyMapView: View {
    @EnvironmentObject private var tourCoordinator: TourCoordinator
    @State private var facing: BodyFacing = .front

    /// The current single-tap selection. Drives the dot, the region
    /// highlight and the action bar. Nil means nothing is selected.
    @State private var selection: RegionSelection?

    // MARK: - Muscle-picker state
    @State private var disambiguationCandidates: [MarkCandidate] = []
    /// The tapped dot the camera zooms onto — kept alive across navigation so
    /// Back returns to the same zoomed framing.
    @State private var focusPoint: SIMD3<Float>?
    /// The currently highlighted candidate (its region box brightened).
    @State private var focusedRegion: String?
    /// One `item`-driven destination for every push, rather than several
    /// `isPresented:` modifiers racing over the same stack.
    @State private var exercisesRoute: ExercisesRoute?
    /// Bumped when the exercise list is popped, to nudge BodySceneView to
    /// re-apply the zoom and re-project labels (the covered SCNView goes stale).
    @State private var refocusToken = 0

    private struct RegionSelection: Equatable {
        let region: String
        let point: SIMD3<Float>
    }

    private struct ExercisesRoute: Identifiable, Hashable {
        let region: String
        var id: String { region }
    }

    private let impact = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Top bar ──────────────────────────────────────────────────
                HStack(spacing: 8) {
                    if isDisambiguating {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Which area did you mean?")
                                .font(.luminaCardTitle)
                                .foregroundStyle(Color.luminaOnSurface)
                            Text("Tap a muscle, then tap it again for stretches")
                                .font(.luminaCaption)
                                .foregroundStyle(Color.luminaOnSurfaceVariant)
                        }
                        Spacer(minLength: 0)
                        Button(role: .cancel) { cancelDisambiguation() } label: {
                            Text("Cancel")
                                .font(.luminaLabel)
                                .foregroundStyle(Color.luminaOnSurface)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(Color.luminaContainer, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Spacer(minLength: 0)
                        facingToggleButton
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // ── The body ─────────────────────────────────────────────────
                BodySceneView(facing: facing,
                              style: .anatomy,
                              selectionPoint: selection?.point,
                              onRegionDrilled: handleRegionDrilled,
                              onBackgroundTap: handleOutsideTap,
                              disambiguationCandidates: disambiguationCandidates,
                              focusPoint: focusPoint,
                              focusedRegion: focusedRegion,
                              onCandidateFocused: handleCandidateFocused,
                              onCandidateSelected: handleCandidateSelected,
                              refocusToken: refocusToken)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tourAnchor("bodymap.tapRegion")

                // ── Bottom bar ───────────────────────────────────────────────
                if let selection, !isDisambiguating {
                    RegionActionBar(regionName: selection.region) {
                        exercisesRoute = ExercisesRoute(region: selection.region)
                        tourCoordinator.notifyInteraction(id: "bodymap.findStretches")
                    }
                    .tourAnchor("bodymap.findStretches")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(Color.luminaSurface.ignoresSafeArea())
            .floatingTabBarClearance()
            .navigationTitle("Body Map")
            .navigationBarTitleDisplayMode(.inline)
            .animation(.easeInOut(duration: 0.2), value: selection)
            .navigationDestination(item: $exercisesRoute) { route in
                BodyPartExercisesView(bodyPart: route.region)
            }
            .onChange(of: exercisesRoute) { oldValue, newValue in
                // Popped back to the zoom — re-drive the scene so the body
                // re-renders and the labels re-project.
                if oldValue != nil, newValue == nil, !disambiguationCandidates.isEmpty {
                    refocusToken += 1
                }
            }
            .onAppear { impact.prepare() }
        }
    }

    private var isDisambiguating: Bool { !disambiguationCandidates.isEmpty }

    private func clearSelection() {
        withAnimation(.easeInOut(duration: 0.18)) {
            selection = nil
            focusPoint = nil
        }
    }

    // MARK: - Tap → muscle picker

    /// Surfaces the muscle groups plausibly meant by the tap
    /// (`MuscleHitResolver.candidates`) as labeled pins — the point is to let
    /// the user disambiguate *which* muscle they mean before seeing
    /// exercises. Only if no hit volume resolves at all do we fall back to
    /// navigating straight to the tapped region. The body has already
    /// rotated to face the point by the time this fires — BodySceneView owns
    /// the rig, so it does the turn itself.
    private func handleRegionDrilled(region: String, point: SIMD3<Float>) {
        impact.impactOccurred()
        // The head fans out into fixed, evidence-based face zones with
        // hand-tuned anchors instead of geometric hit-box candidates. Side is
        // inferred from the tapped x (see HeadZones).
        if region == "Head" {
            let pins = HeadZones.candidates(forTapAt: point)
            selection = RegionSelection(region: region, point: point)
            focusPoint = point
            focusedRegion = pins.first?.name
            disambiguationCandidates = pins
            tourCoordinator.notifyInteraction(id: "bodymap.tapRegion")
            return
        }
        // Pull a few extra candidates so that, after dropping any parent group
        // whose heads are already present, we still have a full set of ≤4.
        let raw = MuscleHitResolver.candidates(near: point,
                                               in: BodyHitVolumes.all, maxCandidates: 6)
        let presentParents = Set(raw.compactMap { MuscleGroup.parentOfHead($0) })
        let candidates = raw.filter { !presentParents.contains($0) }.prefix(4)
        let volumesByName = Dictionary(uniqueKeysWithValues: BodyHitVolumes.all.map { ($0.name, $0) })
        let pins = candidates.compactMap { name in
            volumesByName[name].map {
                MarkCandidate(name: name, point: $0.center,
                              minBound: $0.minBound, maxBound: $0.maxBound)
            }
        }
        // Currently unreachable, kept as a defensive guard: `resolveRegion`
        // only ever produces a region here via `MuscleHitResolver.regionName`,
        // whose nearest-centre fallback returns non-nil for any point given a
        // non-empty volume set; `candidates` shares that same fallback via
        // `primaryVolume`, so `raw` always contains at least `primary.name`,
        // which is guaranteed present in `volumesByName`. The parent-drop
        // filter above can only remove a name that is the parent of a head
        // also in `raw`, and a head is never its own parent, so it can't
        // empty the list either. `pins` is therefore never empty in practice.
        if pins.isEmpty {
            exercisesRoute = ExercisesRoute(region: region)
        } else {
            // Zoom onto the actual tapped dot (not a candidate centre) and
            // auto-highlight the primary candidate.
            selection = RegionSelection(region: region, point: point)
            focusPoint = point
            focusedRegion = pins.first?.name
            disambiguationCandidates = pins
            tourCoordinator.notifyInteraction(id: "bodymap.tapRegion")
        }
    }

    /// First tap on a candidate (region box or side label) highlights it.
    private func handleCandidateFocused(_ region: String) {
        withAnimation(.easeInOut(duration: 0.15)) { focusedRegion = region }
        impact.impactOccurred()
    }

    /// Second tap on the focused candidate → drill into its exercises. The
    /// zoom/candidate/focus state is deliberately KEPT alive so pressing Back
    /// returns to the zoomed dot; only Cancel (or an outside tap) tears down
    /// the candidates, and even then the zoom itself survives.
    private func handleCandidateSelected(_ region: String) {
        exercisesRoute = ExercisesRoute(region: region)
        tourCoordinator.notifyInteraction(id: "bodymap.findStretches")
    }

    /// Tapping off the picker means "not that one" rather than "never mind"
    /// — it closes the picker but keeps `selection`/`focusPoint`, landing
    /// back on the zoomed region view (dot + "Stretches for…" bar) instead
    /// of resetting all the way out. Shared by the Cancel button and a
    /// background tap while disambiguating (`handleOutsideTap` below).
    private func cancelDisambiguation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            disambiguationCandidates = []
            focusedRegion = nil
        }
    }

    /// A tap that misses the body — fires in EVERY state (idle, zoomed
    /// region, or the muscle picker), and `BodySceneView.handleOutsideTap`
    /// always shows the whole body again when nothing is focused (an "undo
    /// my pinch" gesture that works even fully at rest). This additionally
    /// backs out whatever's up here, one level at a time:
    /// - Muscle picker open → `cancelDisambiguation` closes it but keeps the
    ///   zoom, so the NEXT outside tap is the one that resets the camera
    ///   (`BodySceneView`'s `disambiguationCandidates` `onChange` leaves the
    ///   camera alone while `focusPoint` stays set).
    /// - Zoomed region selected, no picker → `clearSelection` drops
    ///   `focusPoint` too, so this tap's camera-reset (in `BodySceneView`)
    ///   actually takes effect.
    /// - Fully at rest (nothing selected) → nothing to clear here; the zoom
    ///   reset in `BodySceneView` is the whole point.
    private func handleOutsideTap() {
        if isDisambiguating {
            cancelDisambiguation()
        } else if selection != nil {
            clearSelection()
        }
    }

    // MARK: - Facing control

    // Not a multi-option picker — a single toggle between Front/Back — so it
    // keeps its directional icon, restyled with the same chip tokens
    // (unselected LuminaChip look) rather than wrapped in LuminaChip itself
    // (which is text-only). Still worth keeping alongside tap-to-face: there
    // is nothing to tap on the side you can't see.
    private var facingToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.28)) {
                facing = facing == .front ? .back : .front
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10, weight: .medium))
                Text(facing.rawValue)
                    .font(.luminaLabel)
            }
            .foregroundStyle(Color.luminaOnSurfaceVariant)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color.luminaContainer, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Toggle body facing — currently \(facing.rawValue)")
    }
}

// MARK: - Preview

#Preview {
    BodyMapView()
        .modelContainer(for: Exercise.self, inMemory: true)
}
