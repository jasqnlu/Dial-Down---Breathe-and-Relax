import SwiftUI

// MARK: - StreakCardView
// The shareable card itself, rendered off-screen via ImageRenderer.

struct StreakCardView: View {
    let streak: Int
    let totalPoints: Int
    let totalMinutes: Int
    let displayName: String

    var body: some View {
        VStack(spacing: 20) {
            if !displayName.isEmpty {
                Text("\(displayName)'s Progress")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer(minLength: 0)

            Image(systemName: "flame.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.onPastel)
                .frame(width: 88, height: 88)
                .background(Color.pastelYellow, in: Circle())

            Text("\(streak)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(streak == 1 ? "Day Streak" : "Day Streak")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 28) {
                statColumn(value: "\(totalPoints)", label: "Points")
                statColumn(value: "\(totalMinutes)", label: "Minutes")
            }
            .padding(.top, 12)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                DialDownMark(style: .solid(.white.opacity(0.7)))
                    .frame(height: 16)
                Text("Dial Down – Breathe and Relax")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(28)
        .frame(width: 320, height: 400)
        .background(
            // Black card (seperate-main) — the rendered image is shared out,
            // so it uses fixed colors rather than the dynamic tokens.
            Color(red: 0.09, green: 0.09, blue: 0.10)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: - StreakCardShareSheet
// Renders the card to a UIImage, previews it, and lets the user share via
// the system share sheet.

struct StreakCardShareSheet: View {
    let streak: Int
    let totalPoints: Int
    let totalMinutes: Int
    let displayName: String

    @State private var renderedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 0)

                if let img = renderedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                } else {
                    ProgressView()
                        .frame(height: 280)
                }

                Spacer(minLength: 0)

                if let img = renderedImage {
                    ShareLink(
                        item: Image(uiImage: img),
                        preview: SharePreview("My Streak", image: Image(uiImage: img))
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.luminaPrimary)
                            .foregroundStyle(Color.luminaOnPrimary)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Share Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                renderCard()
            }
        }
    }

    @MainActor
    private func renderCard() {
        let card = StreakCardView(
            streak: streak, totalPoints: totalPoints,
            totalMinutes: totalMinutes, displayName: displayName
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderedImage = renderer.uiImage
    }
}

#Preview {
    StreakCardShareSheet(streak: 12, totalPoints: 840, totalMinutes: 215, displayName: "Jason")
}
