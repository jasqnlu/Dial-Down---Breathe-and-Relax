import SwiftUI

// MARK: - Welcome Page

struct WelcomePage: View {
    private struct Feature: Identifiable {
        let id   = UUID()
        let icon: String
        let title: LocalizedStringKey
        let description: LocalizedStringKey
    }

    private let features: [Feature] = [
        Feature(icon: "figure.mind.and.body",
                title: "Body Map",
                description: "Tap any muscle to find targeted exercises"),
        Feature(icon: "lungs",
                title: "Breathing Guides",
                description: "Calm your nervous system in minutes"),
        Feature(icon: "medal",
                title: "Track Progress",
                description: "Build streaks and earn badges"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 60)

                // Hero logo
                DialDownMark(motion: .breathing)
                    .frame(height: 112)
                    .padding(.bottom, 28)

                Text("Dial Down - Breath and Relax")
                    .font(.luminaDisplay)
                    .foregroundStyle(Color.luminaOnSurface)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("Your daily guide to breathing, stretching, and feeling better.")
                    .font(.luminaBody)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 12)

                // Feature list
                VStack(spacing: 0) {
                    ForEach(features) { feature in
                        FeatureRow(icon: feature.icon,
                                   title: feature.title,
                                   description: feature.description)
                        if feature.id != features.last?.id {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .padding(.top, 40)
                .padding(.horizontal, 20)
                .luminaCard(padding: 0)
                .padding(.horizontal, 20)

                Spacer(minLength: 160)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.luminaPrimary)
                .frame(width: 44, height: 44)
                .background(Color.luminaMintTint)
                .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.badge))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.luminaCardTitle)
                    .foregroundStyle(Color.luminaOnSurface)
                Text(description)
                    .font(.luminaCaption)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
            }

            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }
}

// MARK: - Preview

#Preview { WelcomePage() }
