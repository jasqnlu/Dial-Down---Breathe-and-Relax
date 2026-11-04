import SwiftUI

struct SessionSummaryView: View {
    let pointsEarned: Int
    /// The profile's streak after this session (0 with no profile yet).
    var streak: Int = 0
    /// Whether *this* session is what moved the streak — false for a second
    /// session completed the same day, where `streak` is unchanged and the
    /// flame shouldn't replay its "just lit" animation.
    var streakIncreased: Bool = false
    var newlyEarnedBadges: [String] = []
    let onDismiss: () -> Void

    @State private var flameIsLit = false
    @State private var displayedStreak = 0

    var body: some View {
        ZStack {
        VStack(spacing: 32) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close")
                Spacer()
            }
            .padding([.horizontal, .top])

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(Color.onPastel)
                .frame(width: 88, height: 88)
                .background(Color.pastelMint, in: Circle())

            VStack(spacing: 8) {
                Text("Session Complete!")
                    .font(.luminaDisplay)
                    .foregroundStyle(Color.luminaPrimary)

                Text("Great work. Keep the streak going!")
                    .font(.luminaSubheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                // Streak — grey/unlit at 0, and for a genuine bump (not a
                // second session the same day, which leaves the streak
                // unchanged) the flame lights up and the count steps up
                // from yesterday's value once the view appears, rather than
                // just materializing already-incremented.
                VStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(flameIsLit ? Color.luminaFlameLit : Color.luminaOnSurfaceVariant.opacity(0.5))
                        .scaleEffect(flameIsLit ? 1 : 0.82)
                        .animation(.spring(response: 0.45, dampingFraction: 0.55), value: flameIsLit)
                    Text("\(displayedStreak)")
                        .font(.luminaHeadline)
                        .foregroundStyle(Color.luminaPrimary)
                        .contentTransition(.numericText())
                    Text("day streak")
                        .font(.luminaLabel)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                        .textCase(.uppercase)
                }
                .frame(maxWidth: .infinity)
                .luminaCard()

                VStack(spacing: 4) {
                    Image(systemName: "medal.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.pastelYellow)
                    Text("+\(pointsEarned)")
                        .font(.luminaHeadline)
                        .foregroundStyle(Color.luminaPrimary)
                    Text("points earned")
                        .font(.luminaLabel)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                        .textCase(.uppercase)
                }
                .frame(maxWidth: .infinity)
                .luminaCard()
            }
            .padding(.horizontal, 24)
            .onAppear {
                if streakIncreased {
                    displayedStreak = max(0, streak - 1)
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.35)) {
                        displayedStreak = streak
                        flameIsLit = true
                    }
                } else {
                    displayedStreak = streak
                    flameIsLit = streak > 0
                }
            }

            Spacer()

            Button(action: onDismiss) {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LuminaPillButtonStyle())
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .background(
            Color.luminaSurface.ignoresSafeArea()
        )

            NewBadgesOverlay(newlyEarnedBadges: newlyEarnedBadges)
        }
    }
}

#Preview("Streak increased") {
    SessionSummaryView(pointsEarned: 42, streak: 4, streakIncreased: true) {}
}

#Preview("Second session today") {
    SessionSummaryView(pointsEarned: 18, streak: 4, streakIncreased: false) {}
}

#Preview("New badges earned") {
    SessionSummaryView(pointsEarned: 42, streak: 4, streakIncreased: true,
                        newlyEarnedBadges: ["First Breath", "30 Min Club"]) {}
}
