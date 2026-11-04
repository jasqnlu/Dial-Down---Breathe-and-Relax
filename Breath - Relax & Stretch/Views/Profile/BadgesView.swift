import SwiftUI

struct BadgesView: View {
    let earnedBadges: [String]

    struct BadgeDefinition {
        let name: String
        let icon: String
        let description: String
    }

    static let allBadges: [BadgeDefinition] = [
        // First session
        BadgeDefinition(name: "First Breath",         icon: "wind",                        description: "Complete your very first session"),
        // Streak milestones
        BadgeDefinition(name: "Streak Starter",       icon: "flame",                       description: "Achieve a 3-day streak"),
        BadgeDefinition(name: "Weekly Warrior",       icon: "flame.fill",                  description: "Keep a 7-day streak"),
        BadgeDefinition(name: "Two Week Streak",      icon: "flame.circle",                description: "Keep a 14-day streak"),
        BadgeDefinition(name: "Month of Mindfulness", icon: "calendar.badge.checkmark",    description: "Keep a 30-day streak"),
        BadgeDefinition(name: "Streak Legend",        icon: "flame.circle.fill",           description: "Keep a 60-day streak"),
        BadgeDefinition(name: "Unstoppable",          icon: "bolt.fill",                   description: "Keep a 100-day streak"),
        // Time milestones
        BadgeDefinition(name: "30 Min Club",          icon: "clock",                       description: "Accumulate 30 minutes of practice"),
        BadgeDefinition(name: "Hour Hero",            icon: "clock.badge.checkmark",       description: "Accumulate 1 hour of practice"),
        BadgeDefinition(name: "5 Hour Club",          icon: "clock.badge.fill",            description: "Accumulate 5 hours of practice"),
        BadgeDefinition(name: "Ten Hour Club",        icon: "clock.arrow.circlepath",      description: "Accumulate 10 hours of practice"),
        BadgeDefinition(name: "Marathoner",           icon: "figure.run",                  description: "Accumulate 20 hours of practice"),
        BadgeDefinition(name: "2000 Club",            icon: "trophy",                      description: "Accumulate 2,000 minutes of practice"),
        // Points milestones
        BadgeDefinition(name: "Century",              icon: "star",                        description: "Earn 100 total points"),
        BadgeDefinition(name: "High Achiever",        icon: "star.leadinghalf.filled",     description: "Earn 500 total points"),
        BadgeDefinition(name: "Elite Breather",       icon: "star.fill",                   description: "Earn 1,000 total points"),
        // Time-of-day / habit-shape
        BadgeDefinition(name: "Early Bird",           icon: "sunrise.fill",                description: "Complete 5 sessions before 8am"),
        BadgeDefinition(name: "Night Owl",            icon: "moon.stars.fill",             description: "Complete 5 sessions after 10pm"),
        BadgeDefinition(name: "Weekend Warrior",      icon: "calendar.circle.fill",        description: "Complete 5 sessions on a weekend"),
        // Variety
        BadgeDefinition(name: "Well Rounded",         icon: "figure.mixed.cardio",         description: "Target every major muscle group across your sessions"),
        BadgeDefinition(name: "Difficulty Climber",   icon: "chart.line.uptrend.xyaxis",   description: "Complete an exercise at every difficulty level"),
        BadgeDefinition(name: "Best of Both",         icon: "arrow.triangle.2.circlepath", description: "Complete both a breathing and a stretch session"),
        // Special
        BadgeDefinition(name: "Full Body",            icon: "figure.mind.and.body",        description: "Target 5+ muscle groups in one session"),
        BadgeDefinition(name: "Routine Builder",      icon: "rectangle.stack.badge.plus",  description: "Create your first custom routine"),
        BadgeDefinition(name: "Borrowed & Built",     icon: "arrow.triangle.branch",       description: "Complete a routine borrowed from the library"),
    ]

    var body: some View {
        List(Self.allBadges, id: \.name) { badge in
            let earned = earnedBadges.contains(badge.name)
            HStack(spacing: 16) {
                // Earned: pastel circle (stable per badge). Locked: dim graphite.
                if earned {
                    LuminaIconBadge(systemName: badge.icon, tint: Color.pastel(for: badge.name), size: 40)
                } else {
                    Image(systemName: badge.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                        .frame(width: 40, height: 40)
                        .background(Color.luminaContainer, in: Circle())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(badge.name)
                        .font(.luminaCardTitle)
                        .foregroundStyle(earned ? Color.luminaOnSurface : Color.luminaOnSurfaceVariant)
                    Text(badge.description)
                        .font(.luminaCaption)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                }

                Spacer()

                if earned {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.luminaOnPrimary)
                        .frame(width: 22, height: 22)
                        .background(Color.luminaPrimary, in: Circle())
                }
            }
            .padding(.vertical, 6)
            .opacity(earned ? 1.0 : 0.5)
            .listRowBackground(Color.luminaCardFill)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.luminaSurface)
        .navigationTitle("Badges")
        .floatingTabBarClearance()
    }
}

#Preview {
    NavigationStack {
        BadgesView(earnedBadges: ["First Breath", "Streak Starter"])
    }
}
