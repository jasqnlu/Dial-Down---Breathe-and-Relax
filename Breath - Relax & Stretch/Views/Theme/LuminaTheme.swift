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
    // "Modern black" palette (seperate-main): near-black page, graphite
    // cards, white primary actions, and pastels for icon circles, tiles and
    // the active tab. The app runs dark-only, so the dark values are the
    // design; light values are a warm-cream fallback. Token names are
    // unchanged so every screen picks this up for free.
    static let luminaPrimary          = Color(UIColor.lumina(light: 0x1E1D1A, dark: 0xF5F5F7))
    static let luminaOnPrimary        = Color(UIColor.lumina(light: 0xF8F2E4, dark: 0x0A0A0B))
    static let luminaMintTint         = Color(UIColor.lumina(light: 0xDCE3C0, dark: 0x26262A))
    static let luminaOrange           = Color(UIColor.lumina(light: 0xF6BE95, dark: 0x994701))
    static let luminaOnOrange         = Color(UIColor.lumina(light: 0x5A2A08, dark: 0xFFDBC8))
    /// Selected segment in segmented controls / filter chips.
    static let luminaSegmentSelected  = Color(UIColor.lumina(light: 0x1E1D1A, dark: 0xF5F5F7))
    static let luminaOnSegmentSelected = Color(UIColor.lumina(light: 0xF8F2E4, dark: 0x0A0A0B))
    /// The lit streak flame (TodayView.streakButton).
    static let luminaFlameLit         = Color(UIColor.lumina(light: 0xF0782A, dark: 0xFF9F0A))
    static let luminaBlue             = Color(UIColor.lumina(light: 0x3E63C9, dark: 0x9DB4FF))
    static let luminaSurface          = Color(UIColor.lumina(light: 0xF8F2E4, dark: 0x0A0A0B))
    static let luminaCardFill         = Color(UIColor.lumina(light: 0xEDE6D6, dark: 0x17171A))
    static let luminaContainer        = Color(UIColor.lumina(light: 0xE2DAC8, dark: 0x26262A))
    static let luminaOnSurface        = Color(UIColor.lumina(light: 0x1E1D1A, dark: 0xF5F5F7))
    static let luminaOnSurfaceVariant = Color(UIColor.lumina(light: 0x6F695C, dark: 0x8E8E93))
    static let luminaOutline          = Color(UIColor.lumina(light: 0xDDD5C3, dark: 0x2A2A2E))
    /// Hairline edge on flat cards, in place of drop shadows.
    static let luminaHairline         = Color(UIColor.lumina(light: 0x1E1D1A, dark: 0xFFFFFF)).opacity(0.06)
    static let luminaGradientStart    = Color(UIColor.lumina(light: 0xFFCB84, dark: 0xC97A2E))

    // Pastels — icon circles, tiles, banners. Always paired with ink
    // (`luminaOnSurface`-dark) glyphs/text, never white.
    static let pastelYellow           = Color(UIColor(hex: 0xF4DC6C))
    static let pastelPink             = Color(UIColor(hex: 0xF4B8D7))
    static let pastelOlive            = Color(UIColor(hex: 0xA9B874))
    static let pastelBlue             = Color(UIColor(hex: 0xBED0F1))
    static let pastelPeach            = Color(UIColor(hex: 0xF5C09A))
    static let pastelLavender         = Color(UIColor(hex: 0xD4C6F0))
    static let pastelMint             = Color(UIColor(hex: 0xB9DEC6))
    static let pastelCoral            = Color(UIColor(hex: 0xF2A99E))
    /// Text/glyph color on any pastel.
    static let onPastel               = Color(UIColor(hex: 0x1E1D1A))

    static let pastels: [Color] = [.pastelYellow, .pastelPink, .pastelOlive, .pastelBlue,
                                   .pastelPeach, .pastelLavender, .pastelMint]

    /// A stable pastel for any string (icon name, title…). Uses a simple
    /// scalar sum, not `hashValue`, which Swift randomizes per launch.
    static func pastel(for key: String) -> Color {
        let sum = key.unicodeScalars.reduce(0) { $0 &+ Int($1.value) &* 31 }
        return pastels[abs(sum) % pastels.count]
    }

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
            .overlay(
                RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous)
                    .strokeBorder(Color.luminaHairline, lineWidth: 0.5)
            )
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
                .foregroundStyle(isSelected ? Color.luminaOnSegmentSelected : Color.luminaOnSurfaceVariant)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.luminaSegmentSelected : Color.luminaCardFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Pastel icon circle
//
// The signature element of the warm editorial look: a line glyph in ink on
// a soft pastel circle (Allergies / Past diagnoses rows in the reference).

struct LuminaIconBadge: View {
    let systemName: String
    var tint: Color? = nil
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(Color.onPastel)
            .frame(width: size, height: size)
            .background(tint ?? Color.pastel(for: systemName), in: Circle())
    }
}

/// Renders every `Label` as [pastel icon circle] + title. Apply once to a
/// `List`/container and all its Labels pick it up.
struct LuminaPastelLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 14) {
            configuration.icon
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.onPastel)
                .frame(width: 34, height: 34)
                .background(PastelForLabel(), in: Circle())
            configuration.title
                .font(.luminaBody.weight(.medium))
        }
    }
}

/// Labels don't expose their symbol name, so pastel circles inside a list
/// cycle by position instead: each row draws the next pastel in turn.
private struct PastelForLabel: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        environment.luminaPastelTint ?? .pastelYellow
    }
}

private struct LuminaPastelTintKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var luminaPastelTint: Color? {
        get { self[LuminaPastelTintKey.self] }
        set { self[LuminaPastelTintKey.self] = newValue }
    }
}

extension View {
    /// Sets the pastel used by `LuminaPastelLabelStyle` icons inside this view.
    func pastelTint(_ color: Color) -> some View {
        environment(\.luminaPastelTint, color)
    }
}

// MARK: - Count badge
//
// Small ink pill with a number — the "2" / "24" badges in the reference.

struct LuminaCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold).monospacedDigit())
            .foregroundStyle(Color.luminaOnPrimary)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 18)
            .background(Color.luminaPrimary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

// MARK: - Section title
//
// Large, bold, sentence-case section headings ("Clinical profile").

struct LuminaSectionTitle: View {
    let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .font(.luminaTitle)
            .foregroundStyle(Color.luminaOnSurface)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Category pastels
//
// One distinct pastel per body area, for surfaces drawn in the warm/black
// restyle (Exercises bubble map). `accentColor` stays as the saturated
// per-category color used by pose glyphs elsewhere.

extension ExerciseCategory {
    var pastel: Color {
        switch self {
        case .neck:       return .pastelPeach
        case .shoulders:  return .pastelYellow
        case .chest:      return .pastelPink
        case .back:       return .pastelBlue
        case .core:       return .pastelMint
        case .arms:       return .pastelLavender
        case .hipsGlutes: return .pastelCoral
        case .legs:       return .pastelOlive
        }
    }
}
