import SwiftUI

// Owner: B6. The eight glow colors from docs/SPEC.md, and the swatches for clothing and hair tags.

/// A glow color. The raw values are the contract's `GlowColor` names, so a glow session maps
/// straight across:
///
///     let hue = GlowHue(rawValue: session.color.rawValue) ?? .pearl
public enum GlowHue: String, CaseIterable, Identifiable, Sendable {
    case ember, rose, violet, sky, aqua, lime, sun, pearl

    public var id: String {
        rawValue
    }

    public var rgb: GlowRGB {
        switch self {
        case .ember: GlowRGB(0xFF6B2C)
        case .rose: GlowRGB(0xFF3D8B)
        case .violet: GlowRGB(0x8C5BFF)
        case .sky: GlowRGB(0x2F8CFF)
        case .aqua: GlowRGB(0x12D6C5)
        case .lime: GlowRGB(0x9BE52E)
        case .sun: GlowRGB(0xFFD23F)
        case .pearl: GlowRGB(0xF2F2F7)
        }
    }

    public var color: Color {
        rgb.color
    }

    /// The color's name, for VoiceOver and for telling the other person which color to look for.
    public var name: String {
        switch self {
        case .ember: String(localized: "Ember")
        case .rose: String(localized: "Rose")
        case .violet: String(localized: "Violet")
        case .sky: String(localized: "Sky")
        case .aqua: String(localized: "Aqua")
        case .lime: String(localized: "Lime")
        case .sun: String(localized: "Sun")
        case .pearl: String(localized: "Pearl")
        }
    }

    /// Text drawn on this color: the code word, the meeting spot, the countdown.
    ///
    /// The spec puts white on Ember, Rose, Violet and Sky, but white on those is 2.8 to 4.2:1, under
    /// WCAG AA for normal text (and Ember is under 3:1 even for large text). Dark ink is 4.7:1 or
    /// better on all eight, at every Dynamic Type size. See docs/DECISIONS.md.
    public var ink: GlowRGB {
        GlowPalette.background
    }

    /// The bloom at the brightest point of the pulse: this color with some white mixed in.
    public var bloomPeak: GlowRGB {
        rgb.mixed(with: .white, amount: GlowPulse.bloomStrength)
    }
}

/// A clothing or hair color shown as a small dot next to a tag. Raw values are the contract's
/// `TopColor` and `HairColor` names (`GlowSwatch(rawValue: tags.topColor.rawValue)`).
///
/// A swatch never carries meaning on its own: it always sits next to the color's name.
public enum GlowSwatch: String, CaseIterable, Identifiable, Sendable {
    case black, white, gray, red, pink, orange, yellow, green, blue, purple
    case brown, blonde, dyed

    public var id: String {
        rawValue
    }

    /// The dot's fill. `dyed` is drawn as a gradient of these stops instead.
    public var rgb: GlowRGB {
        switch self {
        case .black: GlowRGB(0x111114)
        case .white: GlowRGB(0xF7F7F7)
        case .gray: GlowRGB(0x8E8E96)
        case .red: GlowRGB(0xE5383B)
        case .pink: GlowRGB(0xF48FB1)
        case .orange: GlowRGB(0xF5862E)
        case .yellow: GlowRGB(0xF6D03F)
        case .green: GlowRGB(0x3FAE5A)
        case .blue: GlowRGB(0x3A7BEA)
        case .purple: GlowRGB(0x8E5CD9)
        case .brown: GlowRGB(0x7B5235)
        case .blonde: GlowRGB(0xE8C77D)
        case .dyed: GlowRGB(0xC05BD8)
        }
    }

    /// Stops for the `dyed` gradient.
    static let dyedStops: [GlowRGB] = [GlowRGB(0x2F8CFF), GlowRGB(0xC05BD8), GlowRGB(0xFF3D8B), GlowRGB(0x12D6C5)]

    var style: AnyShapeStyle {
        if self == .dyed {
            AnyShapeStyle(AngularGradient(colors: Self.dyedStops.map(\.color) + [Self.dyedStops[0].color], center: .center))
        } else {
            AnyShapeStyle(rgb.color)
        }
    }
}

/// A round swatch dot with a hairline ring, so black shows on the dark app and white on Pearl.
public struct GlowSwatchDot: View {
    private let swatch: GlowSwatch
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 14

    public init(_ swatch: GlowSwatch) {
        self.swatch = swatch
    }

    public var body: some View {
        Circle()
            .fill(swatch.style)
            .overlay(Circle().strokeBorder(.glowTextSecondary.opacity(0.6), lineWidth: 1))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
