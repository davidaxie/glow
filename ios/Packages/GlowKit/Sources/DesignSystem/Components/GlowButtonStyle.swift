import SwiftUI

// Owner: B6. Buttons: primary, secondary, quiet and danger, large or compact.
//
//     Button("Check in") { … }.buttonStyle(.glowPrimary)
//     Button("Not now") { … }.buttonStyle(.glowQuiet)
//     Button("Block", role: .destructive) { … }.buttonStyle(.glowDanger)
//     Button("Send") { … }.buttonStyle(.glow(.primary, size: .compact)).glowLoading(isSending)

public enum GlowButtonKind: String, CaseIterable, Identifiable, Sendable {
    /// The one main action on a screen. Accent fill.
    case primary
    /// Other actions. Raised surface with a hairline.
    case secondary
    /// Low-key actions like "Not now". Accent text, no fill.
    case quiet
    /// Block, report and delete. Danger fill.
    case danger

    public var id: String {
        rawValue
    }
}

public enum GlowButtonSize: String, CaseIterable, Sendable {
    /// Full width, 52 tall at the default text size.
    case large
    /// Fits its label, 44 tall at the default text size.
    case compact
}

/// The Glow button style.
public struct GlowButtonStyle: ButtonStyle {
    public let kind: GlowButtonKind
    public let size: GlowButtonSize

    public init(_ kind: GlowButtonKind = .primary, size: GlowButtonSize = .large) {
        self.kind = kind
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        GlowButtonBody(label: configuration.label, isPressed: configuration.isPressed, kind: kind, size: size)
    }
}

extension ButtonStyle where Self == GlowButtonStyle {
    public static var glowPrimary: GlowButtonStyle {
        GlowButtonStyle(.primary)
    }

    public static var glowSecondary: GlowButtonStyle {
        GlowButtonStyle(.secondary)
    }

    public static var glowQuiet: GlowButtonStyle {
        GlowButtonStyle(.quiet)
    }

    public static var glowDanger: GlowButtonStyle {
        GlowButtonStyle(.danger)
    }

    public static func glow(_ kind: GlowButtonKind, size: GlowButtonSize = .large) -> GlowButtonStyle {
        GlowButtonStyle(kind, size: size)
    }
}

extension View {
    /// Shows a spinner in Glow buttons inside this view and stops them being tapped again, without
    /// dimming them like a disabled button. VoiceOver hears "In progress".
    public func glowLoading(_ isLoading: Bool) -> some View {
        environment(\.glowIsLoading, isLoading).disabled(isLoading)
    }
}

extension EnvironmentValues {
    @Entry var glowIsLoading = false
}

/// Colors for one button kind in one state. Internal so tests can check them.
struct GlowButtonColors: Equatable {
    let foreground: GlowRGB
    let fill: GlowRGB?
    let border: GlowRGB?

    static func colors(for kind: GlowButtonKind, isPressed: Bool) -> GlowButtonColors {
        let lift = GlowPalette.pressedLift
        switch kind {
        case .primary:
            let fill = isPressed ? GlowPalette.accent.mixed(with: .white, amount: lift) : GlowPalette.accent
            return GlowButtonColors(foreground: GlowPalette.onAccent, fill: fill, border: nil)
        case .danger:
            let fill = isPressed ? GlowPalette.danger.mixed(with: .white, amount: lift) : GlowPalette.danger
            return GlowButtonColors(foreground: GlowPalette.onAccent, fill: fill, border: nil)
        case .secondary:
            return GlowButtonColors(
                foreground: GlowPalette.textPrimary,
                fill: isPressed ? GlowPalette.line : GlowPalette.surfaceRaised,
                border: GlowPalette.line,
            )
        case .quiet:
            return GlowButtonColors(foreground: GlowPalette.accent, fill: isPressed ? GlowPalette.surfaceRaised : nil, border: nil)
        }
    }
}

/// The button's look. Internal so the Gallery can draw the pressed state.
struct GlowButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let kind: GlowButtonKind
    let size: GlowButtonSize

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.glowIsLoading) private var isLoading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var largeHeight = GlowSize.buttonHeight
    @ScaledMetric(relativeTo: .body) private var compactHeight = GlowSize.compactButtonHeight
    @ScaledMetric(relativeTo: .body) private var horizontalPadding = GlowSpacing.lg

    private var colors: GlowButtonColors {
        .colors(for: kind, isPressed: isPressed)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GlowRadius.control, style: .continuous)
        ZStack {
            label
                .multilineTextAlignment(.center)
                .opacity(isLoading ? 0 : 1)
            if isLoading {
                ProgressView()
                    .tint(colors.foreground.color)
                    .accessibilityHidden(true)
            }
        }
        .font(.glow(.button))
        .foregroundStyle(colors.foreground.color)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, GlowSpacing.xs)
        .frame(maxWidth: size == .large ? .infinity : nil)
        .frame(minHeight: size == .large ? largeHeight : compactHeight)
        .background {
            if let fill = colors.fill {
                shape.fill(fill.color)
            }
        }
        .overlay {
            if let border = colors.border {
                shape.strokeBorder(border.color, lineWidth: 1)
            }
        }
        .contentShape(shape)
        // Disabled controls are exempt from WCAG contrast; loading ones stay at full strength.
        .opacity(isEnabled || isLoading ? 1 : 0.4)
        .scaleEffect(isPressed && !reduceMotion ? 0.98 : 1)
        .animation(GlowMotion.ui, value: isPressed)
        .accessibilityValue(isLoading ? Text("In progress") : Text(verbatim: ""))
    }
}
