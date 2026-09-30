import SwiftUI

// MARK: - Lumina Mobility design tokens
// Palette from the Stitch redesign (docs/superpowers/specs/
// 2026-07-06-lumina-mobility-restyle-design.md). All colors are dynamic.

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }

    static func lumina(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }
    }
}

extension Color {
    static let luminaPrimary          = Color(UIColor.lumina(light: 0xB5540A, dark: 0xFFB454))
    static let luminaOnPrimary        = Color(UIColor.lumina(light: 0xFFFFFF, dark: 0x2B1400))
    static let luminaMintTint         = Color(UIColor.lumina(light: 0xFFE9D2, dark: 0x33230F))
    static let luminaOrange           = Color(UIColor.lumina(light: 0xFF9651, dark: 0x994701))
    static let luminaOnOrange         = Color(UIColor.lumina(light: 0x6F3200, dark: 0xFFDBC8))
    /// A brighter variant of `luminaOrange`, same hue — used only for the
    /// lit streak flame (TodayView.streakButton), which reads as a small,
    /// glanceable badge rather than a filled container background, so it
    /// wants more punch than `luminaOrange`'s container-friendly tone.
    static let luminaFlameLit         = Color(UIColor.lumina(light: 0xFFAD70, dark: 0xC65C00))
    static let luminaBlue             = Color(UIColor.lumina(light: 0x4C6DDD, dark: 0xB6C4FF))
    static let luminaSurface          = Color(UIColor.lumina(light: 0xF8FAFB, dark: 0x0E1413))
    static let luminaCardFill         = Color(UIColor.lumina(light: 0xFFFFFF, dark: 0x1A2120))
    static let luminaContainer        = Color(UIColor.lumina(light: 0xECEEEF, dark: 0x242B2A))
    static let luminaOnSurface        = Color(UIColor.lumina(light: 0x191C1D, dark: 0xEFF1F2))
    static let luminaOnSurfaceVariant = Color(UIColor.lumina(light: 0x3D4946, dark: 0xBCC9C5))
    static let luminaOutline          = Color(UIColor.lumina(light: 0xE1E3E4, dark: 0x2E3835))
    static let luminaGradientStart    = Color(UIColor.lumina(light: 0xFFCB84, dark: 0xC97A2E))

    // Dial Down logo palette (Branding/logo-kit/GUIDELINES.md). The lobe
    // gradient is fixed in both modes; only the head flips so it keeps
    // contrast against the surface behind it.
    static let brandEmber             = Color(UIColor(hex: 0xC75F0E))
    static let brandAmber             = Color(UIColor(hex: 0xF59A3A))
    static let brandGlow              = Color(UIColor(hex: 0xFFC978))
    static let brandLogoHead          = Color(UIColor.lumina(light: 0xC75F0E, dark: 0xFFE2B0))
    static let luminaGradientEnd      = Color(UIColor.lumina(light: 0xD9701A, dark: 0x8A4008))
}

// MARK: - Corner radius scale
//
// One source of truth for the handful of intended radii used across cards,
// buttons, and small containers. Values are unchanged from what call sites
// already used — this only replaces the scattered magic numbers.

enum LuminaRadius {
    /// Large surfaces: hero cards, sheets, primary panels.
    static let card: CGFloat = 24
    /// Medium containers: thumbnails, popovers, secondary panels.
    static let panel: CGFloat = 16
    /// Compact controls: selectable buttons/chips, callout boxes.
    static let control: CGFloat = 14
    /// Small inline containers: segmented tabs, icon badges, stepper backgrounds.
    static let chip: CGFloat = 12
    /// Small toolbar/banner containers.
    static let badge: CGFloat = 10
    /// Tiny accents: inline icon tags.
    static let tag: CGFloat = 8
}

// MARK: - Pill button

struct LuminaPillButtonStyle: ButtonStyle {
    enum Kind { case prominent, ghost }
    var kind: Kind = .prominent
    /// Smaller sizing for inline/secondary placements (e.g. a banner action)
    /// that shouldn't compete with a full-width primary CTA.
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .luminaLabel : .luminaCardTitle)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(kind == .prominent ? Color.luminaOnPrimary : Color.luminaPrimary)
            .padding(.horizontal, compact ? 14 : 24)
            .frame(minHeight: compact ? 34 : 48)
            .background(
                kind == .prominent ? Color.luminaPrimary : Color.luminaMintTint,
                in: Capsule()
            )
            .shadow(color: kind == .prominent && !compact ? Color.luminaPrimary.opacity(0.25) : .clear,
                    radius: 10, y: 5)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Card

private struct LuminaCard: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.luminaCardFill, in: RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous))
            .shadow(color: Color(UIColor.lumina(light: 0x0F172A, dark: 0x000000)).opacity(0.05),
                    radius: 10, y: 4)
    }
}

extension View {
    func luminaCard(padding: CGFloat = 16) -> some View {
        modifier(LuminaCard(padding: padding))
    }
}

// MARK: - Filter chip

struct LuminaChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.luminaLabel)
                .foregroundStyle(isSelected ? Color.luminaOnOrange : Color.luminaOnSurfaceVariant)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(isSelected ? Color.luminaOrange : Color.luminaContainer, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
