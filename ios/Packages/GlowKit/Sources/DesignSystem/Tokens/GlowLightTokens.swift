import SwiftUI

// Owner: U1 (design wave). New tokens for "light as the language" (docs/design/DIRECTION.md): the
// canvas, layered glass, a third text tone, larger radii and the serif display type. All additive:
// every older token keeps its name.
//
//     ZStack { … }.glowCanvas()                                  // a full screen
//     VStack { … }.padding(GlowSpacing.lg).glowGlass()           // a lifted card
//     Text("Lantern").glowFont(.displaySerif)                    // a display moment, in New York

extension GlowPalette {
    /// The top of the canvas's vertical gradient: a breath warmer and lighter than `background`.
    public static let canvasTop = GlowRGB(0x14111A)
    /// The bottom of the canvas's vertical gradient: the background itself.
    public static let canvasBottom = background

    /// Glass cards: a lifted surface. Drawn at full opacity, so text contrast is exact.
    public static let glass = GlowRGB(0x1A1720)
    /// A pressed or selected glass card.
    public static let glassRaised = GlowRGB(0x25212B)

    /// Hints, placeholders and timestamps: a quieter warm grey that still meets 4.5:1 on every
    /// surface it's drawn on.
    public static let textTertiary = GlowRGB(0x8E8882)

    /// How bright the 1 px highlight on a glass card's top edge is (white, at this opacity).
    public static let glassHighlightOpacity = 0.09
    /// The hairline around a glass card (white, at this opacity).
    public static let glassStrokeOpacity = 0.05
    /// The film grain over full-screen canvases (white, at this opacity per grain). 2 to 3 percent.
    public static let grainOpacity = 0.025
}

extension ShapeStyle where Self == Color {
    /// Top of the canvas gradient, #14111A.
    public static var glowCanvasTop: Color {
        GlowPalette.canvasTop.color
    }

    /// Glass cards, #1A1720.
    public static var glowGlass: Color {
        GlowPalette.glass.color
    }

    /// Pressed or selected glass, #25212B.
    public static var glowGlassRaised: Color {
        GlowPalette.glassRaised.color
    }

    /// Hints, placeholders and timestamps, #8E8882.
    public static var glowTextTertiary: Color {
        GlowPalette.textTertiary.color
    }
}

extension GlowRadius {
    /// Sheets' top corners.
    public static let sheet: CGFloat = 20
    /// Deck cards and photo tiles.
    public static let tile: CGFloat = 24
    /// Glass cards and panels.
    public static let panel: CGFloat = 28
}

extension GlowSpacing {
    /// A roomier screen margin for editorial screens (welcome, empty states, the reveal).
    public static let screenMarginWide: CGFloat = 24
}
