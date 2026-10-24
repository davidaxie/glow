import SwiftUI

// Owner: B6. Type from docs/SPEC.md: SF Pro, SF Pro Rounded for the code word, Dynamic Type
// everywhere. Every style is built on a system text style, so it scales with the person's text size.
//
// Feature modules never pick fonts themselves (SwiftLint fails `.font(.body)`, `Font.system` and
// `UIFont` there). Use these instead:
//
//     Text("Pick what you noticed").glowFont(.title)
//     Label("Glasses", systemImage: "eyeglasses").font(.glow(.callout))

/// A text style. Each one scales with Dynamic Type.
public enum GlowTextStyle: String, CaseIterable, Identifiable, Sendable {
    /// Takeover headlines, like the mutual moment.
    case display
    /// Screen titles.
    case title
    /// Sheet titles and section headers.
    case headline
    /// Running text.
    case body
    /// Body text that sits a little quieter, like explanations under a title.
    case callout
    /// Labels on buttons.
    case button
    /// Chips and tags.
    case chip
    /// Small print, like footnotes under a form.
    case footnote
    /// Captions on cards.
    case caption
    /// One character of a code entry field (room codes, email codes).
    case code
    /// The glow code word. Use `GlowCodeWord` for the huge on-surface version.
    case codeWord

    public var id: String {
        rawValue
    }

    public var font: Font {
        switch self {
        case .display: .system(.largeTitle, design: .default, weight: .bold)
        case .title: .system(.title, design: .default, weight: .bold)
        case .headline: .system(.headline, design: .default, weight: .semibold)
        case .body: .system(.body, design: .default)
        case .callout: .system(.callout, design: .default)
        case .button: .system(.body, design: .default, weight: .semibold)
        case .chip: .system(.subheadline, design: .default, weight: .medium)
        case .footnote: .system(.footnote, design: .default)
        case .caption: .system(.caption, design: .default, weight: .medium)
        case .code: .system(.title, design: .rounded, weight: .semibold).monospacedDigit()
        case .codeWord: .system(.largeTitle, design: .rounded, weight: .heavy)
        }
    }

    /// The system text style this one scales with, for `@ScaledMetric(relativeTo:)`.
    public var scalesWith: Font.TextStyle {
        switch self {
        case .display, .codeWord: .largeTitle
        case .title, .code: .title
        case .headline: .headline
        case .body, .button: .body
        case .callout: .callout
        case .chip: .subheadline
        case .footnote: .footnote
        case .caption: .caption
        }
    }
}

extension Font {
    /// A Glow text style as a font: `.font(.glow(.headline))`.
    public static func glow(_ style: GlowTextStyle) -> Font {
        style.font
    }
}

extension View {
    /// Sets a Glow text style: `Text("Hi").glowFont(.title)`.
    public func glowFont(_ style: GlowTextStyle) -> some View {
        font(style.font)
    }
}
