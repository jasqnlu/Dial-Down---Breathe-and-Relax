import SwiftUI

// MARK: - Dial Down logo mark ("Open Lungs · Airways")
// Two lung lobes that double as arms raised overhead, with airways branching
// out of the body. Geometry mirrors Tools/branding/build_logo_kit.py (same
// Bézier control points on the same 256-unit concept grid), so the in-app
// mark matches the app icon and Branding/logo-kit exactly.

enum DialDownMarkGeometry {
    /// Tight bounds of the mark on the concept grid (lobe tips at y 44, lobe
    /// bases at y 214). Everything is mapped from this box into the view.
    static let box = CGRect(x: 56, y: 44, width: 144, height: 170)
    static let aspectRatio = box.width / box.height

    typealias Cubic = (CGPoint, CGPoint, CGPoint, CGPoint)

    static let lobe: [Cubic] = [
        (CGPoint(x: 120, y: 214), CGPoint(x: 74, y: 196), CGPoint(x: 50, y: 128), CGPoint(x: 56, y: 44)),
        (CGPoint(x: 56, y: 44), CGPoint(x: 96, y: 80), CGPoint(x: 122, y: 136), CGPoint(x: 120, y: 214)),
    ]
    static let airwayMain: Cubic =
        (CGPoint(x: 121, y: 182), CGPoint(x: 106, y: 156), CGPoint(x: 88, y: 124), CGPoint(x: 74, y: 88))
    static let airwayBranches: [Cubic] = [
        (CGPoint(x: 97, y: 136), CGPoint(x: 88, y: 134), CGPoint(x: 80, y: 132), CGPoint(x: 72, y: 126)),
        (CGPoint(x: 108, y: 158), CGPoint(x: 99, y: 160), CGPoint(x: 90, y: 160), CGPoint(x: 81, y: 156)),
        (CGPoint(x: 86, y: 114), CGPoint(x: 84, y: 106), CGPoint(x: 83, y: 100), CGPoint(x: 84, y: 92)),
    ]
    static let mainWidth: CGFloat = 6
    static let branchWidth: CGFloat = 4.5
    static let headCenter = CGPoint(x: 128, y: 66)
    static let headRadius: CGFloat = 18

    /// Where each lobe meets the body — the pivot for grow and breathe motion.
    static func lobeBase(mirrored: Bool) -> UnitPoint {
        let x = mirrored ? 256 - 120 : 120
        return UnitPoint(x: (CGFloat(x) - box.minX) / box.width, y: 1)
    }

    /// Maps a concept-grid point into `rect`, optionally mirrored about x = 128.
    static func map(_ p: CGPoint, in rect: CGRect, mirrored: Bool = false) -> CGPoint {
        let x = mirrored ? 256 - p.x : p.x
        return CGPoint(x: rect.minX + (x - box.minX) / box.width * rect.width,
                       y: rect.minY + (p.y - box.minY) / box.height * rect.height)
    }
}

private struct LobeShape: Shape {
    var mirrored: Bool

    func path(in rect: CGRect) -> Path {
        let g = DialDownMarkGeometry.self
        var path = Path()
        path.move(to: g.map(g.lobe[0].0, in: rect, mirrored: mirrored))
        for seg in g.lobe {
            path.addCurve(to: g.map(seg.3, in: rect, mirrored: mirrored),
                          control1: g.map(seg.1, in: rect, mirrored: mirrored),
                          control2: g.map(seg.2, in: rect, mirrored: mirrored))
        }
        path.closeSubpath()
        return path
    }
}

private struct AirwayShape: Shape {
    var mirrored: Bool
    var branches: Bool

    func path(in rect: CGRect) -> Path {
        let g = DialDownMarkGeometry.self
        var path = Path()
        for seg in branches ? g.airwayBranches : [g.airwayMain] {
            path.move(to: g.map(seg.0, in: rect, mirrored: mirrored))
            path.addCurve(to: g.map(seg.3, in: rect, mirrored: mirrored),
                          control1: g.map(seg.1, in: rect, mirrored: mirrored),
                          control2: g.map(seg.2, in: rect, mirrored: mirrored))
        }
        return path
    }
}

private struct HeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        let g = DialDownMarkGeometry.self
        let c = g.map(g.headCenter, in: rect)
        let r = g.headRadius / g.box.height * rect.height
        return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
}

/// The Dial Down logo mark. Decorative — hidden from VoiceOver, since every
/// placement sits next to the app name in text.
struct DialDownMark: View {
    enum Motion {
        /// Static artwork (share cards, rendered images).
        case still
        /// Lobes slowly open and settle on a 4 s inhale / 4 s exhale loop.
        case breathing
        /// Lobes grow up from the body, head drops in, airways draw on,
        /// then the breathing loop starts. Used on the launch splash.
        case introThenBreathing
    }

    enum Style {
        /// Amber gradient lobes, adaptive head colour.
        case color
        /// Every part in one colour (e.g. white on the streak share card).
        case solid(Color)
    }

    var motion: Motion = .still
    var style: Style = .color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown: Bool
    @State private var headShown: Bool
    @State private var airwaysDrawn: CGFloat
    @State private var inhale = false

    init(motion: Motion = .still, style: Style = .color) {
        self.motion = motion
        self.style = style
        let startsHidden = motion == .introThenBreathing
        _grown = State(initialValue: !startsHidden)
        _headShown = State(initialValue: !startsHidden)
        _airwaysDrawn = State(initialValue: startsHidden ? 0 : 1)
    }

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.height / DialDownMarkGeometry.box.height
            ZStack {
                lobe(mirrored: false, unit: unit)
                lobe(mirrored: true, unit: unit)
                HeadShape()
                    .fill(headFill)
                    .opacity(headShown ? 1 : 0)
                    .offset(y: (headShown ? 0 : -12 * unit) + (inhale ? -4 * unit : 0))
            }
        }
        .aspectRatio(DialDownMarkGeometry.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
        .task { await run() }
    }

    private func lobe(mirrored: Bool, unit: CGFloat) -> some View {
        let g = DialDownMarkGeometry.self
        let base = g.lobeBase(mirrored: mirrored)
        let tilt = inhale ? (mirrored ? 4.0 : -4.0) : 0
        return ZStack {
            LobeShape(mirrored: mirrored).fill(lobeFill)
            // destinationOut punches the airways out of the lobe, so they are
            // real holes on any background (matches the SVG kit).
            AirwayShape(mirrored: mirrored, branches: false)
                .trim(from: 0, to: airwaysDrawn)
                .stroke(style: StrokeStyle(lineWidth: g.mainWidth * unit, lineCap: .round))
                .blendMode(.destinationOut)
            AirwayShape(mirrored: mirrored, branches: true)
                .trim(from: 0, to: airwaysDrawn)
                .stroke(style: StrokeStyle(lineWidth: g.branchWidth * unit, lineCap: .round))
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .scaleEffect(x: 1, y: grown ? 1 : 0.15, anchor: base)
        .opacity(grown ? 1 : 0)
        .scaleEffect(inhale ? 1.04 : 1, anchor: base)
        .rotationEffect(.degrees(tilt), anchor: base)
    }

    private var lobeFill: AnyShapeStyle {
        switch style {
        case .color:
            AnyShapeStyle(LinearGradient(stops: [.init(color: .brandEmber, location: 0),
                                                 .init(color: .brandAmber, location: 0.55),
                                                 .init(color: .brandGlow, location: 1)],
                                         startPoint: .bottom, endPoint: .top))
        case .solid(let color):
            AnyShapeStyle(color)
        }
    }

    private var headFill: Color {
        switch style {
        case .color: .brandLogoHead
        case .solid(let color): color
        }
    }

    private func run() async {
        switch motion {
        case .still:
            return
        case .breathing:
            startBreathing()
        case .introThenBreathing:
            guard !reduceMotion else {
                grown = true; headShown = true; airwaysDrawn = 1
                return
            }
            // Whole intro lands in ~1.2 s so it finishes inside the splash's
            // 1.5 s minimum hold (BreathRelaxStretchApp).
            withAnimation(.spring(duration: 0.8, bounce: 0.25)) { grown = true }
            guard (try? await Task.sleep(for: .milliseconds(300))) != nil else { return }
            withAnimation(.spring(duration: 0.5, bounce: 0.35)) { headShown = true }
            guard (try? await Task.sleep(for: .milliseconds(150))) != nil else { return }
            withAnimation(.easeOut(duration: 0.7)) { airwaysDrawn = 1 }
            guard (try? await Task.sleep(for: .milliseconds(700))) != nil else { return }
            startBreathing()
        }
    }

    private func startBreathing() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { inhale = true }
    }
}

// MARK: - Preview

#Preview("Intro") {
    DialDownMark(motion: .introThenBreathing)
        .frame(height: 160)
}

#Preview("Solid white on gradient") {
    DialDownMark(style: .solid(.white))
        .frame(height: 40)
        .padding()
        .background(Color.brandEmber)
}
