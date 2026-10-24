import SwiftUI

// Owner: B6. Motion from docs/SPEC.md: 0.2 s ease-out for UI, a spring for the reveal, a 1.25 s
// loop for the glow. Reduce Motion turns movement into fades.

/// Animations. Prefer `glowAnimation(_:value:)`, which follows Reduce Motion by itself.
public enum GlowMotion {
    public enum Kind: Sendable {
        /// Most UI changes: 0.2 s ease-out.
        case ui
        /// The mutual moment and other reveals: a spring. A plain ease under Reduce Motion.
        case reveal
    }

    /// Duration of a UI change.
    public static let uiDuration: Double = 0.2

    /// 0.2 s ease-out.
    public static var ui: Animation {
        .easeOut(duration: uiDuration)
    }

    /// The reveal spring: settles in about half a second with a small, warm overshoot.
    public static var reveal: Animation {
        .spring(response: 0.55, dampingFraction: 0.72)
    }

    /// The animation for `kind`, honoring Reduce Motion: no springs or overshoot, just an ease.
    public static func animation(_ kind: Kind, reduceMotion: Bool) -> Animation {
        switch (kind, reduceMotion) {
        case (.ui, _): ui
        case (.reveal, false): reveal
        case (.reveal, true): .easeInOut(duration: 0.35)
        }
    }

    /// How a toast, banner or overlay enters from `edge`: sliding in, or only fading under Reduce
    /// Motion.
    public static func transition(from edge: Edge, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}

/// The glow's pulse. Flash safety from docs/SPEC.md: slower than once per second, and the dimmest
/// moment is never under 70% of the brightest (seizures are triggered from about 3 flashes a second).
///
/// The pulse never darkens the glow color: a soft white bloom fades in and out on top of it, so the
/// code word's contrast only ever goes up during a pulse.
public enum GlowPulse {
    /// One full in-and-out cycle, in seconds. 0.8 times a second.
    public static let period: Double = 1.25
    /// The cycle under Reduce Motion: a slow fade, with no scaling.
    public static let reducedPeriod: Double = 4
    /// How much white the bloom mixes into the glow color at its brightest point.
    public static let bloomStrength = 0.15
    /// The dimmest moment as a share of the brightest, in luminance. Never lower (spec).
    public static let minimumLuminanceRatio = 0.7

    /// Pulses per second.
    public static func frequency(reduceMotion: Bool) -> Double {
        1 / (reduceMotion ? reducedPeriod : period)
    }
}

// MARK: - View helpers

extension View {
    /// Animates changes to `value` with a Glow animation, following Reduce Motion.
    public func glowAnimation(_ kind: GlowMotion.Kind = .ui, value: some Equatable) -> some View {
        modifier(GlowAnimationModifier(kind: kind, value: value))
    }
}

private struct GlowAnimationModifier<Value: Equatable>: ViewModifier {
    let kind: GlowMotion.Kind
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(GlowMotion.animation(kind, reduceMotion: reduceMotion), value: value)
    }
}
