import SwiftUI

/// The coach-mark tour's visuals: a soft dim with a rounded spotlight cut out
/// around the current step's target, a pastel ring in the section's tab
/// color, and a card explaining the step. The welcome and finish steps show
/// a centered card with no spotlight.
///
/// Nothing here hit-tests except the card itself, so the real app stays
/// fully tappable underneath — the interactive steps (Areas / Body switch,
/// tap a sore spot, Find Stretches) rely on that. The dim fades out above
/// the tab bar so the bar stays lit and shows which tab you're on.
///
/// `anchors`/`proxy` are supplied by the caller (`HomeView`) via
/// `.overlayPreferenceValue` attached to its OUTER ZStack, since
/// `.overlayPreferenceValue`/`.onPreferenceChange` can only observe
/// preference values bubbling up from a view's own subtree — this view
/// itself has no subtree of `.tourAnchor`-tagged content to observe.
struct TourSpotlightOverlay: View {
    @EnvironmentObject private var coordinator: TourCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let anchors: [String: Anchor<CGRect>]
    let proxy: GeometryProxy
    /// Measured height of the step card, used to decide whether it fits
    /// above or below the spotlight.
    @State private var cardHeight: CGFloat = 280

    /// Steps whose own target can disappear mid-step fall back to another:
    /// "Find Stretches" points at a bar that only shows once a muscle is
    /// picked, so until then keep the body itself lit (its muscle labels
    /// are what the user taps next).
    private static let fallbackAnchors = ["bodymap.findStretches": "bodymap.tapRegion"]

    var body: some View {
        if coordinator.isActive, let step = coordinator.currentStep {
            let target = resolvedRect(for: step)
            let section = TourSection(tab: coordinator.currentSectionTab)
            let tabBarTop = anchors["chrome.tabBar"].map { proxy[$0].minY } ?? (proxy.size.height - 90)

            ZStack {
                dimLayer(target: target, tabBarTop: tabBarTop)
                if let target {
                    SpotlightRing(rect: target, tint: section.tint, pulses: !reduceMotion)
                }
                if TourCoordinator.isCardOnly(step) {
                    TourCenterCard(step: step, section: section)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                } else {
                    let place = placement(for: target, tabBarTop: tabBarTop)
                    TourStepCard(step: step, section: section)
                        .frame(width: min(proxy.size.width - 32, 360))
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: place.edge == .top ? .top : .bottom)
                        .padding(place.edge, place.inset)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .ignoresSafeArea()
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.86),
                       value: step.id)
            .transition(.opacity)
        }
    }

    // MARK: Layout

    /// The spotlight frame: every anchor tagged with the step's id (or
    /// `"<id>#part"`, for targets split across List rows) unioned together,
    /// padded, and kept inside the screen's side edges so the ring never
    /// runs off-screen around full-width content.
    private func resolvedRect(for step: TourStep) -> CGRect? {
        if TourCoordinator.isCardOnly(step) { return nil }
        if let fixedFrame = step.fixedFrame { return fixedFrame(proxy) }
        let rect = unionOfAnchors(step.id)
            ?? Self.fallbackAnchors[step.id].flatMap(unionOfAnchors)
        guard let rect else { return nil }
        var padded = rect.insetBy(dx: -8, dy: -8)
        let minX = max(padded.minX, 6)
        let maxX = min(padded.maxX, proxy.size.width - 6)
        padded.origin.x = minX
        padded.size.width = max(0, maxX - minX)
        return padded
    }

    private func unionOfAnchors(_ id: String) -> CGRect? {
        anchors
            .filter { $0.key == id || $0.key.hasPrefix(id + "#") }
            .map { proxy[$0.value] }
            .reduce(nil) { partial, rect in partial.map { $0.union(rect) } ?? rect }
    }

    /// Where the card goes: right below the spotlight if it fits there,
    /// else right above it, else just above the tab bar (the fallback for
    /// targets too big to clear, like the whole body scene — those can be
    /// tapped anywhere, so the card covering part of them is fine).
    private func placement(for target: CGRect?, tabBarTop: CGFloat) -> (edge: Edge.Set, inset: CGFloat) {
        let height = proxy.size.height
        let gap: CGFloat = 12
        let topLimit: CGFloat = 60          // below the status bar / Dynamic Island
        let bottomLimit = tabBarTop - 10    // above the tab bar's pop-out bubble
        if let target, target.height < height * 0.55 {
            if target.maxY + gap + cardHeight <= bottomLimit {
                return (.top, target.maxY + gap)
            }
            if target.minY - gap - cardHeight >= topLimit {
                return (.bottom, height - target.minY + gap)
            }
        }
        return (.bottom, height - tabBarTop + 14)
    }

    // MARK: Dim

    /// Dark veil with the target cut out, fading away just above the tab bar.
    private func dimLayer(target: CGRect?, tabBarTop: CGFloat) -> some View {
        let height = max(proxy.size.height, 1)
        let fadeStart = max(0, (tabBarTop - 70) / height)
        let fadeEnd = max(fadeStart, (tabBarTop - 18) / height)
        // No target: collapse the cut-out to a point mid-screen so the
        // spotlight shrinks/grows smoothly in and out of the cards.
        let hole = target ?? CGRect(x: proxy.size.width / 2, y: proxy.size.height / 2, width: 0, height: 0)

        return SpotlightCutout(hole: hole, cornerRadius: 22)
            .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
            .mask(
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: fadeStart),
                    .init(color: .clear, location: fadeEnd),
                ], startPoint: .top, endPoint: .bottom)
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Section styling

/// Name, icon and pastel for the tab a tour section covers — the same
/// pastel and icon the tab uses in `CustomTabBar`.
struct TourSection {
    let title: LocalizedStringKey
    let icon: String
    let tint: Color

    init(tab: Int?) {
        switch tab.flatMap(AppTab.init(rawValue:)) {
        case .today:     (title, icon, tint) = ("Today", "sun.max.fill", .pastelYellow)
        case .exercises: (title, icon, tint) = ("Exercises", "square.grid.2x2.fill", .pastelBlue)
        case .breathe:   (title, icon, tint) = ("Breathe", "wind", .pastelMint)
        case .routines:  (title, icon, tint) = ("Routines", "rectangle.stack.fill", .pastelLavender)
        case .profile:   (title, icon, tint) = ("Profile", "person.fill", .pastelPink)
        case nil:        (title, icon, tint) = ("Tour", "sparkles", .pastelLavender)
        }
    }
}

// MARK: - Spotlight shapes

/// A full-screen rectangle with a rounded hole; filled even-odd. The hole's
/// frame is animatable so the spotlight glides between targets.
private struct SpotlightCutout: Shape {
    var hole: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(hole.origin.x, hole.origin.y), .init(hole.size.width, hole.size.height)) }
        set {
            hole = CGRect(x: newValue.first.first, y: newValue.first.second,
                          width: newValue.second.first, height: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let radius = min(cornerRadius, hole.width / 2, hole.height / 2)
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        return path
    }
}

/// The pastel outline around the spotlight, with a slow breathing glow.
private struct SpotlightRing: View {
    let rect: CGRect
    let tint: Color
    let pulses: Bool
    @State private var glow = false

    var body: some View {
        let radius = min(22, rect.width / 2, rect.height / 2)
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(tint, lineWidth: 2)
            .shadow(color: tint.opacity(glow ? 0.75 : 0.35), radius: glow ? 14 : 6)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard pulses else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { glow = true }
            }
    }
}

// MARK: - Step card

private struct TourStepCard: View {
    @EnvironmentObject private var coordinator: TourCoordinator
    let step: TourStep
    let section: TourSection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.luminaTitle)
                    .foregroundStyle(Color.luminaOnSurface)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.message)
                    .font(.luminaBody)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if step.isInteractive, let hint = step.hint {
                TourHint(text: hint, tint: section.tint)
            }

            TourProgressBar()

            controls
        }
        .padding(20)
        .background(Color.luminaCardFill, in: RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous)
                .strokeBorder(section.tint.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 10) {
            LuminaIconBadge(systemName: section.icon, tint: section.tint, size: 28)
            Text(section.title)
                .font(.luminaLabel)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Color.luminaOnSurfaceVariant)
            if let position = coordinator.positionInSection, position.count > 1 {
                Text("\(position.index) / \(position.count)")
                    .font(.system(.caption, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.luminaOnSurfaceVariant.opacity(0.8))
            }
            Spacer(minLength: 0)
            Button {
                coordinator.finish()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                    .frame(width: 30, height: 30)
                    .background(Color.luminaContainer, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Exit tour")
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button("Skip") { coordinator.skipToNextSection() }
                .font(.luminaLabel)
                .foregroundStyle(Color.luminaOnSurfaceVariant)
                .buttonStyle(.plain)
                .padding(.vertical, 8)
                .accessibilityHint("Jumps to the next part of the tour")

            Spacer(minLength: 0)

            if !coordinator.isFirstStepInSection {
                Button {
                    coordinator.back()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.luminaOnSurface)
                        .frame(width: 40, height: 40)
                        .background(Color.luminaContainer, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            if !step.isInteractive {
                Button {
                    coordinator.advance()
                } label: {
                    HStack(spacing: 6) {
                        Text("Next")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .buttonStyle(LuminaPillButtonStyle(compact: true))
            }
        }
    }
}

/// "Do this to continue" line on interactive steps, with a gently pulsing
/// tap glyph.
private struct TourHint: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 13, weight: .semibold))
                .symbolEffect(.pulse, options: .repeating)
            Text(LocalizedStringKey(text))
                .font(.luminaLabel)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

/// One segment per section, tinted in each section's pastel: past sections
/// full, the current one filled up to this step, later ones empty.
private struct TourProgressBar: View {
    @EnvironmentObject private var coordinator: TourCoordinator

    var body: some View {
        let tabs = coordinator.sectionTabs
        let current = coordinator.currentSectionTab
        let currentIndex = current.flatMap { tabs.firstIndex(of: $0) } ?? 0
        let fraction: CGFloat = {
            guard let position = coordinator.positionInSection else { return 1 }
            return CGFloat(position.index) / CGFloat(max(position.count, 1))
        }()

        HStack(spacing: 5) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { offset, tab in
                let fill: CGFloat = offset < currentIndex ? 1 : (offset == currentIndex ? fraction : 0)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.luminaContainer)
                        Capsule()
                            .fill(TourSection(tab: tab).tint)
                            .frame(width: geo.size.width * fill)
                    }
                }
                .frame(height: 5)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: coordinator.currentStepIndex)
        .accessibilityElement()
        .accessibilityLabel("Step \(coordinator.stepNumber) of \(coordinator.totalSteps)")
    }
}

// MARK: - Welcome / finish card

private struct TourCenterCard: View {
    @EnvironmentObject private var coordinator: TourCoordinator
    let step: TourStep
    let section: TourSection

    private var isWelcome: Bool { step.id == TourStep.welcomeID }

    var body: some View {
        VStack(spacing: 18) {
            if isWelcome {
                DialDownMark(motion: .breathing)
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)
            } else {
                ZStack {
                    ForEach(Array([Color.pastelYellow, .pastelBlue, .pastelMint, .pastelLavender, .pastelPink].enumerated()), id: \.offset) { i, color in
                        Circle().fill(color)
                            .frame(width: 22, height: 22)
                            .offset(x: CGFloat(i - 2) * 18)
                    }
                }
                .frame(height: 30)
                .accessibilityHidden(true)
            }

            VStack(spacing: 8) {
                Text(step.title)
                    .font(.luminaHeadline)
                    .foregroundStyle(Color.luminaOnSurface)
                    .multilineTextAlignment(.center)
                Text(step.message)
                    .font(.luminaBody)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 6) {
                Button {
                    coordinator.advance()
                } label: {
                    Text(isWelcome ? "Show Me Around" : "Start Exploring")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LuminaPillButtonStyle())

                if isWelcome {
                    Button("Not Now") { coordinator.finish() }
                        .font(.luminaLabel)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                        .buttonStyle(.plain)
                        .padding(.vertical, 8)
                        .accessibilityLabel("Exit tour")
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 340)
        .background(Color.luminaCardFill, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.luminaHairline, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Preview

#Preview {
    let coordinator = TourCoordinator()
    coordinator.restart()
    return GeometryReader { proxy in
        ZStack {
            Color.luminaSurface.ignoresSafeArea()
            TourSpotlightOverlay(anchors: [:], proxy: proxy)
        }
    }
    .environmentObject(coordinator)
}
