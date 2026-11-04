import SwiftUI
import CoreText

// MARK: - Manrope registration
//
// The target generates its Info.plist (GENERATE_INFOPLIST_FILE), which has
// no UIAppFonts build setting, so fonts are registered at runtime instead.

enum LuminaFonts {
    private static var didRegister = false

    /// Idempotent. Called from the App initializer (and from unit tests).
    static func registerAll() {
        guard !didRegister else { return }
        didRegister = true

        let names = ["ManropeExtraLight-Regular", "ManropeExtraLight-Medium", "ManropeExtraLight-SemiBold",
                     "ManropeExtraLight-Bold", "ManropeExtraLight-ExtraBold"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                assertionFailure("Missing bundled font \(name).ttf")
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

// MARK: - Navigation bar type
//
// UIKit owns navigation titles, so SwiftUI fonts never reach them. Applied
// once at launch (after fonts register) so every screen's large and inline
// titles use the same heavy Manrope as in-content headings.

extension LuminaFonts {
    static func applyNavigationBarAppearance() {
        // Matches `luminaOnSurface` in both modes.
        let ink = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255, alpha: 1)
            : UIColor(red: 0x1E / 255, green: 0x1D / 255, blue: 0x1A / 255, alpha: 1) }
        let bar = UINavigationBar.appearance()
        if let large = UIFont(name: "ManropeExtraLight-ExtraBold", size: 34) {
            bar.largeTitleTextAttributes = [
                .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large),
                .foregroundColor: ink,
                .kern: -0.6,
            ]
        }
        if let inline = UIFont(name: "ManropeExtraLight-Bold", size: 17) {
            bar.titleTextAttributes = [
                .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline),
                .foregroundColor: ink,
            ]
        }
    }
}

// MARK: - Semantic type scale
//
// Warm editorial restyle (seperate-main): headings in heavy Manrope — the
// tight geometric display type of the reference — with SF Pro for body
// copy and small labels, where it reads cleaner at small sizes.

extension Font {
    static let luminaDisplay     = Font.custom("ManropeExtraLight-ExtraBold", size: 36, relativeTo: .largeTitle)
    static let luminaHeadline    = Font.custom("ManropeExtraLight-ExtraBold", size: 28, relativeTo: .title)
    static let luminaTitle       = Font.custom("ManropeExtraLight-Bold",      size: 22, relativeTo: .title2)
    static let luminaCardTitle   = Font.custom("ManropeExtraLight-Bold",      size: 17, relativeTo: .headline)
    static let luminaBody        = Font.system(.body)
    static let luminaSubheadline = Font.system(.subheadline)
    static let luminaLabel       = Font.system(.footnote, weight: .semibold)
    static let luminaCaption     = Font.system(.caption, weight: .medium)
}
