import SwiftUI

// Owner: B6. A capsule chip that toggles, for tags and filters.
//
//     GlowChip("Glasses", systemImage: "eyeglasses", isSelected: picked) { picked.toggle() }
//     GlowChip("Green", swatch: .green, isSelected: color == .green) { color = .green }

/// A capsule toggle. Selected chips get the accent fill and a checkmark, so the state never rests
/// on color alone, and VoiceOver hears "Selected".
public struct GlowChip: View {
    private let title: Text
    private let systemImage: String?
    private let swatch: GlowSwatch?
    private let isSelected: Bool
    private let action: () -> Void

    public init(
        _ titleKey: LocalizedStringKey,
        systemImage: String? = nil,
        swatch: GlowSwatch? = nil,
        isSelected: Bool,
        action: @escaping () -> Void,
    ) {
        title = Text(titleKey)
        self.systemImage = systemImage
        self.swatch = swatch
        self.isSelected = isSelected
        self.action = action
    }

    /// A chip with text that's already localized, like a tag name from a lookup table.
    @_disfavoredOverload
    public init(
        _ title: some StringProtocol,
        systemImage: String? = nil,
        swatch: GlowSwatch? = nil,
        isSelected: Bool,
        action: @escaping () -> Void,
    ) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.swatch = swatch
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: GlowSpacing.xs) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.glow(.caption))
                        .accessibilityHidden(true)
                }
                if let swatch {
                    GlowSwatchDot(swatch)
                }
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                title
            }
        }
        .buttonStyle(GlowChipStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The chip look, for anything that should read as a chip. `GlowChip` uses it.
public struct GlowChipStyle: ButtonStyle {
    public let isSelected: Bool

    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    public func makeBody(configuration: Configuration) -> some View {
        GlowChipBody(label: configuration.label, isSelected: isSelected, isPressed: configuration.isPressed)
    }
}

/// Chip colors for one state. Internal so tests can check them.
struct GlowChipColors: Equatable {
    let foreground: GlowRGB
    let fill: GlowRGB
    let border: GlowRGB?

    static func colors(isSelected: Bool, isPressed: Bool) -> GlowChipColors {
        if isSelected {
            let fill = isPressed ? GlowPalette.accent.mixed(with: .white, amount: GlowPalette.pressedLift) : GlowPalette.accent
            return GlowChipColors(foreground: GlowPalette.onAccent, fill: fill, border: nil)
        }
        return GlowChipColors(
            foreground: GlowPalette.textPrimary,
            fill: isPressed ? GlowPalette.surfaceRaised : GlowPalette.surface,
            border: GlowPalette.line,
        )
    }
}

/// The chip's look. Internal so the Gallery can draw the pressed state.
struct GlowChipBody<Label: View>: View {
    let label: Label
    let isSelected: Bool
    let isPressed: Bool

    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .subheadline) private var height = GlowSize.chipHeight
    @ScaledMetric(relativeTo: .subheadline) private var horizontalPadding = GlowSpacing.md

    var body: some View {
        let colors = GlowChipColors.colors(isSelected: isSelected, isPressed: isPressed)
        label
            .font(.glow(.chip))
            .foregroundStyle(colors.foreground.color)
            .lineLimit(2)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, GlowSpacing.xxs)
            .frame(minHeight: height)
            .background(colors.fill.color, in: Capsule())
            .overlay {
                if let border = colors.border {
                    Capsule().strokeBorder(border.color, lineWidth: 1)
                }
            }
            // The visible chip is 36 tall; the hit area is 44.
            .padding(.vertical, max(0, (GlowSize.minimumTapTarget - height) / 2))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
            .animation(GlowMotion.ui, value: isSelected)
    }
}
