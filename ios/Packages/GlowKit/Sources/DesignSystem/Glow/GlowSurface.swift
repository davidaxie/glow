import SwiftUI

// Owner: B6. The glow: a full-screen color with a soft, flash-safe pulse.
//
//     GlowSurface(.aqua) {
//         VStack {
//             GlowCodeWord("lantern")
//             Text("Meet at the food line").glowFont(.headline)
//             Button("We met") { … }.buttonStyle(.glowOnSurface)
//         }
//     }
//
// While it's on screen it also turns brightness all the way up and keeps the screen awake, and puts
// both back when it goes away (or the app leaves the foreground). Text inside is drawn in the
// color's ink, which meets WCAG AA at every moment of the pulse (B6-D1, B6-D3).

@available(iOSApplicationExtension, unavailable)
public struct GlowSurface<Content: View>: View {
    private let hue: GlowHue
    private let isPulsing: Bool
    private let controlsScreen: Bool
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - isPulsing: false holds the bloom still, halfway.
    ///   - controlsScreen: false leaves brightness and the idle timer alone (for previews and the
    ///     Gallery).
    public init(_ hue: GlowHue, isPulsing: Bool = true, controlsScreen: Bool = true, @ViewBuilder content: () -> Content) {
        self.hue = hue
        self.isPulsing = isPulsing
        self.controlsScreen = controlsScreen
        self.content = content()
    }

    public var body: some View {
        ZStack {
            GlowBloom(hue: hue, isPulsing: isPulsing, reduceMotion: reduceMotion)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            content
                .foregroundStyle(hue.ink.color)
                .tint(hue.ink.color)
        }
        .environment(\.glowHue, hue)
        .glowFullBrightness(controlsScreen)
        .glowKeepAwake(controlsScreen)
    }
}

/// The color with its breathing bloom. Draws at most 30 frames a second, and nothing at all when
/// it isn't pulsing.
struct GlowBloom: View {
    let hue: GlowHue
    let isPulsing: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPulsing)) { timeline in
            let frame = isPulsing
                ? GlowPulse.frame(at: timeline.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion)
                : GlowPulse.Frame.resting
            GeometryReader { proxy in
                let radius = max(proxy.size.width, proxy.size.height) * 0.75 * frame.scale
                ZStack {
                    hue.color
                    RadialGradient(
                        colors: [Color.white.opacity(GlowPulse.bloomStrength * frame.opacity), Color.white.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: radius,
                    )
                }
            }
        }
    }
}

extension GlowPulse {
    /// One moment of the pulse.
    public struct Frame: Equatable, Sendable {
        /// How strong the bloom is, 0 to 1, times `bloomStrength`.
        public let opacity: Double
        /// The bloom's radius, as a share of its full size.
        public let scale: Double

        /// Halfway, standing still.
        public static let resting = Frame(opacity: 0.6, scale: 1)
    }

    /// The bloom at `time` seconds. A smooth cosine wave, so there's never a sudden change.
    /// Reduce Motion: the bloom only fades, more slowly, and never changes size.
    public static func frame(at time: TimeInterval, reduceMotion: Bool) -> Frame {
        let period = reduceMotion ? reducedPeriod : period
        let phase = time.truncatingRemainder(dividingBy: period) / period
        let wave = 0.5 - 0.5 * cos(2 * Double.pi * phase) // 0 → 1 → 0
        let opacity = 0.2 + 0.8 * wave
        let scale = reduceMotion ? 1 : 0.85 + 0.15 * wave
        return Frame(opacity: opacity, scale: scale)
    }
}

extension EnvironmentValues {
    /// The glow color behind this view, inside a `GlowSurface`.
    @Entry public var glowHue: GlowHue?
}

/// The code word, as big as it fits: New York, semibold, set tight (U1, DIRECTION.md), scaling with
/// Dynamic Type.
public struct GlowCodeWord: View {
    private let word: String
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 80

    public init(_ word: String) {
        self.word = word
    }

    public var body: some View {
        Text(verbatim: word)
            .font(.system(size: size, weight: .semibold, design: .serif))
            .tracking(-size * 0.02)
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .accessibilityLabel(Text("Code word: \(word)"))
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Buttons on a glow

/// A button on a glow color: filled with the color's ink, labelled in the color itself, so it has
/// the same contrast as the code word.
public struct GlowOnSurfaceButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        GlowOnSurfaceButtonBody(label: configuration.label, isPressed: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlowOnSurfaceButtonStyle {
    /// For buttons inside a `GlowSurface`.
    public static var glowOnSurface: GlowOnSurfaceButtonStyle {
        GlowOnSurfaceButtonStyle()
    }
}

struct GlowOnSurfaceButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool

    @Environment(\.glowHue) private var hue
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.glowIsLoading) private var isLoading
    @ScaledMetric(relativeTo: .body) private var height = GlowSize.buttonHeight

    var body: some View {
        let hue = hue ?? .pearl
        let shape = Capsule(style: .continuous)
        ZStack {
            label.opacity(isLoading ? 0 : 1)
            if isLoading {
                ProgressView().tint(hue.color).accessibilityHidden(true)
            }
        }
        .font(.glow(.button))
        .foregroundStyle(hue.color)
        .multilineTextAlignment(.center)
        .padding(.horizontal, GlowSpacing.lg)
        .padding(.vertical, GlowSpacing.xs)
        .frame(maxWidth: .infinity, minHeight: height)
        .background(hue.ink.color.opacity(isPressed ? 0.85 : 1), in: shape)
        .contentShape(shape)
        .opacity(isEnabled || isLoading ? 1 : 0.4)
        .animation(GlowMotion.ui, value: isPressed)
        .accessibilityValue(isLoading ? Text("In progress") : Text(verbatim: ""))
    }
}
