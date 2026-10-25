import SwiftUI

// Owner: U1 (design wave). The room every screen sits in, and the glass cards that float in it
// (docs/design/DIRECTION.md, "Visual system").
//
//     content.glowCanvas()                         // full screen: warm gradient, film grain
//     content.glowCanvas(light: .accent)           // …with a faint light gathered at the top
//     card.padding(GlowSpacing.lg).glowGlass()     // a lifted glass card, 28 pt corners

/// A soft light gathered at the top of a canvas, for screens that should feel warm (a joined
/// room, onboarding). Never behind text at more than a whisper, so contrast is unchanged.
public enum GlowAmbientLight: Equatable, Sendable {
    case none
    case accent
    case hue(GlowHue)

    var rgb: GlowRGB? {
        switch self {
        case .none: nil
        case .accent: GlowPalette.accent
        case let .hue(hue): hue.rgb
        }
    }

    /// The light's strength at its center.
    static let opacity = 0.16
}

/// The canvas: a warm near-black with a very subtle vertical gradient and a faint film grain, so
/// blacks feel rich, not flat. Fills the safe area.
public struct GlowCanvasBackground: View {
    private let light: GlowAmbientLight
    private let grain: Bool

    public init(light: GlowAmbientLight = .none, grain: Bool = true) {
        self.light = light
        self.grain = grain
    }

    public var body: some View {
        ZStack {
            LinearGradient(colors: [.glowCanvasTop, .glowBackground], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.65))
            if let rgb = light.rgb {
                GeometryReader { proxy in
                    RadialGradient(
                        colors: [rgb.color.opacity(GlowAmbientLight.opacity), rgb.color.opacity(0)],
                        center: UnitPoint(x: 0.5, y: -0.08),
                        startRadius: 0,
                        endRadius: max(proxy.size.width, proxy.size.height) * 0.6,
                    )
                }
            }
            if grain {
                GlowGrain()
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// Film grain: a fixed scatter of tiny specks at 2 to 3 percent, drawn once per size. Seeded, so
/// it's the same on every launch and in every snapshot.
struct GlowGrain: View {
    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            var generator = GlowSeededRandom(seed: 0x6C6F_7767)
            let count = Int(size.width * size.height / 90)
            for _ in 0 ..< count {
                let x = Double(generator.next() % 10000) / 10000 * size.width
                let y = Double(generator.next() % 10000) / 10000 * size.height
                let bright = generator.next() % 2 == 0
                let opacity = GlowPalette.grainOpacity * (bright ? 1.4 : 0.8)
                context.fill(
                    Path(CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(bright ? Color.white.opacity(opacity) : Color.black.opacity(opacity * 2)),
                )
            }
        }
        .drawingGroup()
    }
}

/// A tiny deterministic generator (SplitMix64), so the grain never shimmers between frames.
struct GlowSeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

// MARK: - Glass

/// A lifted glass surface: the glass fill, a 1 px highlight along the top edge, a hairline and a
/// soft shadow, with large continuous corners.
struct GlowGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isRaised: Bool
    let tint: GlowRGB?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(isRaised ? Color.glowGlassRaised : Color.glowGlass)
                    if let tint {
                        shape.fill(
                            LinearGradient(
                                colors: [tint.color.opacity(0.10), tint.color.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom,
                            ),
                        )
                    }
                }
                .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 14)
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(GlowPalette.glassHighlightOpacity),
                            Color.white.opacity(GlowPalette.glassStrokeOpacity),
                            Color.white.opacity(GlowPalette.glassStrokeOpacity * 0.5),
                        ],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                    lineWidth: 1,
                )
                .allowsHitTesting(false)
            }
    }
}

extension View {
    /// Puts this full-screen view on the canvas: the warm gradient and film grain, and optionally
    /// a faint light gathered at the top.
    public func glowCanvas(light: GlowAmbientLight = .none, grain: Bool = true) -> some View {
        background { GlowCanvasBackground(light: light, grain: grain) }
    }

    /// A lifted glass card behind this view. `isRaised` for pressed or selected; `tint` washes the
    /// top of the glass with a color (a match's hue), at a whisper.
    public func glowGlass(cornerRadius: CGFloat = GlowRadius.panel, isRaised: Bool = false, tint: GlowHue? = nil) -> some View {
        modifier(GlowGlassModifier(cornerRadius: cornerRadius, isRaised: isRaised, tint: tint?.rgb))
    }
}
