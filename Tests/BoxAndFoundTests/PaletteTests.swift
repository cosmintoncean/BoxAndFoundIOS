import Testing
@testable import BoxAndFound

/// The palette is duplicated across three clients, and the only thing keeping
/// them together is a person remembering to change all three. These values are
/// transcribed from the web client's `css/style.css` (`:root` for light,
/// `[data-theme="dark"]` for dark); if someone edits `Palette.swift` without
/// touching the CSS, this fails and says which one moved.
@Suite("Palette parity with the web client")
struct PaletteTests {

    @Test("Brand colours are scheme-independent, as on the web")
    func brand() {
        #expect(PaletteHex.accent == 0xD4760A)
        #expect(PaletteHex.accentHover == 0xB8620A)
        #expect(PaletteHex.green == 0x2D8C26)
    }

    @Test("Light scheme matches :root")
    func light() {
        #expect(PaletteHex.Light.bg == 0xFAF8F4)
        #expect(PaletteHex.Light.bg2 == 0xF2EFE8)
        #expect(PaletteHex.Light.surface == 0xFFFFFF)
        #expect(PaletteHex.Light.surface2 == 0xF5F2EB)
        #expect(PaletteHex.Light.surface3 == 0xEDE9E0)
        #expect(PaletteHex.Light.border == 0xE4DDD0)
        #expect(PaletteHex.Light.borderStrong == 0xC8BFAA)
        #expect(PaletteHex.Light.text == 0x1C1A14)
        #expect(PaletteHex.Light.textMuted == 0x6E6454)
        #expect(PaletteHex.Light.accentSoft == 0xFFF8ED)
        #expect(PaletteHex.Light.greenSoft == 0xEDF7EC)
        #expect(PaletteHex.Light.danger == 0xC0392B)
        #expect(PaletteHex.Light.dangerSoft == 0xFDF0EE)
    }

    @Test("Dark scheme matches [data-theme=dark]")
    func dark() {
        #expect(PaletteHex.Dark.bg == 0x141210)
        #expect(PaletteHex.Dark.bg2 == 0x1C1A16)
        #expect(PaletteHex.Dark.surface == 0x201E1A)
        #expect(PaletteHex.Dark.surface2 == 0x2A2720)
        #expect(PaletteHex.Dark.surface3 == 0x343028)
        #expect(PaletteHex.Dark.border == 0x3A3630)
        #expect(PaletteHex.Dark.borderStrong == 0x504A40)
        #expect(PaletteHex.Dark.text == 0xF0ECE4)
        #expect(PaletteHex.Dark.textMuted == 0xA09080)
        #expect(PaletteHex.Dark.accentSoft == 0x2A1E0A)
        #expect(PaletteHex.Dark.greenSoft == 0x0E1E0C)
        #expect(PaletteHex.Dark.danger == 0xE05040)
        #expect(PaletteHex.Dark.dangerSoft == 0x2A1818)
    }
}
