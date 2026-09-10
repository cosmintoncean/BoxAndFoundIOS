import SwiftUI
import UIKit

/// Ported verbatim from the web client's CSS custom properties
/// (`css/style.css`) by way of the Android client's `Color.kt`, so a household
/// sees the same product on all three clients. Names mirror the CSS variable
/// names to keep the palettes diffable, and `PaletteTests` fails if they drift.
///
/// Raw hex rather than a colour asset catalogue on purpose: a catalogue would
/// be a fourth place the values live, and it cannot be diffed against the CSS
/// in a test.
enum PaletteHex {
    // Brand — identical in both schemes on the web, kept identical here.
    static let accent: UInt32 = 0xD4760A
    static let accentHover: UInt32 = 0xB8620A
    static let green: UInt32 = 0x2D8C26

    enum Light {
        static let bg: UInt32 = 0xFAF8F4
        static let bg2: UInt32 = 0xF2EFE8
        static let surface: UInt32 = 0xFFFFFF
        static let surface2: UInt32 = 0xF5F2EB
        static let surface3: UInt32 = 0xEDE9E0
        static let border: UInt32 = 0xE4DDD0
        static let borderStrong: UInt32 = 0xC8BFAA
        static let text: UInt32 = 0x1C1A14
        static let textMuted: UInt32 = 0x6E6454
        static let accentSoft: UInt32 = 0xFFF8ED
        static let greenSoft: UInt32 = 0xEDF7EC
        static let danger: UInt32 = 0xC0392B
        static let dangerSoft: UInt32 = 0xFDF0EE
    }

    enum Dark {
        static let bg: UInt32 = 0x141210
        static let bg2: UInt32 = 0x1C1A16
        static let surface: UInt32 = 0x201E1A
        static let surface2: UInt32 = 0x2A2720
        static let surface3: UInt32 = 0x343028
        static let border: UInt32 = 0x3A3630
        static let borderStrong: UInt32 = 0x504A40
        static let text: UInt32 = 0xF0ECE4
        static let textMuted: UInt32 = 0xA09080
        static let accentSoft: UInt32 = 0x2A1E0A
        static let greenSoft: UInt32 = 0x0E1E0C
        static let danger: UInt32 = 0xE05040
        static let dangerSoft: UInt32 = 0x2A1818
    }
}

extension Color {
    static let bfAccent = Color(hex: PaletteHex.accent)
    static let bfAccentHover = Color(hex: PaletteHex.accentHover)
    static let bfGreen = Color(hex: PaletteHex.green)

    static let bfBg = Color(light: PaletteHex.Light.bg, dark: PaletteHex.Dark.bg)
    static let bfBg2 = Color(light: PaletteHex.Light.bg2, dark: PaletteHex.Dark.bg2)
    static let bfSurface = Color(light: PaletteHex.Light.surface, dark: PaletteHex.Dark.surface)
    static let bfSurface2 = Color(light: PaletteHex.Light.surface2, dark: PaletteHex.Dark.surface2)
    static let bfSurface3 = Color(light: PaletteHex.Light.surface3, dark: PaletteHex.Dark.surface3)
    static let bfBorder = Color(light: PaletteHex.Light.border, dark: PaletteHex.Dark.border)
    static let bfBorderStrong = Color(light: PaletteHex.Light.borderStrong, dark: PaletteHex.Dark.borderStrong)
    static let bfText = Color(light: PaletteHex.Light.text, dark: PaletteHex.Dark.text)
    static let bfTextMuted = Color(light: PaletteHex.Light.textMuted, dark: PaletteHex.Dark.textMuted)
    static let bfAccentSoft = Color(light: PaletteHex.Light.accentSoft, dark: PaletteHex.Dark.accentSoft)
    static let bfGreenSoft = Color(light: PaletteHex.Light.greenSoft, dark: PaletteHex.Dark.greenSoft)
    static let bfDanger = Color(light: PaletteHex.Light.danger, dark: PaletteHex.Dark.danger)
    static let bfDangerSoft = Color(light: PaletteHex.Light.dangerSoft, dark: PaletteHex.Dark.dangerSoft)

    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// Resolves per trait collection rather than per `ColorScheme`, so the pair
    /// works in UIKit-backed surfaces too and does not need a view to read it.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
