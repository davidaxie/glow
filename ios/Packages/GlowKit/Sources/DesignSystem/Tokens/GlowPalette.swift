import SwiftUI

// Owner: B6. The color tokens from docs/SPEC.md ("Design system"). B7 mirrors the same hex values
// as CSS variables for the admin web, so change a value here and tell B7 in docs/HANDOFFS.md.
//
// Feature modules never build their own colors (SwiftLint fails `Color(...)`, `UIColor` and named
// system colors there). Use these instead:
//
//     Text("Hi").foregroundStyle(.glowTextSecondary)
//     .background(.glowSurface, in: .rect(cornerRadius: GlowRadius.card))

/// An exact sRGB color, written the way the spec writes it (`#0B0B10`), so tests can check contrast
/// on the real values.
public struct GlowRGB: Hashable, Sendable, CustomStringConvertible {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    /// `GlowRGB(0xFF4FA3)`.
    public init(_ hex: UInt32) {
        red = UInt8((hex >> 16) & 0xFF)
        green = UInt8((hex >> 8) & 0xFF)
        blue = UInt8(hex & 0xFF)
    }

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `#RRGGBB`, uppercase, the format the spec and the admin CSS use.
    public var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    public var description: String {
        hex
    }

    public var color: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: 1)
    }

    /// This color moved `amount` (0 to 1) of the way toward `other`, per channel in sRGB, the way
    /// the screen composites an overlay at that opacity.
    public func mixed(with other: GlowRGB, amount: Double) -> GlowRGB {
        let amount = min(max(amount, 0), 1)
        func channel(_ from: UInt8, _ to: UInt8) -> UInt8 {
            UInt8((Double(from) + (Double(to) - Double(from)) * amount).rounded())
        }
        return GlowRGB(red: channel(red, other.red), green: channel(green, other.green), blue: channel(blue, other.blue))
    }

    public static let black = GlowRGB(0x000000)
    public static let white = GlowRGB(0xFFFFFF)
}

/// The app's colors. The app is always dark: there is no light variant.
public enum GlowPalette {
    // The neutrals are warm (U1-D1, docs/design/DIRECTION.md): a warm near-black canvas, never
    // pure #000, and warm grey text, never blue grey. Same luminance as before, so contrast holds.

    /// App background: a warm near-black.
    public static let background = GlowRGB(0x0B0A0F)
    /// Cards and sheets.
    public static let surface = GlowRGB(0x17151C)
    /// Pressed and raised elements.
    public static let surfaceRaised = GlowRGB(0x221F27)
    /// Main text: a warm white.
    public static let textPrimary = GlowRGB(0xF5F3F0)
    /// Secondary text: a warm grey.
    public static let textSecondary = GlowRGB(0xA9A39D)
    /// Dividers.
    public static let line = GlowRGB(0x2D2931)
    /// Primary buttons and focus.
    public static let accent = GlowRGB(0xFF4FA3)
    /// Block, report and delete.
    public static let danger = GlowRGB(0xFF5A5F)

    /// Text and icons on an accent or danger fill. White on #FF4FA3 is only 2.8:1, so filled
    /// buttons and selected chips use the background color as ink (6.4:1). See docs/DECISIONS.md.
    public static let onAccent = background

    /// How much white a filled control mixes in while pressed. Pressing lightens rather than
    /// darkens, so dark ink only gains contrast.
    public static let pressedLift = 0.12

    /// Every token by its spec name, in the spec's order. B7's CSS variables use these names.
    public static let tokens: [GlowColorToken] = [
        GlowColorToken(name: "background", rgb: background),
        GlowColorToken(name: "surface", rgb: surface),
        GlowColorToken(name: "surfaceRaised", rgb: surfaceRaised),
        GlowColorToken(name: "textPrimary", rgb: textPrimary),
        GlowColorToken(name: "textSecondary", rgb: textSecondary),
        GlowColorToken(name: "line", rgb: line),
        GlowColorToken(name: "accent", rgb: accent),
        GlowColorToken(name: "danger", rgb: danger),
    ]
}

/// A named color token.
public struct GlowColorToken: Hashable, Sendable, Identifiable {
    public let name: String
    public let rgb: GlowRGB

    public var id: String {
        name
    }
}

// MARK: - SwiftUI tokens

extension ShapeStyle where Self == Color {
    /// App background, #0B0A0F. For full screens prefer `.glowCanvas()`, which adds the gradient
    /// and grain.
    public static var glowBackground: Color {
        GlowPalette.background.color
    }

    /// Cards and sheets, #17151C. For lifted cards prefer `.glowGlass()`.
    public static var glowSurface: Color {
        GlowPalette.surface.color
    }

    /// Pressed and raised elements, #221F27.
    public static var glowSurfaceRaised: Color {
        GlowPalette.surfaceRaised.color
    }

    /// Main text, #F5F3F0.
    public static var glowTextPrimary: Color {
        GlowPalette.textPrimary.color
    }

    /// Secondary text, #A9A39D.
    public static var glowTextSecondary: Color {
        GlowPalette.textSecondary.color
    }

    /// Dividers, #2D2931.
    public static var glowLine: Color {
        GlowPalette.line.color
    }

    /// Primary buttons and focus, #FF4FA3.
    public static var glowAccent: Color {
        GlowPalette.accent.color
    }

    /// Block, report and delete, #FF5A5F.
    public static var glowDanger: Color {
        GlowPalette.danger.color
    }

    /// Text and icons on an accent or danger fill.
    public static var glowOnAccent: Color {
        GlowPalette.onAccent.color
    }

    /// See-through. Allowed in features too, for hit areas and spacers.
    public static var glowClear: Color {
        Color.clear
    }
}
