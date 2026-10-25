import DesignSystem
import SwiftUI

// U3 (design revamp): the motion, light and type of the mutual moment, with the exact values from
// docs/design/DIRECTION.md. Module-local until U1's DesignSystem `Motion` presets and serif styles
// land; then these become aliases for them (docs/design/CHANGES.md). Presentation only.

enum Moment {
    /// `Motion.snappy`: small UI changes.
    static let snappy = Motion.snappy
    /// `Motion.smooth`: things arriving.
    static let smooth = Motion.smooth
    /// `Motion.gentle`: big, slow movement, like two lights drifting together.
    static let gentle = Motion.gentle
    /// The calm crossfade every movement turns into under Reduce Motion.
    static let fade = Motion.fade
    /// Between items appearing one after another.
    static let stagger = Motion.stagger
    /// A bloom of light: 600 ms, then settle.
    static let bloom = Animation.easeOut(duration: Motion.bloomDuration)
    /// One breath of a waiting state, in seconds (a resting heart rate).
    static let breathPeriod = Motion.breathPeriod

    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }

    /// 0 → 1 → 0 over one breath, a smooth cosine so it never jumps.
    static func breath(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: breathPeriod) / breathPeriod
        return 0.5 - 0.5 * cos(2 * Double.pi * phase)
    }

    /// New York, for display moments (names, the headline), scaling with Dynamic Type.
    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    /// New York at a fixed point size; pair it with `@ScaledMetric`.
    static func serif(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - Light

/// A soft point of light in the accent color: a bright core that fades to nothing.
struct MomentLight: View {
    var core = 0.95

    var body: some View {
        Circle()
            .fill(EllipticalGradient(
                stops: [
                    .init(color: GlowPalette.accent.mixed(with: .white, amount: 0.6).color.opacity(core), location: 0),
                    .init(color: GlowPalette.accent.color.opacity(0.6 * core), location: 0.22),
                    .init(color: GlowPalette.accent.color.opacity(0.18 * core), location: 0.55),
                    .init(color: GlowPalette.accent.color.opacity(0), location: 1),
                ],
                center: .center,
                startRadiusFraction: 0,
                endRadiusFraction: 0.5,
            ))
            .accessibilityHidden(true)
    }
}

/// Breathes at a resting heart rate: scale 1.0 to 1.03 and opacity 0.6 to 1.0 over 4 s. Only for
/// light, never for text, so contrast never drops. Under Reduce Motion it only fades.
struct MomentBreathing: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive)) { context in
            let wave = isActive ? Moment.breath(at: context.date) : 1
            content
                .scaleEffect(reduceMotion ? 1 : 1 + 0.03 * wave)
                .opacity(0.6 + 0.4 * wave)
        }
    }
}

/// Rises into place a beat after the item before it (40 ms stagger). Still when `isAnimated` is
/// false (snapshot tests), a plain fade under Reduce Motion.
struct MomentRise: ViewModifier {
    let index: Int
    let isShown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : 16)
            .animation(
                Moment.animation(Moment.smooth, reduceMotion: reduceMotion).delay(Double(index) * Moment.stagger),
                value: isShown,
            )
    }
}

extension View {
    func momentBreathing(_ isActive: Bool = true) -> some View {
        modifier(MomentBreathing(isActive: isActive))
    }

    func momentRise(_ index: Int, shown: Bool) -> some View {
        modifier(MomentRise(index: index, isShown: shown))
    }

    /// A small uppercase label above a display line: tracked caption type.
    func momentOverline() -> some View {
        glowFont(.caption)
            .textCase(.uppercase)
            .kerning(1.6)
    }
}

// MARK: - The stage

/// The takeover's room: warm near-black, one accent light, and a glass close button. The light
/// sits in the middle during the intro and rises behind the name once it's done.
struct MomentStage<Content: View>: View {
    let lightRisen: Bool
    @ViewBuilder let content: () -> Content
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [GlowPalette.surface.color, GlowPalette.background.color, GlowPalette.background.color],
                startPoint: .top,
                endPoint: .bottom,
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

            GeometryReader { proxy in
                let side = max(proxy.size.width, proxy.size.height)
                MomentLight(core: lightRisen ? 0.35 : 0)
                    .frame(width: side * (lightRisen ? 1.1 : 0.9), height: side * (lightRisen ? 1.1 : 0.9))
                    .position(x: proxy.size.width / 2, y: lightRisen ? -side * 0.12 : proxy.size.height * 0.4)
                    .opacity(lightRisen ? 0.75 : 0)
                    .momentBreathing(lightRisen)
            }
            .ignoresSafeArea()
            .animation(Moment.animation(Moment.gentle, reduceMotion: reduceMotion), value: lightRisen)
            .accessibilityHidden(true)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.glow(.headline))
                    .foregroundStyle(.glowTextPrimary)
                    .frame(width: GlowSize.minimumTapTarget, height: GlowSize.minimumTapTarget)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(GlowPalette.textPrimary.color.opacity(0.12), lineWidth: 1))
            }
            .accessibilityLabel(Text("Close"))
            .padding(.horizontal, GlowSpacing.md)
            .padding(.top, GlowSpacing.xs)
        }
    }
}

/// A waiting state that breathes instead of spinning.
struct MomentWaitingLight: View {
    let label: Text
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 120

    var body: some View {
        MomentLight(core: 0.7)
            .frame(width: size, height: size)
            .momentBreathing()
            .accessibilityElement()
            .accessibilityLabel(label)
    }
}
