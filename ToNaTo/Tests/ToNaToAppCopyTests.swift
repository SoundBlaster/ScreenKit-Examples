import Testing
@testable import ToNaTo

@Suite("ToNaTo App Copy")
struct ToNaToAppCopyTests {
    @Test("default copy is stable")
    func testDefaultCopy() async throws {
        #expect(ToNaToAppCopy.title == "ToNaTo")
        #expect(ToNaToAppCopy.tagline == "Compare price per unit in seconds.")
    }

    @Test("framework label identifies the modular stack")
    func testFrameworkDependenciesAreLinked() async throws {
        #expect(ToNaToAppCopy.frameworkLinkageLabel == "ScreenKit + Patchwork linked")
    }

    @Test("theme palette keeps brand and accent distinct")
    func themePaletteKeepsBrandAndAccentDistinct() async throws {
        #expect(ToNaToTheme.Palette.brand != ToNaToTheme.Palette.accent)
        #expect(ToNaToTheme.Palette.groupedBackground != ToNaToTheme.Palette.groupedCardBackground)
    }

    @Test("theme typography token sizes remain stable")
    func themeTypographyTokenSizesRemainStable() async throws {
        #expect(ToNaToTheme.Typography.aboutTitleSize == 34)
        #expect(ToNaToTheme.Typography.detailTitleSize == 24)
        #expect(ToNaToTheme.Typography.heroSubtitleSize == 22)
    }
}
