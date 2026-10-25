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

    // U1 (docs/design/DIRECTION.md): an editorial pairing. Display moments are set in New York
    // (the system serif), everything else in SF Pro.

    /// The biggest, quietest moments: an empty state's one sentence, a name at the reveal. New
    /// York, regular.
    case hero
    /// A screen title with an editorial voice. New York, regular.
    case titleSerif
    /// Blind mode's codenames. New York italic.
    case codename
    /// Numbers that change (countdowns, counters): monospaced digits. Pair with
    /// `.contentTransition(.numericText())`.
    case numeric
    /// A small label above a title. Pair with `.glowEyebrow()` for its tracking and case.
    case eyebrow

    public var id: String {
        rawValue
    }

    public var font: Font {
        switch self {
        case .display: .system(.largeTitle, design: .serif, weight: .semibold)
        case .hero: .system(.largeTitle, design: .serif, weight: .regular)
        case .titleSerif: .system(.title, design: .serif, weight: .regular)
        case .codename: .system(.title2, design: .serif, weight: .regular).italic()
        case .numeric: .system(.body, design: .default, weight: .semibold).monospacedDigit()
        case .eyebrow: .system(.caption, design: .default, weight: .semibold)
        case .title: .system(.title, design: .default, weight: .bold)
        case .headline: .system(.headline, design: .default, weight: .semibold)
        case .body: .system(.body, design: .default)
        case .callout: .system(.callout, design: .default)
        case .button: .system(.body, design: .default, weight: .semibold)
        case .chip: .system(.subheadline, design: .default, weight: .medium)
        case .footnote: .system(.footnote, design: .default)
        case .caption: .system(.caption, design: .default, weight: .medium)
        case .code: .system(.title, design: .rounded, weight: .semibold).monospacedDigit()
        case .codeWord: .system(.largeTitle, design: .serif, weight: .semibold)
        }
    }

    /// The system text style this one scales with, for `@ScaledMetric(relativeTo:)`.
    public var scalesWith: Font.TextStyle {
        switch self {
        case .display, .codeWord, .hero: .largeTitle
        case .title, .code, .titleSerif: .title
        case .codename: .title2
        case .headline: .headline
        case .body, .button, .numeric: .body
        case .callout: .callout
        case .chip: .subheadline
        case .footnote: .footnote
        case .caption, .eyebrow: .caption
        }
    }

    /// Letter spacing that suits this style at its default size: display serifs set a little
    /// tight, the eyebrow a little open. Apply with `.glowFont(_:)`, which does it for you.
    public var tracking: CGFloat {
        switch self {
        case .display, .hero, .codeWord: -0.6
        case .titleSerif: -0.3
        case .eyebrow: 1.2
        default: 0
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
    /// Sets a Glow text style: `Text("Hi").glowFont(.title)`. Display styles also get their tight
    /// tracking.
    public func glowFont(_ style: GlowTextStyle) -> some View {
        font(style.font).tracking(style.tracking)
    }

    /// The small label above a title: caption weight, uppercase, open tracking, warm grey.
    public func glowEyebrow() -> some View {
        font(GlowTextStyle.eyebrow.font)
            .tracking(GlowTextStyle.eyebrow.tracking)
            .textCase(.uppercase)
            .foregroundStyle(.glowTextSecondary)
    }
}
