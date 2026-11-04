import SwiftUI

/// A lightweight one-shot confetti burst, drawn with Canvas instead of a
/// third-party package — no new dependency for a small celebratory effect.
/// Bump `trigger` to fire a new burst (e.g. from `.onAppear`, or again if
/// more badges land after the view is already visible).
struct ConfettiView: View {
    var trigger: Int = 0

    private struct Particle {
        var x: Double
        var y: Double
        var velocityX: Double
        var velocityY: Double
        var rotation: Double
        var rotationSpeed: Double
        var color: Color
        var size: Double
    }

    @State private var particles: [Particle] = []
    @State private var startDate = Date()

    private static let colors: [Color] = [
        .luminaPrimary, .pastelYellow, .pastelPink, .pastelBlue, .pastelMint, .pastelLavender, .pastelPeach,
    ]
    private static let duration: TimeInterval = 2.2
    private static let fadeStart: TimeInterval = 1.6

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                Canvas { context, _ in
                    let elapsed = timeline.date.timeIntervalSince(startDate)
                    guard elapsed < Self.duration else { return }
                    let opacity = elapsed > Self.fadeStart
                        ? max(0, 1 - (elapsed - Self.fadeStart) / (Self.duration - Self.fadeStart))
                        : 1

                    for particle in particles {
                        let x = particle.x + particle.velocityX * elapsed
                        let y = particle.y + particle.velocityY * elapsed + 0.5 * 260 * elapsed * elapsed

                        var pieceContext = context
                        pieceContext.opacity = opacity
                        pieceContext.translateBy(x: x, y: y)
                        pieceContext.rotate(by: .radians(particle.rotation + particle.rotationSpeed * elapsed))

                        let rect = CGRect(x: -particle.size / 2, y: -particle.size / 4,
                                           width: particle.size, height: particle.size / 2)
                        pieceContext.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(particle.color))
                    }
                }
                .onAppear { fire(width: geometry.size.width) }
                .onChange(of: trigger) { _, _ in fire(width: geometry.size.width) }
            }
        }
        .allowsHitTesting(false)
    }

    private func fire(width: CGFloat) {
        startDate = Date()
        particles = (0..<60).map { _ in
            Particle(
                x: Double.random(in: 0...max(1, Double(width))),
                y: -20,
                velocityX: Double.random(in: -60...60),
                velocityY: Double.random(in: 80...220),
                rotation: Double.random(in: 0...(2 * .pi)),
                rotationSpeed: Double.random(in: -6...6),
                color: Self.colors.randomElement() ?? .luminaPrimary,
                size: Double.random(in: 6...12)
            )
        }
    }
}

#Preview {
    ConfettiView()
        .background(Color.luminaSurface)
}
