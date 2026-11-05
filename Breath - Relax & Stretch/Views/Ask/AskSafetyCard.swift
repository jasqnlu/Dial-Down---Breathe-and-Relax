import SwiftUI

/// Safety response: doctor note, emergency button, and (concerning only) the gentle option.
struct AskSafetyCard: View {
    let level: SafetyLevel
    /// Shows "show gentle stretches anyway" (concerning only); nil once it has been used.
    let onGentleAnyway: (() -> Void)?

    @Environment(\.openURL) private var openURL

    /// The local emergency number for the device's region (not the app language).
    /// Unknown regions get 112, which most GSM phones route to local services.
    static func emergencyNumber(for region: Locale.Region?) -> String {
        guard let code = region?.identifier.uppercased() else { return "112" }
        return emergencyNumbers[code] ?? "112"
    }

    private static let emergencyNumbers: [String: String] = {
        var table = ["CN": "120", "JP": "119", "KR": "119", "TW": "119",
                     "BR": "192", "CL": "131", "AU": "000", "GB": "999", "NZ": "111", "IN": "112"]
        for code in ["US", "CA", "MX", "AR", "CO", "PE", "VE", "EC", "PA", "CR",
                     "GT", "HN", "SV", "NI", "DO", "PY", "UY"] {
            table[code] = "911"
        }
        return table
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if level == .concerning {
                Text("This sounds like more than everyday tightness. It's worth checking with a doctor before stretching.")
            }
            Text("If the pain is severe or came on suddenly, please call emergency services.")

            Button {
                let number = Self.emergencyNumber(for: Locale.current.region)
                if let url = URL(string: "tel://\(number)") { openURL(url) }
            } label: {
                Label("Call emergency services", systemImage: "phone.fill")
                    .font(.luminaCardTitle)
                    .foregroundStyle(Color.onPastel)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.pastelCoral, in: RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ask.emergency")

            if level == .concerning, let onGentleAnyway {
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
