import SwiftUI

/// Safety response: doctor note, emergency button, and (concerning only) the gentle option.
struct AskSafetyCard: View {
    let level: SafetyLevel
    let onGentleAnyway: () -> Void

    @Environment(\.openURL) private var openURL

    static var emergencyNumber: String {
        let region = Locale.current.region
        return region == .unitedStates || region == .canada ? "911" : "112"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if level == .concerning {
                Text("This sounds like more than everyday tightness. It's worth checking with a doctor before stretching.")
            }
            Text("If the pain is severe or came on suddenly, please call emergency services.")

            Button {
                if let url = URL(string: "tel://\(Self.emergencyNumber)") { openURL(url) }
            } label: {
                Label("Call emergency services", systemImage: "phone.fill")
                    .font(.luminaCardTitle)
                    .foregroundStyle(Color.onPastel)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.pastelCoral, in: RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ask.emergency")

            if level == .concerning {
                Button(action: onGentleAnyway) {
                    Text("I understand — show gentle stretches anyway")
                        .font(.luminaLabel)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                                .strokeBorder(Color.luminaOutline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ask.gentleAnyway")
            }
        }
        .font(.luminaBody)
        .foregroundStyle(Color.onPastel)
        .padding(16)
        .background(Color.pastelPeach, in: RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous))
    }
}
