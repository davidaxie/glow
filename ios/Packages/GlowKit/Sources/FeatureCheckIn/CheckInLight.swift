import DesignSystem
import SwiftUI

// Owner: U2 (design wave). Check-in's half of docs/design/DIRECTION.md, "Joining a room": the room
// warms up as you check in. Each step lets a little more light into the room, and the waits
// breathe instead of spinning. Module-local until U1's `Motion` presets land in DesignSystem
// (design/u1-foundation); the numbers are DIRECTION.md's.

enum CheckInLight {
    /// Big, slow arrivals: the light gathering.
    static var gentle: Animation {
        Motion.gentle
    }

    /// Most UI movement.
    static var smooth: Animation {
        Motion.smooth
    }

    /// Opacity-only changes, and every movement under Reduce Motion.
    static var fade: Animation {
        Motion.fade
    }

    /// One breath, in seconds.
    static let breathPeriod = Motion.breathPeriod

    static func motion(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }

    /// How warm the room is at each step, 0 to 1.
    static func warmth(_ step: CheckInModel.Step) -> Double {
        switch step {
        case .capture: 0.3
        case .processing: 0.45
        case .preview: 0.55
        case .tags: 0.65
        case .uploading: 0.85
        case .done: 1
        }
    }
}

/// The warm dark room, lit from above by `warmth` (0 to 1). Warmth gathers on the gentle spring.
struct CheckInCanvas: View {
    var warmth: Double

    var body: some View {
        ZStack {
            Color.glowBackground
            LinearGradient(colors: [GlowHue.ember.color.opacity(0.06), .glowClear], startPoint: .top, endPoint: .center)
            RadialGradient(
                colors: [Color.glowAccent.opacity(0.2 * warmth), Color.glowAccent.opacity(0)],
                center: UnitPoint(x: 0.5, y: -0.05),
                startRadius: 0,
                endRadius: 380 + 160 * warmth,
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A soft light breathing at a resting heart rate (4 s, scale 1.0 to 1.03, light 0.6 to 1.0), for
/// the waits. Under Reduce Motion it only brightens and dims, slower. Decorative.
struct CheckInBreath: View {
    var size: CGFloat = 160
    var intensity: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let period = reduceMotion ? CheckInLight.breathPeriod * 1.5 : CheckInLight.breathPeriod
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            let wave = 0.5 - 0.5 * cos(2 * .pi * phase)
            ZStack {
                Circle().fill(RadialGradient(
                    colors: [
                        Color.glowAccent.opacity(0.45 * intensity),
                        Color.glowAccent.opacity(0.12 * intensity),
                        Color.glowAccent.opacity(0),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2,
                ))
                Circle().fill(RadialGradient(
                    colors: [GlowHue.pearl.color.opacity(0.6 * intensity), GlowHue.pearl.color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.12,
                ))
            }
            .scaleEffect(reduceMotion ? 1 : 1 + 0.03 * wave)
            .opacity(reduceMotion ? 0.75 + 0.25 * wave : 0.6 + 0.4 * wave)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
