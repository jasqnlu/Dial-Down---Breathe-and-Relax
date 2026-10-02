import SwiftUI

/// Shown at app launch while `BodyMeshLoader` preloads the anatomy mesh, so
/// Body Map never has to show its own "Loading 3D model…" spinner later.
/// Purely a launch-time gate — no dismiss action; `BreathRelaxStretchApp`
/// removes it from the view tree once preloading finishes (see
/// `docs/superpowers/specs/2026-07-31-app-launch-preload-design.md`).
struct AppLoadingView: View {
    @State private var currentFact = BodyTrivia.randomFact()

    /// Must match the system launch screen (Assets LaunchLogo): a 104 pt mark
    /// whose centre sits 140 pt above the *full-screen* centre. The launch
    /// image gets that lift from transparent padding below the mark, so the
    /// hand-off from launch screen to splash has no jump.
    static let markHeight: CGFloat = 104
    static let markLift: CGFloat = 140

    var body: some View {
        GeometryReader { geo in
            let markCenterY = geo.size.height / 2 - Self.markLift
            ZStack(alignment: .top) {
                Color.luminaSurface

                DialDownMark(motion: .continueFromLaunch)
                    .frame(height: Self.markHeight)
                    .position(x: geo.size.width / 2, y: markCenterY)

                content
                    .frame(width: geo.size.width)
                    .padding(.top, markCenterY + Self.markHeight / 2 + 24)
            }
        }
        .ignoresSafeArea()
    }

    private var content: some View {
        VStack(spacing: 24) {
            Text("Dial Down – Breathe and Relax")
                .font(.luminaDisplay)
                .foregroundStyle(Color.luminaOnSurface)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            ProgressView()
                .controlSize(.large)
                .tint(Color.luminaPrimary)

            triviaCard
        }
        .padding(.horizontal, 24)
    }

    private var triviaCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("Did you know?")
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2)
            }
            .font(.luminaLabel)
            .foregroundStyle(Color.luminaPrimary)

            Text(currentFact)
                .id(currentFact)
                .transition(.opacity)
                .font(.luminaSubheadline)
                .foregroundStyle(Color.luminaOnSurface)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: 280)
        .background(Color.luminaMintTint.opacity(0.78), in: RoundedRectangle(cornerRadius: LuminaRadius.panel))
        .contentShape(RoundedRectangle(cornerRadius: LuminaRadius.panel))
        // Explicit label/value (not the raw combined child texts) so this
        // reads as one stable VoiceOver element regardless of which random
        // fact is showing — also gives AppLoadingViewUITest (Task 4) a
        // predictable query target. See the repo's `verify` skill: a
        // container with an explicit `.accessibilityLabel` replaces its
        // child texts in the XCUI hierarchy, so query the container's own
        // label, not `staticTexts`.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Body trivia fact")
        .accessibilityValue(currentFact)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to show another fact")
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentFact = BodyTrivia.randomFact(excluding: currentFact)
            }
        }
    }
}

// MARK: - Preview

#Preview { AppLoadingView() }
