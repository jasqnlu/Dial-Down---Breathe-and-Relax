import SwiftUI

// MARK: - Appearance Tab

struct ProfileAppearanceTab: View {
    @AppStorage("accentColorName")     private var accentColorName = "Blue"
    @AppStorage("compactListMode")     private var compactListMode = false
    @AppStorage("showStreakEmoji")     private var showStreakEmoji = true

    let accentOptions: [(name: String, color: Color)] = [
        ("Blue",   .blue),
        ("Purple", .purple),
        ("Pink",   .pink),
        ("Red",    .red),
        ("Orange", .orange),
        ("Green",  .green),
    ]

    var body: some View {
        Group {
            // Accent color
            Section("Accent Color") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6),
                          spacing: 12) {
                    ForEach(accentOptions, id: \.name) { option in
                        Button {
                            withAnimation(.spring(duration: 0.25)) {
                                accentColorName = option.name
                            }
                        } label: {
                            ZStack {
                                Circle().fill(option.color).frame(width: 34, height: 34)
                                if accentColorName == option.name {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.name)
                        .accessibilityAddTraits(accentColorName == option.name ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }

            // Layout
            Section("Layout") {
                Toggle(isOn: $compactListMode) {
                    Label("Compact Exercise List", systemImage: "list.bullet.indent")
                        .pastelTint(.pastel(for: "list.bullet.indent"))
                        .labelStyle(LuminaPastelLabelStyle())
                }
                Toggle(isOn: $showStreakEmoji) {
                    Label("Show Streak Emoji 🔥", systemImage: "flame")
                        .pastelTint(.pastel(for: "flame"))
                        .labelStyle(LuminaPastelLabelStyle())
                }
            }
        }
        .listRowBackground(Color.luminaCardFill)
        .tint(Color.luminaPrimary)
    }
}
