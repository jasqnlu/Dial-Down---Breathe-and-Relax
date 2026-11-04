import SwiftUI

// MARK: - RoadmapWaveGeometry
//
// Pure math — a session's exercises laid out as evenly-spaced nodes on a
// cosine curve. Spacing is fixed (never "fit everything to the available
// width"): this is what makes exercise 1 land at the same leading-edge
// position whether the session has 4 exercises or 40, and lets a long
// routine scroll instead of compressing into illegible, overlapping nodes.
enum RoadmapWaveGeometry {
    static let nodeSpacing: CGFloat = 62
    static let amplitude: CGFloat = 24
    /// Fallback padding for a zero/near-zero viewport width — see
    /// `viewportPadding(visibleWidth:)`. Real layouts use the
    /// viewport-derived padding, which every `padding:`-taking function
    /// below takes as an explicit parameter rather than baking in.
    static let leadingPadding: CGFloat = 24
    static let minNodeSize: CGFloat = 36
    static let maxNodeSize: CGFloat = 58

    /// Total scrollable content width: symmetric `padding` on both sides so
    /// node 0 and the last node can each reach the viewport center.
    static func totalWidth(count: Int, padding: CGFloat) -> CGFloat {
        let base = padding * 2
        guard count > 1 else { return base }
        return base + nodeSpacing * CGFloat(count - 1)
    }

    static func x(at index: Int, padding: CGFloat) -> CGFloat {
        x(atContinuous: CGFloat(index), padding: padding)
    }

    static func x(atContinuous t: CGFloat, padding: CGFloat) -> CGFloat {
        padding + nodeSpacing * t
    }

    static func y(at index: Int, midY: CGFloat) -> CGFloat {
        midY - amplitude * cos(CGFloat(index) * .pi)
    }

    static func y(atContinuous t: CGFloat, midY: CGFloat) -> CGFloat {
        midY - amplitude * cos(t * .pi)
    }

    static func nodeSize(forDuration duration: Int, in durations: [Int]) -> CGFloat {
        guard let minD = durations.min(), let maxD = durations.max(), maxD > minD else {
            return (minNodeSize + maxNodeSize) / 2
        }
        let fraction = CGFloat(duration - minD) / CGFloat(maxD - minD)
        return minNodeSize + fraction * (maxNodeSize - minNodeSize)
    }

    // MARK: - Carousel focus falloff
    //
    // Pure functions of pixel distance from the viewport's horizontal
    // center to whichever node/curve-segment is being styled. Ported 1:1
    // from the interactive HTML mockup reviewed before this shipped (see
    // docs/superpowers/specs/2026-08-14-roadmap-carousel-exercise-picking-design.md)
    // so the tuning here is deliberate, not arbitrary: the node's transform
    // pivots near its duration label (RoadmapWave applies the scale with a
    // bottom-weighted anchor), so distance-based growth pushes the glyph
    // upward into headroom instead of the label into the container edge.

    /// Leading/trailing padding needed so node 0 and the last node can each
    /// reach the *center* of the viewport, not just its leading edge —
    /// unlike `nodeSpacing`, this is legitimately viewport-dependent (the
    /// "never fit to available width" invariant above is about spacing,
    /// not padding). Falls back to the fixed `leadingPadding` for a
    /// zero/near-zero width (e.g. a first layout pass before geometry is
    /// known), so a node is never pushed off both edges at once.
    static func viewportPadding(visibleWidth: CGFloat) -> CGFloat {
        let half = visibleWidth / 2
        return half > leadingPadding ? half : leadingPadding
    }

    /// The settled content-offset a scroll should snap to, given whatever
    /// offset the deceleration would otherwise land on.
    ///
    /// Node *i* sits at content-x `x(at: i, padding:)`, and is centered in
    /// the viewport when the content offset equals
    /// `x(at: i, padding:) - containerWidth / 2`. So the lattice of valid
    /// resting offsets is anchored at `padding - containerWidth / 2` (the
    /// offset that centers node 0 — ≈ 0 once real geometry is known, since
    /// `padding ≈ containerWidth / 2`), *not* at `padding`: anchoring at
    /// `padding` shifts every interior stop by `padding mod nodeSpacing`
    /// (~25pt on a 321pt viewport) while the clamped first/last pages still
    /// look correct, which is exactly how that bug hid.
    static func snappedContentOffset(proposed: CGFloat, padding: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let origin = padding - containerWidth / 2
        let steps = ((proposed - origin) / nodeSpacing).rounded()
        return max(0, origin + steps * nodeSpacing)
    }

    // MARK: - Headroom for the focused node
    //
    // The focused node is scaled to `focusScale(distance: 0)` about
    // `focusAnchorY` (bottom-weighted, so growth goes up into headroom
    // rather than down through the container's bottom edge — see
    // RoadmapWave.nodeView). That growth still has to *fit*: without
    // reserving space for it, the fully-scaled node — which on a crest
    // (even indices, including node 0) already sits `amplitude` above the
    // curve's midline — is clipped flat by the ScrollView's own frame.

    static let focusAnchorY: CGFloat = 0.84
    static let nodeStackSpacing: CGFloat = 8
    static let orderBadgeSize: CGFloat = 15
    static let durationLabelHeight: CGFloat = 16

    /// Height of a node's label stack at its largest (badge + glyph +
    /// duration label), i.e. the worst case the container has to fit.
    static func nodeStackHeight(numbered: Bool) -> CGFloat {
        (numbered ? orderBadgeSize + nodeStackSpacing : 0)
            + maxNodeSize + nodeStackSpacing + durationLabelHeight
    }

    /// How far the focused node's stack reaches above its own center point
    /// once scaled. The stack is centered on the node, so its top starts at
    /// `h/2` above center and the anchor sits `(focusAnchorY - 0.5) * h`
    /// below center; scaling multiplies the anchor→top distance.
    static func focusTopExtent(numbered: Bool) -> CGFloat {
        let h = nodeStackHeight(numbered: numbered)
        return focusAnchorY * h * focusScale(distance: 0) - (focusAnchorY - 0.5) * h
    }

    /// The mirror of `focusTopExtent` below the node's center.
    static func focusBottomExtent(numbered: Bool) -> CGFloat {
        let h = nodeStackHeight(numbered: numbered)
        return (1 - focusAnchorY) * h * focusScale(distance: 0) + (focusAnchorY - 0.5) * h
    }

    static func focusScale(distance: CGFloat) -> CGFloat {
        max(0.48, 1.62 - (distance / nodeSpacing) * 0.85)
    }

    static func focusOpacity(distance: CGFloat) -> CGFloat {
        max(0.26, 1 - (distance / nodeSpacing) * 0.62)
    }

    static func focusBlur(distance: CGFloat) -> CGFloat {
        min(2.1, max(0, (distance / nodeSpacing - 0.3) * 1.7))
    }

    /// Numbered-variant order badge: a continuous 0…1 ramp on the node's
    /// focus scale, so the badge fades rather than popping.
    ///
    /// The ramp starts below the scale of an immediate neighbour
    /// (`focusScale(distance: nodeSpacing)` ≈ 0.77) on purpose: the whole
    /// point of the numbered variant is reading exercise *order*, so the
    /// nodes either side of the focused one keep a faint but present
    /// number, and only nodes two or more spacings out fade to nothing.
    static func badgeOpacity(scale: CGFloat) -> CGFloat {
        min(1, max(0, (scale - 0.62) / 0.5))
    }

    static func segmentStrokeWidth(distance: CGFloat) -> CGFloat {
        max(0.8, 5.8 - (distance / nodeSpacing) * 3.1)
    }

    static func segmentOpacity(distance: CGFloat) -> CGFloat {
        max(0.24, 1 - (distance / nodeSpacing) * 0.58)
    }

    static func segmentBlur(distance: CGFloat) -> CGFloat {
        min(1.8, max(0, (distance / nodeSpacing - 0.4) * 1.5))
    }
}

// MARK: - RoadmapWaveCurve
//
// One Canvas-drawn path segment per inter-node span (not one continuous
// Path for the whole timeline) so each span's stroke-width/opacity/blur can
// be pushed toward `focusCenterX` independently — this, paired with the
// node-level falloff in RoadmapWave's ForEach below, is what reads as the
// camera zooming into a specific point on the curve rather than just that
// point's icon growing while a flat, uniformly-styled line sits under it.
struct RoadmapWaveCurve: View {
    let count: Int
    let midY: CGFloat
    /// The x-coordinate, in this curve's own (unscrolled content)
    /// coordinate space, currently centered in the viewport.
    let focusCenterX: CGFloat
    /// Leading offset for node 0, matching RoadmapWave's own viewport-
    /// dependent `padding` (RoadmapWaveGeometry.viewportPadding). Passed
    /// straight through to `RoadmapWaveGeometry.x(atContinuous:padding:)`
    /// so this curve places its points on exactly the same lattice the
    /// nodes use.
    let padding: CGFloat

    var body: some View {
        Canvas { context, _ in
            guard count > 1 else { return }
            let stepsPerSegment = 16
            // Color now lives on the nodes (see nodeView), not the
            // connecting line — a neutral gradient here keeps the curve
            // from competing with each node's category color.
            let gradient = Gradient(colors: [Color.luminaOnSurface.opacity(0.35), Color.luminaOnSurface.opacity(0.15)])

            for segment in 0..<(count - 1) {
                var path = Path()
                for step in 0...stepsPerSegment {
                    let t = CGFloat(segment) + CGFloat(step) / CGFloat(stepsPerSegment)
                    let point = CGPoint(
                        x: RoadmapWaveGeometry.x(atContinuous: t, padding: padding),
                        y: RoadmapWaveGeometry.y(atContinuous: t, midY: midY)
                    )
                    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }

                let midX = RoadmapWaveGeometry.x(atContinuous: CGFloat(segment) + 0.5, padding: padding)
                let distance = abs(midX - focusCenterX)
                let width = RoadmapWaveGeometry.segmentStrokeWidth(distance: distance)
                let opacity = RoadmapWaveGeometry.segmentOpacity(distance: distance)
                let blur = RoadmapWaveGeometry.segmentBlur(distance: distance)

                context.drawLayer { layer in
                    if blur > 0.01 { layer.addFilter(.blur(radius: blur)) }
                    layer.opacity = opacity
                    layer.stroke(
                        path,
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: RoadmapWaveGeometry.x(at: 0, padding: padding), y: midY),
                            endPoint: CGPoint(x: RoadmapWaveGeometry.x(at: count - 1, padding: padding), y: midY)
                        ),
                        style: StrokeStyle(lineWidth: width, lineCap: .round)
                    )
                }
            }
        }
    }
}

// MARK: - RoadmapWave
//
// A session's exercises as duration-sized PoseGlyphIcon nodes on a
// continuous curve, paging one exercise at a time in a horizontal
// ScrollView: the centered node and the curve segment under it read as
// zoomed in (larger, sharper, brighter), while neighbors recede (smaller,
// blurred, dimmed toward a vignette). Node 0 always renders first (an
// un-scrolled ScrollView shows its content's leading edge first in LTR
// layouts), and the user pages right to bring each subsequent exercise
// into focus. Spacing between nodes is fixed regardless of exercise count
// (RoadmapWaveGeometry.nodeSpacing) — only the leading/trailing padding is
// viewport-dependent, so node 0 and the last node can each reach dead
// center. Stays PoseGlyphIcon-only by design: this is compact wayfinding,
// not the primary browsing surface, so it's exempt from the general
// animation-vs-glyph size rule (see ExerciseArt, Task 6).
struct RoadmapWave: View {
    let exercises: [Exercise]
    var numbered: Bool = false
    /// Per-exercise duration overrides, keyed by exercise UUID — absent key
    /// means "use the exercise's own durationSeconds." Threaded through so
    /// node sizing and each node's duration label reflect a customized
    /// (e.g. shortened) duration instead of always showing the catalog
    /// default, wherever this is shown alongside CustomizeRoutineView's own
    /// duration stepper.
    var durationOverrides: [UUID: Int] = [:]

    /// Continuous horizontal content-offset, read every scroll frame via
    /// `.onScrollGeometryChange` — not just the settled post-snap position
    /// — because the "glide" the carousel needs (nodes/curve scaling
    /// *during* the drag, not only once it stops) needs per-frame position.
    @State private var contentOffsetX: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    /// Curve midline: one full amplitude (so crest nodes clear it) plus the
    /// space the focused node needs *above* its own center once scaled.
    private var midY: CGFloat {
        RoadmapWaveGeometry.amplitude + RoadmapWaveGeometry.focusTopExtent(numbered: numbered)
    }

    private var contentHeight: CGFloat {
        midY + RoadmapWaveGeometry.amplitude + RoadmapWaveGeometry.focusBottomExtent(numbered: numbered)
    }

    /// The exercise's duration after applying `durationOverrides`, if any —
    /// mirrors the identically named helper in CustomizeRoutineView /
    /// SessionPlayerView / RoutineBuilderView.
    private func duration(for exercise: Exercise) -> Int {
        durationOverrides[exercise.uuid] ?? exercise.durationSeconds
    }

    private var durations: [Int] { exercises.map(duration(for:)) }

    private var padding: CGFloat {
        RoadmapWaveGeometry.viewportPadding(visibleWidth: viewportWidth)
    }

    private var totalWidth: CGFloat {
        RoadmapWaveGeometry.totalWidth(count: exercises.count, padding: padding)
    }

    /// The x-coordinate (in content space) currently centered in the
    /// viewport — what every node/curve-segment measures its distance from.
    private var focusCenterX: CGFloat {
        contentOffsetX + viewportWidth / 2
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                RoadmapWaveCurve(count: exercises.count, midY: midY, focusCenterX: focusCenterX, padding: padding)

                ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                    nodeView(index: index, exercise: exercise)
                }
            }
            .frame(width: totalWidth, height: contentHeight)
        }
        .frame(height: contentHeight)
        .scrollTargetBehavior(RoadmapPagingBehavior(padding: padding))
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, newOffset in
            contentOffsetX = newOffset
        }
        .background {
            GeometryReader { geo in
                // Behind the scrolling content, so the glow reads as light
                // *behind* the focused node's glyph rather than a wash over
                // it. Fixed to the viewport, like the vignette.
                focusGlow
                    // Smooths the glow's color transition when the focused
                    // node changes category — without this, the color
                    // snapped instantly at the moment focus crossed from one
                    // exercise to the next instead of crossfading.
                    .animation(.easeInOut(duration: 0.25), value: focusedCategoryColor)
                    .onAppear { viewportWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newWidth in viewportWidth = newWidth }
            }
        }
        .overlay { carouselVignette }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Mirrors `Exercise.durationFormatted`'s "m:ss" formatting, but reads
    /// the overridden duration rather than always the catalog default.
    private func durationFormatted(for exercise: Exercise) -> String {
        let seconds = duration(for: exercise)
        let m = seconds / 60, s = seconds % 60
        return s == 0 ? "\(m):00" : "\(m):\(String(format: "%02d", s))"
    }

    @ViewBuilder
    private func nodeView(index: Int, exercise: Exercise) -> some View {
        let category = ExerciseCategory.primary(for: exercise.targetBodyParts)
        let size = RoadmapWaveGeometry.nodeSize(forDuration: duration(for: exercise), in: durations)
        let x = RoadmapWaveGeometry.x(at: index, padding: padding)
        let y = RoadmapWaveGeometry.y(at: index, midY: midY)
        let distance = abs(x - focusCenterX)
        let scale = RoadmapWaveGeometry.focusScale(distance: distance)
        let opacity = RoadmapWaveGeometry.focusOpacity(distance: distance)
        let blur = RoadmapWaveGeometry.focusBlur(distance: distance)

        VStack(spacing: RoadmapWaveGeometry.nodeStackSpacing) {
            if numbered {
                Text("\(index + 1)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: RoadmapWaveGeometry.orderBadgeSize, height: RoadmapWaveGeometry.orderBadgeSize)
                    .background(category.accentColor, in: Circle())
                    // Continuous ramp, not a binary cut: the badge fades in
                    // smoothly as a node approaches focus (and stays legible
                    // on the near neighbours, which matters on the numbered
                    // variant whose whole job is showing exercise order)
                    // instead of popping on for exactly one node mid-drag.
                    .opacity(RoadmapWaveGeometry.badgeOpacity(scale: scale))
            }
            PoseGlyphIcon(exercise: exercise, category: category, size: size)
            // A fixed dark scrim behind the label (rather than
            // luminaOnSurfaceVariant straight on the background) so it stays
            // legible at a fixed contrast regardless of what's behind it —
            // TodayView's glass hero card in particular, where plain text
            // was hard to read wherever the halo/vignette didn't happen to
            // darken it.
            Text(durationFormatted(for: exercise))
                .font(.luminaCaption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.luminaOnSurface)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.luminaSurface.opacity(0.85), in: Capsule())
        }
        // Pivoting near the bottom of the stack (by the duration label)
        // rather than dead-center means scaling up pushes the glyph
        // further UP into open headroom above the curve, and leaves the
        // duration label roughly anchored — nodes on the low side of the
        // curve (odd indices, per RoadmapWaveGeometry.y) no longer grow
        // downward into the container edge as they scale up. The container
        // reserves matching space for that growth via
        // RoadmapWaveGeometry.focusTopExtent/focusBottomExtent.
        .scaleEffect(scale, anchor: UnitPoint(x: 0.5, y: RoadmapWaveGeometry.focusAnchorY))
        .opacity(opacity)
        .blur(radius: blur)
        .position(x: x, y: y)
        .zIndex(Double(scale))
    }

    /// The category color of whichever exercise is nearest the viewport
    /// center right now — feeds `focusGlow` so the ambient glow always
    /// matches the category color of the node it's actually glowing
    /// behind, instead of a fixed color regardless of which node is
    /// focused.
    private var focusedCategoryColor: Color {
        guard !exercises.isEmpty else { return .luminaPrimary }
        let nearestIndex = exercises.indices.min { lhs, rhs in
            let lhsDistance = abs(RoadmapWaveGeometry.x(at: lhs, padding: padding) - focusCenterX)
            let rhsDistance = abs(RoadmapWaveGeometry.x(at: rhs, padding: padding) - focusCenterX)
            return lhsDistance < rhsDistance
        }!
        return ExerciseCategory.primary(for: exercises[nearestIndex].targetBodyParts).accentColor
    }

    /// A soft halo behind whichever node is centered (the spec's "soft glow
    /// behind the centered node", distinct from the page-wide vignette).
    /// Centered on the viewport center — the same point the vignette is
    /// centered on, and where the focused node always renders. Kept subtle
    /// (low opacity, no hard-edged clear stop) so it reads as the same
    /// glass surface catching a bit of color, not a separate colored patch
    /// sitting on top of the hero card.
    private var focusGlow: some View {
        let color = focusedCategoryColor
        return RadialGradient(
            gradient: Gradient(colors: [
                color.opacity(0.14),
                color.opacity(0.05),
                Color.clear,
            ]),
            center: .center,
            startRadius: 0,
            endRadius: RoadmapWaveGeometry.maxNodeSize * 1.3
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var carouselVignette: some View {
        // Fixed over the viewport (this overlay does not scroll with the
        // content) — stays clear near center, dims toward the edges, like
        // looking through a lens centered on whichever node is focused.
        //
        // Deliberately a neutral multiply rather than a fade to an absolute
        // colour: this renders over both a plain `luminaSurface` background
        // (CustomizeRoutineView) and TodayView's glass hero card, and any
        // fixed colour that suits one paints an obviously wrong haze over
        // the other. Multiplying black-at-opacity just darkens whatever is
        // actually behind it.
        RadialGradient(
            gradient: Gradient(colors: [
                Color.clear,
                Color.clear,
                Color.black.opacity(0.10),
            ]),
            center: .center,
            startRadius: 10,
            endRadius: max(viewportWidth, 1) * 0.62
        )
        .blendMode(.multiply)
        .allowsHitTesting(false)
    }

    private var accessibilityLabel: String {
        guard !exercises.isEmpty else { return "No exercises" }
        let items = exercises.map { "\($0.name), \(durationFormatted(for: $0))" }.joined(separator: "; ")
        return "\(exercises.count) exercise\(exercises.count == 1 ? "" : "s"): \(items)"
    }
}

// MARK: - RoadmapPagingBehavior
//
// `.scrollTargetBehavior(.paging)` snaps to multiples of the *container*
// width — the wrong fit here, since RoadmapWaveGeometry.nodeSpacing is a
// fixed constant independent of container width. This snaps to the
// nearest node-*centering* offset instead (see
// RoadmapWaveGeometry.snappedContentOffset, where the actual math lives so
// it can be unit-tested), so a node always lands centered in the viewport
// regardless of how wide that viewport is.
private struct RoadmapPagingBehavior: ScrollTargetBehavior {
    let padding: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        target.rect.origin.x = RoadmapWaveGeometry.snappedContentOffset(
            proposed: target.rect.minX,
            padding: padding,
            containerWidth: context.containerSize.width
        )
    }
}
