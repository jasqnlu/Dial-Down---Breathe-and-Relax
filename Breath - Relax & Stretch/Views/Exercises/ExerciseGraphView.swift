import SwiftUI

// MARK: - Exercise Graph View
//
// Pinch-zoom node graph: 8 category circles arranged on a ring; pinching in
// near one focuses it, fading in grouped exercise satellites around it.
// Mirrors the zoom/pan gesture pattern already used by BodyMapView.

struct ExerciseGraphView: View {
    let exercises: [Exercise]
    let typeFilter: ExerciseType?
    let onSelect: (Exercise) -> Void

    @State private var zoomScale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var lastPan: CGSize = .zero
    @State private var focusedCategory: ExerciseCategory?
    @State private var selectedGroup: SelectedExerciseGraphGroup?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let minZoom: CGFloat = 0.85
    private let maxZoom: CGFloat = 3.2
    private let focusThreshold: CGFloat = 1.45
    private let categoryRadius: CGFloat = 0.70      // normalised distance from canvas center

    /// Focus/zoom transitions use a springy bounce for polish; under Reduce
    /// Motion that overshoot is dropped in favor of a short, direct ease so
    /// the pan/zoom position still updates (that's the functional part) but
    /// without the bouncy bloom.
    private var graphAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.86)
    }

    private var filteredExercises: [Exercise] {
        guard let typeFilter else { return exercises }
        return exercises.filter { $0.type == typeFilter }
    }

    private func exercises(in category: ExerciseCategory) -> [Exercise] {
        filteredExercises.filter { ExerciseCategory.categories(for: $0.targetBodyParts).contains(category) }
    }

    private var visibleCategories: [ExerciseCategory] {
        ExerciseCategory.allCases.filter { !exercises(in: $0).isEmpty }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let scale = min(size.width, size.height) / 2
            let categories = visibleCategories

            ZStack(alignment: .topTrailing) {
                ZStack {
                    // Background gesture-catcher, BEHIND the nodes: it carries
                    // the rectangular hit area the pan/pinch gestures need, so
                    // the container itself no longer claims a full-rectangle hit
                    // shape. Previously `.contentShape(Rectangle())` on the
                    // container routed every in-bounds tap to the container's
                    // gesture recognizers, so taps never reached the satellite
                    // group Buttons drawn within it (the General Chest bug).
                    Rectangle()
                        .fill(Color.luminaSurface.opacity(0.001))
                        .contentShape(Rectangle())
                        // Double-tap-to-reset lives HERE, on the background,
                        // rather than on the whole container. As a container
                        // gesture its double-tap recognizer competed with — and
                        // swallowed — single taps on the satellite group Buttons
                        // (the General Chest bug). Scoped to empty space, it no
                        // longer touches node taps; the reset button in
                        // zoomControls covers taps that land on a node.
                        .gesture(resetGesture)

                    ForEach(Array(categories.enumerated()), id: \.element) { pair in
                        categoryLayer(pair: pair, categories: categories, center: center, scale: scale)
                    }
                }
                .frame(width: size.width, height: size.height)
                .scaleEffect(zoomScale, anchor: .center)
                .offset(panOffset)
                .gesture(magnifyGesture(center: center, scale: scale))
                .simultaneousGesture(panGesture)
                .animation(graphAnimation, value: focusedCategory)

                zoomControls
            }
        }
        .navigationDestination(item: $selectedGroup) { selected in
            ExerciseGroupCorpusSheet(selected: selected) { exercise in
                selectedGroup = nil
                onSelect(exercise)
            }
        }
        // Category/satellite node labels are sized in fixed points to fit
        // inside circles whose diameters come from GraphLayout's normalised
        // canvas math, not from the type system. Letting Dynamic Type grow
        // this text would overflow those circles well before it became more
        // legible, so the diagram itself is pinned to the standard size;
        // the pushed screen it presents (a grid) scales normally.
        .dynamicTypeSize(.large)
    }

    @ViewBuilder
    private func categoryLayer(pair: (offset: Int, element: ExerciseCategory),
                                categories: [ExerciseCategory],
                                center: CGPoint, scale: CGFloat) -> some View {
        let index = pair.offset
        let category = pair.element
        let normalized = GraphLayout.categoryPosition(index: index, count: categories.count)
        let isFocused = focusedCategory == category
        let categoryExercises = exercises(in: category)
        let shouldShowCategoryLayer = focusedCategory == nil || isFocused

        if shouldShowCategoryLayer {
            let groups = ExerciseGraphGrouping.groups(for: categoryExercises, in: category)
            let categoryCenter = CGPoint(x: normalized.x * categoryRadius, y: normalized.y * categoryRadius)
            let ringConfiguration = GraphLayout.exerciseSatelliteRingConfiguration(
                for: groups.count,
                isFocused: isFocused
            )
            let positions = GraphLayout.ringPositions(count: groups.count,
                                                        around: categoryCenter,
                                                        baseRadius: ringConfiguration.baseRadius,
                                                        ringSpacing: ringConfiguration.ringSpacing,
                                                        perRing: ringConfiguration.perRing)
            let labelOpacity = GraphLayout.labelOpacity(zoomScale: zoomScale, isFocused: isFocused)

            // Draw the category node FIRST (underneath) so the group satellites
            // that follow sit on top of it and win hit-testing. Previously the
            // category node was drawn last: its `.position`-expanded tap target
            // covered the whole canvas and swallowed every satellite tap, so a
            // focused group like "General Chest" opened nothing.
            CategoryNode(category: category, count: categoryExercises.count, isFocused: isFocused)
                .contentShape(Circle())
                .accessibilityIdentifier("exerciseCategoryNode")
                .onTapGesture { focus(on: category, index: index, categories: categories, center: center, scale: scale) }
                .position(x: center.x + normalized.x * scale * categoryRadius,
                          y: center.y + normalized.y * scale * categoryRadius)

            ForEach(Array(zip(groups, positions).enumerated()), id: \.offset) { pair in
                let group = pair.element.0
                let exNormalized = pair.element.1
                // A Button, not `.onTapGesture`: inside this pinch/pan/double-tap
                // canvas the satellites' tap gestures arbitrated unreliably
                // against the container's simultaneous drag. Button hit-testing
                // wins that arbitration; drawn last, it also sits on top.
                Button {
                    selectedGroup = SelectedExerciseGraphGroup(category: category, group: group)
                } label: {
                    ExerciseGroupNode(
                        group: group,
                        color: category.pastel,
                        isFocused: isFocused,
                        labelOpacity: labelOpacity
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .accessibilityIdentifier("exerciseGroupNode")
                // `.disabled(!isFocused)` rather than `.allowsHitTesting`: the
                // latter, applied before `.position` inside the scaled/offset
                // canvas, left the button's hit region misaligned from where it
                // drew, so taps on a focused satellite ("General Chest") missed.
                .disabled(!isFocused)
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
                .position(x: center.x + exNormalized.x * scale,
                          y: center.y + exNormalized.y * scale)
            }
        }
    }

    // MARK: - Focus state

    private func focus(on category: ExerciseCategory, index: Int, categories: [ExerciseCategory],
                        center: CGPoint, scale: CGFloat) {
        let normalized = GraphLayout.categoryPosition(index: index, count: categories.count)
        withAnimation(graphAnimation) {
            focusedCategory = category
            zoomScale = GraphLayout.defaultFocusZoom
            lastScale = GraphLayout.defaultFocusZoom
            panOffset = CGSize(width: -normalized.x * scale * categoryRadius * GraphLayout.defaultFocusZoom,
                                height: -normalized.y * scale * categoryRadius * GraphLayout.defaultFocusZoom)
            lastPan = panOffset
        }
    }

    private func unfocus() {
        withAnimation(graphAnimation) {
            focusedCategory = nil
            zoomScale = minZoom
            lastScale = minZoom
            panOffset = .zero
            lastPan = .zero
        }
    }

    // MARK: - Gestures

    private func magnifyGesture(center: CGPoint, scale: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoomScale = GraphLayout.clampedZoom(lastScale * value.magnification, min: minZoom, max: maxZoom)
                if zoomScale < focusThreshold, focusedCategory != nil {
                    withAnimation(graphAnimation) {
                        focusedCategory = nil
                    }
                }
            }
            .onEnded { value in
                lastScale = zoomScale
                let categories = visibleCategories
                if zoomScale < focusThreshold {
                    unfocus()
                } else if focusedCategory == nil,
                          let nearestIndex = nearestCategoryIndex(categories: categories, center: center, scale: scale,
                                                                   pinchLocation: value.startLocation) {
                    focus(on: categories[nearestIndex], index: nearestIndex, categories: categories,
                          center: center, scale: scale)
                }
            }
    }

    private var panGesture: some Gesture {
        // A minimum distance so a stationary tap on a satellite node isn't
        // claimed by this (simultaneous) pan drag. With the default 0-distance
        // drag, taps on the small satellites arbitrated unreliably against the
        // pan and often never reached the node's tap gesture.
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                panOffset = CGSize(width: lastPan.width + value.translation.width,
                                    height: lastPan.height + value.translation.height)
            }
            .onEnded { _ in lastPan = panOffset }
    }

    private var resetGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded { resetView() }
    }

    private var zoomControls: some View {
        VStack(spacing: 8) {
            Button {
                zoom(by: 1.22)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Zoom in")

            Button {
                zoom(by: 0.82)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Zoom out")

            Button {
                resetView()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Reset graph view")
        }
        .font(.system(size: 18, weight: .semibold))
        .buttonStyle(.plain)
        .foregroundStyle(Color.luminaOnSurface)
        .padding(6)
        .background(Color.luminaCardFill, in: RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LuminaRadius.panel, style: .continuous)
                .strokeBorder(Color.luminaHairline, lineWidth: 0.5)
        )
        .padding(.top, 12)
        .padding(.trailing, 12)
    }

    private func zoom(by multiplier: CGFloat) {
        let nextScale = GraphLayout.clampedZoom(zoomScale * multiplier, min: minZoom, max: maxZoom)
        withAnimation(graphAnimation) {
            zoomScale = nextScale
            lastScale = nextScale
            if nextScale < focusThreshold {
                focusedCategory = nil
            }
        }
    }

    private func resetView() {
        withAnimation(graphAnimation) {
            focusedCategory = nil
            zoomScale = 1
            lastScale = 1
            panOffset = .zero
            lastPan = .zero
        }
    }

    /// Index of whichever visible category's node sits nearest `pinchLocation`
    /// (the screen point a pinch gesture started at) under the current
    /// pan/zoom — the category a pinch-in focuses.
    private func nearestCategoryIndex(categories: [ExerciseCategory], center: CGPoint, scale: CGFloat,
                                       pinchLocation: CGPoint) -> Int? {
        guard !categories.isEmpty else { return nil }
        let pinchOffsetX = pinchLocation.x - center.x
        let pinchOffsetY = pinchLocation.y - center.y
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for index in categories.indices {
            let normalized = GraphLayout.categoryPosition(index: index, count: categories.count)
            let screenX = normalized.x * scale * categoryRadius * zoomScale + panOffset.width
            let screenY = normalized.y * scale * categoryRadius * zoomScale + panOffset.height
            let dx = screenX - pinchOffsetX
            let dy = screenY - pinchOffsetY
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }
}

private struct SelectedExerciseGraphGroup: Identifiable, Hashable {
    let category: ExerciseCategory
    let group: ExerciseGraphGroup

    var id: String { "\(category.id)-\(group.id)" }

    static func == (lhs: SelectedExerciseGraphGroup, rhs: SelectedExerciseGraphGroup) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Category node

private struct CategoryNode: View {
    let category: ExerciseCategory
    let count: Int
    let isFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var diameter: CGFloat { isFocused ? 136 : 96 }

    var body: some View {
        ZStack {
            // Solid pastel bubble with ink content (seperate-main restyle) —
            // no translucency, white rim or colored glow.
            Circle()
                .fill(category.pastel)
                .frame(width: diameter, height: diameter)
                .shadow(color: category.pastel.opacity(isFocused ? 0.35 : 0), radius: 18)
            VStack(spacing: 3) {
                CategoryTouchGlyph(category: category, size: diameter * 0.46, tint: .onPastel)
                Text(category.rawValue)
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Color.onPastel)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.70)
                    .frame(width: diameter - 16)
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.onPastel, in: Capsule())
            }
        }
        .contentShape(Circle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.rawValue), \(count) exercise\(count == 1 ? "" : "s")")
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.86),
                   value: isFocused)
    }
}

// MARK: - Exercise group corpus

private struct ExerciseGroupCorpusSheet: View {
    let selected: SelectedExerciseGraphGroup
    let onSelect: (Exercise) -> Void

    @EnvironmentObject private var pickingSession: ExercisePickingSession

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(selected.group.exercises, id: \.uuid) { exercise in
                    ExerciseGridTile(
                        exercise: exercise,
                        badge: pickingSession.isActive ? .add(isSelected: pickingSession.isPicked(exercise)) : .none
                    ) {
                        if pickingSession.isActive {
                            pickingSession.toggle(exercise)
                        } else {
                            onSelect(exercise)
                        }
                    } onBadgeTap: {
                        if pickingSession.isActive { pickingSession.toggle(exercise) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.luminaSurface)
        .navigationTitle(selected.group.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 8) {
                Circle()
                    .fill(selected.category.pastel)
                    .frame(width: 10, height: 10)
                Text("\(selected.group.exercises.count) exercise\(selected.group.exercises.count == 1 ? "" : "s")")
                    .font(.luminaCaption)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.luminaSurface)
        }
        // This sheet is a PUSHED destination, so the picking bar
        // `ExerciseListView` attaches to the NavigationStack root never
        // reaches it — the bar has to be applied here too (see `PickingBar`).
        // `.safeAreaInset` stacks bottom-up in application order, so the bar
        // must come BEFORE `.floatingTabBarClearance()` to land just above the
        // floating tab bar's reserved zone rather than underneath it.
        .safeAreaInset(edge: .bottom) {
            if pickingSession.isActive {
                PickingBar()
            }
        }
        .floatingTabBarClearance()
    }
}

// MARK: - Exercise group node

private struct ExerciseGroupNode: View {
    let group: ExerciseGraphGroup
    let color: Color
    let isFocused: Bool
    let labelOpacity: Double

    private var diameter: CGFloat {
        GraphLayout.exerciseSatelliteDiameter(isFocused: isFocused)
    }

    var body: some View {
        ZStack {
            // Muted pastel at rest, full pastel with ink text once its
            // category is focused.
            Circle()
                .fill(color.opacity(isFocused ? 0.92 : 0.38))
                .frame(width: diameter, height: diameter)
            VStack(spacing: isFocused ? 2 : 0) {
                Text(group.title)
                    .font(.system(size: isFocused ? 9.5 : 5.2, weight: .semibold, design: .rounded))
                    .foregroundStyle(isFocused ? Color.onPastel : Color.luminaOnSurface)
                    .multilineTextAlignment(.center)
                    .lineLimit(isFocused ? 3 : 1)
                    .minimumScaleFactor(isFocused ? 0.46 : 0.35)
                Text("\(group.exercises.count)")
                    .font(.system(size: isFocused ? 8 : 4.5, weight: .bold, design: .rounded))
                    .foregroundStyle(isFocused ? Color.onPastel.opacity(0.6) : Color.luminaOnSurfaceVariant)
            }
            .frame(width: diameter - 8, height: diameter - 8)
            .padding(4)
            .opacity(labelOpacity)
        }
        .contentShape(Circle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.title), \(group.exercises.count) exercise\(group.exercises.count == 1 ? "" : "s")")
    }
}

// MARK: - Preview

#Preview {
    ExerciseGraphView(exercises: [], typeFilter: nil, onSelect: { _ in })
        .background(Color.luminaSurface)
}
