import Testing
import SwiftUI
import UIKit
@testable import BreathRelaxStretch

@Suite("Lumina theme colors")
struct LuminaThemeTests {
    @Test("primary resolves differently in light and dark")
    func primaryIsDynamic() {
        let ui = UIColor(Color.luminaPrimary)
        let light = ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(light != dark)
    }

    @Test("surface resolves differently in light and dark")
    func surfaceIsDynamic() {
        let ui = UIColor(Color.luminaSurface)
        #expect(ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
             != ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
    }

    /// The "modern black" restyle (seperate-main) makes the primary action
    /// color a near-white neutral (white pill buttons on near-black). Still a
    /// regression guard against the old teal/mint-cyan (0x6ED8C5: R=110,
    /// G=216, B=197), which fails both the brightness and neutrality checks.
    @Test("primary dark value is a near-white neutral, not cyan")
    func primaryDarkIsNeutralWhite() {
        let resolved = UIColor(Color.luminaPrimary)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(min(r, g, b) > 0.9)
        #expect(max(r, g, b) - min(r, g, b) < 0.05)
    }

    @Test("gradient start dark value is warm (red > blue), not cyan")
    func gradientStartDarkIsWarm() {
        let resolved = UIColor(Color.luminaGradientStart)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r > b)
    }

    /// Xcode's asset-catalog AccentColor is a separate color source from the
    /// `luminaPrimary` Swift token, so it is checked on its own: it must match
    /// the near-white neutral primary in dark mode, not the old cyan/teal.
    /// Uses Color("AccentColor") to resolve the named asset directly.
    @Test("asset-catalog AccentColor dark value is a near-white neutral, not cyan")
    func accentColorAssetDarkIsNeutralWhite() {
        let resolved = UIColor(Color("AccentColor"))
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(min(r, g, b) > 0.9)
        #expect(max(r, g, b) - min(r, g, b) < 0.05)
    }
}
