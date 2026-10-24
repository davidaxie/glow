import Testing
@testable import DesignSystem

/// "All text meets WCAG AA contrast" (B6 brief), checked on the real token values.
struct ContrastTests {
    @Test func theMathMatchesWCAG() {
        #expect(GlowContrast.ratio(.black, .white) == 21)
        #expect(GlowContrast.ratio(.white, .white) == 1)
        #expect(abs(GlowContrast.relativeLuminance(GlowRGB(0x808080)) - 0.2158605) < 0.000_01)
        // Order doesn't matter.
        let accent = GlowPalette.accent, background = GlowPalette.background
        #expect(GlowContrast.ratio(accent, background) == GlowContrast.ratio(background, accent))
    }

    @Test(arguments: GlowPalette.textPairings)
    func everyTextPairingMeetsAA(_ pairing: GlowTextPairing) {
        #expect(pairing.ratio >= GlowContrast.minimumTextRatio, "\(pairing)")
    }

    @Test(arguments: GlowButtonKind.allCases, [false, true])
    func buttonLabelsMeetAA(_ kind: GlowButtonKind, isPressed: Bool) {
        let colors = GlowButtonColors.colors(for: kind, isPressed: isPressed)
        // A button without a fill sits on any of the three grounds.
        let grounds = colors.fill.map { [$0] } ?? [GlowPalette.background, GlowPalette.surface, GlowPalette.surfaceRaised]
        for ground in grounds {
            let ratio = GlowContrast.ratio(colors.foreground, ground)
            #expect(ratio >= GlowContrast.minimumTextRatio, "\(kind) pressed=\(isPressed): \(ratio)")
        }
    }

    @Test(arguments: [false, true], [false, true])
    func chipLabelsMeetAA(isSelected: Bool, isPressed: Bool) {
        let colors = GlowChipColors.colors(isSelected: isSelected, isPressed: isPressed)
        #expect(GlowContrast.ratio(colors.foreground, colors.fill) >= GlowContrast.minimumTextRatio)
    }

    @Test(arguments: GlowToastMessage.Kind.allCases)
    func toastTextMeetsAA(_: GlowToastMessage.Kind) {
        #expect(GlowContrast.ratio(GlowPalette.textPrimary, GlowPalette.surfaceRaised) >= GlowContrast.minimumTextRatio)
    }

    @Test(arguments: GlowHue.allCases)
    func inkOnEveryGlowColorMeetsAAThroughTheWholePulse(_ hue: GlowHue) {
        // The pulse only ever adds white, so the base color and the bloom's peak are the two ends.
        #expect(GlowContrast.ratio(hue.ink, hue.rgb) >= GlowContrast.minimumTextRatio, "\(hue) at rest")
        #expect(GlowContrast.ratio(hue.ink, hue.bloomPeak) >= GlowContrast.minimumTextRatio, "\(hue) at the bloom's peak")
    }

    @Test(arguments: GlowHue.allCases)
    func thePulseNeverDimsBelow70Percent(_ hue: GlowHue) {
        let rest = GlowContrast.relativeLuminance(hue.rgb)
        let peak = GlowContrast.relativeLuminance(hue.bloomPeak)
        #expect(rest / peak >= GlowPulse.minimumLuminanceRatio, "\(hue): \(rest / peak)")
    }

    @Test func thePulseIsSlowerThanOncePerSecond() {
        #expect(GlowPulse.frequency(reduceMotion: false) < 1)
        #expect(GlowPulse.frequency(reduceMotion: true) < GlowPulse.frequency(reduceMotion: false))
        #expect(GlowPulse.period == 1.25)
    }
}
