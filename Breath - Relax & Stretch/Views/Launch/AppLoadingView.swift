import SwiftUI

/// Shown at app launch while `BodyMeshLoader` preloads the anatomy mesh, so
/// Body Map never has to show its own "Loading 3D model…" spinner later.
/// Purely a launch-time gate — no dismiss action; `BreathRelaxStretchApp`
/// removes it from the view tree once preloading finishes (see
/// `docs/superpowers/specs/2026-07-31-app-launch-preload-design.md`).
struct AppLoadingView: View {
    @State private var currentFact = BodyTrivia.randomFact()

    var body: some View {
        ZStack {
            Color.luminaSurface.ignoresSafeArea()

            VStack(spacing: 24) {
                DialDownMark(motion: .introThenBreathing)
                    .frame(height: 104)

                Text("Dial Down - Breath and Relax")
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
