import SwiftUI

// MARK: - Language Page

/// First onboarding screen. Picking a language writes `appLanguage`, which the
/// app root turns into the `\.locale` environment — so this screen's own text
/// switches the instant a row is tapped.
struct LanguagePage: View {
    @AppStorage(AppLanguage.storageKey) private var storedLanguage = AppLanguage.system.rawValue

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 60)

                LuminaIconBadge(systemName: "globe", tint: .pastelBlue, size: 88)
                    .padding(.bottom, 24)

                Text("Choose your language")
                    .font(.luminaDisplay)
                    .foregroundStyle(Color.luminaOnSurface)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("You can change this anytime in Settings.")
                    .font(.luminaBody)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 10)

                VStack(spacing: 0) {
                    ForEach(AppLanguage.allCases) { language in
                        LanguageRow(language: language,
                                    isSelected: AppLanguage(stored: storedLanguage) == language) {
                            storedLanguage = language.rawValue
                        }
                        if language != AppLanguage.allCases.last {
                            Divider().padding(.leading, 20)
                        }
                    }
                }
                .luminaCard(padding: 0)
                .padding(.horizontal, 20)
                .padding(.top, 32)

                Spacer(minLength: 160)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Language Row

private struct LanguageRow: View {
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let nativeName = language.nativeName {
                    Text(verbatim: nativeName)
                } else {
                    Text("System Default")
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.luminaPrimary)
                }
            }
            .font(.luminaCardTitle)
            .foregroundStyle(Color.luminaOnSurface)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("language.\(language.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Preview

#Preview { LanguagePage() }
