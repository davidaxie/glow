import Foundation

// Owner: B6. WCAG 2.2 contrast math, so "All text meets WCAG AA" is a test, not a promise.
// https://www.w3.org/TR/WCAG22/#dfn-contrast-ratio

public enum GlowContrast {
    /// WCAG AA for normal text. Every text pairing in the app meets this, at every Dynamic Type
    /// size, so nothing relies on the large-text exception.
    public static let minimumTextRatio = 4.5

    /// WCAG relative luminance, 0 (black) to 1 (white).
    public static func relativeLuminance(_ rgb: GlowRGB) -> Double {
        func linear(_ channel: UInt8) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
    }

    /// The contrast ratio between two colors, 1 to 21. Order doesn't matter.
    public static func ratio(_ first: GlowRGB, _ second: GlowRGB) -> Double {
        let lighter = max(relativeLuminance(first), relativeLuminance(second))
        let darker = min(relativeLuminance(first), relativeLuminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }
}

/// One way the design system draws text: this foreground on this background.
public struct GlowTextPairing: Sendable, CustomStringConvertible {
    public let foreground: GlowRGB
    public let background: GlowRGB
    public let usage: String

    public init(_ foreground: GlowRGB, on background: GlowRGB, usage: String) {
        self.foreground = foreground
        self.background = background
        self.usage = usage
    }

    public var ratio: Double {
        GlowContrast.ratio(foreground, background)
    }

    public var description: String {
        "\(usage): \(foreground.hex) on \(background.hex) is \(String(format: "%.2f", ratio)):1"
    }
}

extension GlowPalette {
    /// Every text and background combination the components draw. `GlowContrastTests` checks each
    /// one against WCAG AA. Add a line here whenever a component draws text somewhere new.
    public static var textPairings: [GlowTextPairing] {
        let pressedAccent = accent.mixed(with: .white, amount: pressedLift)
        let pressedDanger = danger.mixed(with: .white, amount: pressedLift)
        var pairings: [GlowTextPairing] = []
        for (name, ground) in [("background", background), ("surface", surface), ("surfaceRaised", surfaceRaised)] {
            pairings += [
                GlowTextPairing(textPrimary, on: ground, usage: "textPrimary on \(name)"),
                GlowTextPairing(textSecondary, on: ground, usage: "textSecondary on \(name)"),
                GlowTextPairing(accent, on: ground, usage: "accent (quiet buttons, links) on \(name)"),
                GlowTextPairing(danger, on: ground, usage: "danger (errors) on \(name)"),
            ]
        }
        // U1: the canvas's lighter top and glass cards.
        for (name, ground) in [("canvasTop", canvasTop), ("glass", glass), ("glassRaised", glassRaised)] {
            pairings += [
                GlowTextPairing(textPrimary, on: ground, usage: "textPrimary on \(name)"),
                GlowTextPairing(textSecondary, on: ground, usage: "textSecondary on \(name)"),
                GlowTextPairing(accent, on: ground, usage: "accent on \(name)"),
            ]
        }
        for (name, ground) in [("background", background), ("surface", surface), ("canvasTop", canvasTop), ("glass", glass)] {
            pairings.append(GlowTextPairing(textTertiary, on: ground, usage: "textTertiary (hints) on \(name)"))
        }
        pairings += [
            GlowTextPairing(textPrimary, on: line, usage: "textPrimary on line (pressed secondary button)"),
            GlowTextPairing(onAccent, on: accent, usage: "onAccent on accent (primary button, selected chip)"),
            GlowTextPairing(onAccent, on: pressedAccent, usage: "onAccent on pressed accent"),
            GlowTextPairing(onAccent, on: danger, usage: "onAccent on danger (danger button)"),
            GlowTextPairing(onAccent, on: pressedDanger, usage: "onAccent on pressed danger"),
            GlowTextPairing(
                textPrimary,
                on: background.mixed(with: accent, amount: GlowBackdrop.bloomOpacity),
                usage: "textPrimary on the takeover bloom at its brightest",
            ),
        ]
        return pairings
    }
}
