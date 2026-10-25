import SwiftUI

// Owner: U1 (design wave). The motion system from docs/design/DIRECTION.md, with its exact numbers,
// so every screen moves as if one hand made it.
//
//     .glowMotion(.snappy, value: isSelected)            // a spring that follows Reduce Motion
//     Motion.animate(.smooth) { isOpen = true }          // the same, from an action
//     card.glowRise(index: i, isVisible: appeared)       // a staggered rise, 40 ms apart
//     Circle().glowBreathing()                           // a waiting state: a 4 s breath
//
// Springs only for movement. Opacity-only fades may use `Motion.fade`. Under Reduce Motion every
// preset becomes a calm crossfade (`Motion.fade`), and nothing moves or scales.

/// The motion presets. Each is a SwiftUI `Animation`; prefer the view helpers below, which honor
/// Reduce Motion on their own.
public enum Motion {
    /// Selections, toggles, small things that answer a touch. `spring(response: 0.35, dampingFraction: 0.86)`.
    public static var snappy: Animation {
        .spring(response: Spring.snappy.response, dampingFraction: Spring.snappy.dampingFraction)
    }

    /// Most UI movement: sheets, cards, screens settling. `spring(response: 0.5, dampingFraction: 0.9)`.
    public static var smooth: Animation {
        .spring(response: Spring.smooth.response, dampingFraction: Spring.smooth.dampingFraction)
    }

    /// Big, slow arrivals: the glow filling the screen, a veil lifting. `spring(response: 0.8, dampingFraction: 0.95)`.
    public static var gentle: Animation {
        .spring(response: Spring.gentle.response, dampingFraction: Spring.gentle.dampingFraction)
    }

    /// Opacity-only changes, and every preset under Reduce Motion. `easeOut(duration: 0.25)`.
    public static var fade: Animation {
        .easeOut(duration: fadeDuration)
    }

    /// Seconds of `fade`.
    public static let fadeDuration: Double = 0.25

    /// Seconds between items of a list or a set of cards appearing.
    public static let stagger: Double = 0.04

    /// A waiting state's breath: one in-and-out cycle, in seconds (a resting heart rate's calm).
    public static let breathPeriod: Double = 4
    /// The breath's scale, from rest to full.
    public static let breathScale: ClosedRange<Double> = 1.0 ... 1.03
    /// The breath's glow opacity, from rest to full.
    public static let breathOpacity: ClosedRange<Double> = 0.6 ... 1.0

    /// An important arrival's bloom: a radial light from the touch, then it settles.
    public static let bloomDuration: Double = 0.6

    /// The gap between the heartbeat haptic's two soft beats.
    public static let heartbeatGap: Double = 0.12

    /// Blind mode's reveal: the veil dissolves from the center outward over this long.
    public static let veilLiftDuration: Double = 1.2

    /// The numbers behind a spring preset, so tests and non-SwiftUI code can read them.
    public struct Spring: Equatable, Sendable {
        public let response: Double
        public let dampingFraction: Double

        public static let snappy = Spring(response: 0.35, dampingFraction: 0.86)
        public static let smooth = Spring(response: 0.5, dampingFraction: 0.9)
        public static let gentle = Spring(response: 0.8, dampingFraction: 0.95)
    }

    /// A named preset, for the view helpers.
    public enum Preset: String, CaseIterable, Sendable {
        case snappy
        case smooth
        case gentle
        case fade

        /// The animation, or a crossfade under Reduce Motion.
        public func animation(reduceMotion: Bool) -> Animation {
            if reduceMotion {
                return Motion.fade
            }
            switch self {
            case .snappy: return Motion.snappy
            case .smooth: return Motion.smooth
            case .gentle: return Motion.gentle
            case .fade: return Motion.fade
            }
        }
    }

    /// `preset`, delayed for the `index`th item of a staggered set (40 ms apart).
    public static func staggered(_ preset: Preset, index: Int, reduceMotion: Bool) -> Animation {
        preset.animation(reduceMotion: reduceMotion).delay(Double(max(index, 0)) * stagger)
    }

    /// Runs `body` inside `preset`, honoring the system's Reduce Motion setting. For actions, where
    /// the environment isn't at hand.
    @MainActor
    public static func animate<Result>(_ preset: Preset, _ body: () throws -> Result) rethrows -> Result {
        try withAnimation(preset.animation(reduceMotion: UIAccessibility.isReduceMotionEnabled), body)
    }

    /// The transition for something entering or leaving: rising a little and fading, or only
    /// fading under Reduce Motion.
    public static func rise(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: riseDistance)).combined(with: .scale(scale: 0.98))
    }

    /// How far a rising item travels, in points.
    public static let riseDistance: CGFloat = 12
}

// MARK: - Breathing

/// One moment of a breath, as plain numbers so its shape can be tested.
public struct GlowBreath: Equatable, Sendable {
    public let scale: Double
    public let opacity: Double

    /// At rest: the start of a cycle.
    public static let rest = GlowBreath(scale: Motion.breathScale.lowerBound, opacity: Motion.breathOpacity.lowerBound)

    /// The breath at `time` seconds: a smooth cosine, rest → full → rest every `Motion.breathPeriod`.
    /// Reduce Motion: no scaling, only a slower, softer change of light.
    public static func at(_ time: TimeInterval, reduceMotion: Bool = false) -> GlowBreath {
        let period = reduceMotion ? Motion.breathPeriod * 1.5 : Motion.breathPeriod
        let phase = time.truncatingRemainder(dividingBy: period) / period
        let wave = 0.5 - 0.5 * cos(2 * Double.pi * phase)
        let scale = reduceMotion ? 1 : lerp(Motion.breathScale, wave)
        let opacity = lerp(reduceMotion ? 0.75 ... 1.0 : Motion.breathOpacity, wave)
        return GlowBreath(scale: scale, opacity: opacity)
    }

    private static func lerp(_ range: ClosedRange<Double>, _ amount: Double) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * amount
    }
}

// MARK: - View helpers

extension View {
    /// Animates changes to `value` with a motion preset, or a crossfade under Reduce Motion.
    public func glowMotion(_ preset: Motion.Preset, value: some Equatable) -> some View {
        modifier(GlowMotionModifier(preset: preset, value: value))
    }

    /// Rises into place when `isVisible` turns true: the `index`th item 40 ms after the one before,
    /// on the smooth spring. Fades only under Reduce Motion.
    public func glowRise(index: Int = 0, isVisible: Bool) -> some View {
        modifier(GlowRiseModifier(index: index, isVisible: isVisible))
    }

    /// Breathes at a resting heart rate (a 4 s cycle, scale 1.0 to 1.03, opacity 0.6 to 1.0), for
    /// waiting states. `isActive: false` holds it still at rest. Draws nothing extra when still.
    public func glowBreathing(isActive: Bool = true) -> some View {
        modifier(GlowBreathingModifier(isActive: isActive))
    }
}

private struct GlowMotionModifier<Value: Equatable>: ViewModifier {
    let preset: Motion.Preset
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(preset.animation(reduceMotion: reduceMotion), value: value)
    }
}

private struct GlowRiseModifier: ViewModifier {
    let index: Int
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        // Under tests everything is already in place, so snapshots never catch a rise midway.
        let isVisible = isVisible || GlowMotionClock.isFrozen
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : Motion.riseDistance)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.98)
            .animation(Motion.staggered(.smooth, index: index, reduceMotion: reduceMotion), value: isVisible)
    }
}

private struct GlowBreathingModifier: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let isActive = isActive && !GlowMotionClock.isFrozen
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive)) { timeline in
            let breath = isActive ? GlowBreath.at(timeline.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion) : .rest
            content
                .scaleEffect(breath.scale)
                .opacity(breath.opacity)
        }
    }
}
