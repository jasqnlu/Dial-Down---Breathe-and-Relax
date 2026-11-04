import SwiftUI

/// Confetti + a staggered spring-reveal card per newly-earned badge, shown on
/// top of a session-completion screen. Shared by SessionSummaryView (stretch
/// routines) and BreathingView's completion overlay so both flows celebrate
/// new badges the same way — see SessionRecorder's header comment on why
/// those two flows keep drifting when logic like this lives in two places.
struct NewBadgesOverlay: View {
    let newlyEarnedBadges: [String]

    @State private var confettiTrigger = 0
    @State private var revealedCount = 0

    private var badges: [BadgesView.BadgeDefinition] {
        newlyEarnedBadges.compactMap { name in
            BadgesView.allBadges.first { $0.name == name }
        }
    }

    var body: some View {
        if !badges.isEmpty {
            ZStack {
                ConfettiView(trigger: confettiTrigger)

                VStack(spacing: 12) {
                    ForEach(Array(badges.enumerated()), id: \.element.name) { index, badge in
                        badgeCard(badge)
                            .opacity(index < revealedCount ? 1 : 0)
                            .scaleEffect(index < revealedCount ? 1 : 0.7)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.6).delay(Double(index) * 0.25),
                                value: revealedCount)
                    }
                }
                .padding(.horizontal, 24)
            }
            .onAppear {
                confettiTrigger += 1
                revealedCount = badges.count
            }
        }
    }

    private func badgeCard(_ badge: BadgesView.BadgeDefinition) -> some View {
        HStack(spacing: 12) {
            LuminaIconBadge(systemName: badge.icon, tint: .pastelYellow, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Badge Earned!")
                    .font(.luminaLabel)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                    .textCase(.uppercase)
                Text(badge.name)
                    .font(.luminaCardTitle)
                    .foregroundStyle(Color.luminaOnSurface)
            }

            Spacer()
        }
        .padding(12)
        .luminaCard()
    }
}

#Preview {
    NewBadgesOverlay(newlyEarnedBadges: ["First Breath", "30 Min Club"])
        .background(Color.luminaSurface)
}
