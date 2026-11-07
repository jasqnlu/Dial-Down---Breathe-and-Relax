import SwiftUI

/// One feature-showcase slide: an app screenshot in a device-style frame with a
/// title and subtitle. Static image only — no live SceneKit/SwiftData here.
struct ShowcasePage: View {
    let imageName: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 56)

            Image(imageName)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.luminaOutline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                .frame(maxHeight: 400)
                .padding(.horizontal, 48)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(.luminaTitle)
                    .foregroundStyle(Color.luminaOnSurface)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.luminaBody)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 150)   // clears OnboardingView's Next button overlay
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(Text(title)). \(Text(subtitle))"))
    }
}

#Preview {
    ShowcasePage(imageName: "showcase-bodymap",
                 title: "Tap a muscle, get the stretch",
                 subtitle: "Explore the 3D Body Map to find exercises for exactly where you feel tight.")
}
