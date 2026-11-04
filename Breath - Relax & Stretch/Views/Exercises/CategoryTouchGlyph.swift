import SwiftUI

/// One ExerciseCategory drawn as a standing figure touching its own body
/// region — the Exercises tab's category-circle icon. See
/// TouchGlyphArchetype (Models/TouchGlyphArchetype.swift) for why this is a
/// separate glyph family from PoseGlyphIcon.
struct CategoryTouchGlyph: View {
    let category: ExerciseCategory
    var size: CGFloat = 84
    /// Overrides the figure color (e.g. ink on a pastel bubble). When set,
    /// the glyph's own tinted backing circle is dropped — the caller's
    /// surface is the background.
    var tint: Color? = nil

    private var color: Color { tint ?? category.accentColor }

    /// TouchGlyphArchetype's coordinate space already spans ~0.07–0.95
    /// top-to-bottom (head to feet), so drawing it edge-to-edge across the
    /// full `size` box left almost no breathing room once CategoryNode
    /// stacks two lines of text underneath it inside the same circle —
    /// unlike PoseGlyphIcon, which is the only thing in its badge. Insetting
    /// every point by this fraction on each side keeps the figure clear of
    /// its own box edges regardless of what `size` the caller passes.
    private let contentInset: CGFloat = 0.07
    private var contentScale: CGFloat { 1 - 2 * contentInset }

    private var archetype: TouchGlyphArchetype {
        TouchGlyphLibrary.all[category] ?? TouchGlyphLibrary.all[.core]!
    }

    var body: some View {
        ZStack {
            Circle().fill(tint == nil ? category.accentColor.opacity(0.16) : .clear)

            TouchGlyphPath(chains: [
                inset(archetype.spine), inset(archetype.legLeft), inset(archetype.legRight),
            ])
            .stroke(color, style: StrokeStyle(lineWidth: size * 0.066 * contentScale, lineCap: .round, lineJoin: .round))

            // Resting arm drawn dimmer than the pointing arm so the
            // category-specific gesture — the whole point of this glyph
            // family — reads as the salient shape instead of getting lost
            // in a second, identical-looking limb.
            TouchGlyphPath(chains: [inset(archetype.restingArm)])
                .stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: size * 0.066 * contentScale, lineCap: .round, lineJoin: .round))

            TouchGlyphPath(chains: [inset(archetype.pointingArm)])
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.066 * contentScale, lineCap: .round, lineJoin: .round))

            Circle()
                .fill(color)
                .frame(width: archetype.headRadius * 2 * size * contentScale, height: archetype.headRadius * 2 * size * contentScale)
                .position(insetPosition(archetype.headCenter))

            Circle()
                .fill(color)
                .frame(width: size * 0.092 * contentScale, height: size * 0.092 * contentScale)
                .overlay(Circle().strokeBorder(.white, lineWidth: size * 0.017 * contentScale))
                .position(insetPosition(archetype.contactPoint))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func inset(_ p: CGPoint) -> CGPoint {
        CGPoint(x: contentInset + p.x * contentScale, y: contentInset + p.y * contentScale)
    }

    private func inset(_ chain: [CGPoint]) -> [CGPoint] { chain.map(inset) }

    private func insetPosition(_ p: CGPoint) -> CGPoint {
        let normalized = inset(p)
        return CGPoint(x: normalized.x * size, y: normalized.y * size)
    }
}

private struct TouchGlyphPath: Shape {
    let chains: [[CGPoint]]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for chain in chains {
            guard let first = chain.first else { continue }
            path.move(to: scaled(first, in: rect))
            for point in chain.dropFirst() {
                path.addLine(to: scaled(point, in: rect))
            }
        }
        return path
    }

    private func scaled(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: point.x * rect.width, y: point.y * rect.height)
    }
}
