import DesignSystem
import SwiftUI

// Owner: U2 (design wave). Rooms' half of docs/design/DIRECTION.md, "light as the language": the
// warm dark room, and a light that gathers as you join ("the room warms up"). Module-local until
// U1's `Motion` presets and serif type land in DesignSystem (design/u1-foundation); the numbers
// are DIRECTION.md's, so swapping is a rename.

enum RoomsLight {
    /// Most UI movement.
    static var smooth: Animation {
        Motion.smooth
    }

    /// Big, slow arrivals: the light gathering.
    static var gentle: Animation {
        Motion.gentle
    }

    /// Opacity-only changes, and every movement under Reduce Motion.
    static var fade: Animation {
        Motion.fade
    }

    /// Seconds between items appearing.
    static let stagger = Motion.stagger
    /// One breath, in seconds.
    static let breathPeriod = Motion.breathPeriod

    static func motion(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }
}

/// The warm dark room: a near-black canvas, a whisper of warmth from the top, and a light from
/// above whose strength is `warmth` (0 to 1).
struct RoomsCanvas: View {
    var warmth: Double = 0.35

    var body: some View {
        ZStack {
            Color.glowBackground
            LinearGradient(colors: [GlowHue.ember.color.opacity(0.06), .glowClear], startPoint: .top, endPoint: .center)
            RadialGradient(
                colors: [Color.glowAccent.opacity(0.16 * warmth), Color.glowAccent.opacity(0)],
                center: UnitPoint(x: 0.5, y: -0.05),
                startRadius: 0,
                endRadius: 460,
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The room's light: a soft orb that breathes at a resting heart rate (a 4 s cycle, scale 1.0 to
/// 1.03, light 0.6 to 1.0) and grows warmer and wider with `warmth`, 0 (cold, a failed join) to 1
/// (you're in). Changes of warmth gather on the gentle spring. Decorative.
struct RoomWarmth: View {
    var warmth: Double
    var size: CGFloat = 260
    /// A cold room is grey light, not pink: something to fix, never alarming.
    var isCold = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let wave = Self.wave(at: timeline.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion)
            RoomOrb(warmth: warmth, isCold: isCold)
                .scaleEffect(reduceMotion ? 1 : 1 + 0.03 * wave)
                .opacity(reduceMotion ? 0.75 + 0.25 * wave : 0.6 + 0.4 * wave)
        }
        .frame(width: size, height: size)
        .animation(RoomsLight.motion(RoomsLight.gentle, reduceMotion: reduceMotion), value: warmth)
        .animation(RoomsLight.motion(RoomsLight.gentle, reduceMotion: reduceMotion), value: isCold)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    static func wave(at time: TimeInterval, reduceMotion: Bool) -> Double {
        let period = reduceMotion ? RoomsLight.breathPeriod * 1.5 : RoomsLight.breathPeriod
        let phase = time.truncatingRemainder(dividingBy: period) / period
        return 0.5 - 0.5 * cos(2 * .pi * phase)
    }
}

/// The orb itself. Animatable, so warmth gathers smoothly instead of jumping.
private struct RoomOrb: View {
    var warmth: Double
    var isCold: Bool

    var body: some View {
        let light = isCold ? Color.glowTextSecondary : Color.glowAccent
        let reach = 0.55 + 0.45 * warmth
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2
            ZStack {
                Circle().fill(RadialGradient(
                    colors: [light.opacity(0.18 + 0.32 * warmth), light.opacity(0.06 + 0.1 * warmth), light.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: radius * reach,
                ))
                Circle().fill(RadialGradient(
                    colors: [GlowHue.pearl.color.opacity(0.15 + 0.5 * warmth), GlowHue.pearl.color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: radius * (0.06 + 0.1 * warmth),
                ))
            }
        }
    }
}

extension View {
    /// A lifted glass surface: material over the room, a 1 pt highlight on the top edge, a soft
    /// shadow below (DIRECTION.md "Surfaces").
    func roomsGlass(cornerRadius: CGFloat = 24) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(.ultraThinMaterial, in: shape)
            .background(Color.glowSurface.opacity(0.55), in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.glowTextPrimary.opacity(0.16), Color.glowTextPrimary.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                    lineWidth: 1,
                )
            }
            .shadow(color: Color.glowBackground.opacity(0.6), radius: 18, y: 10)
    }

    /// Rises into place on appear, the `index`th item 40 ms after the one before. Fades only under
    /// Reduce Motion.
    func roomsRise(index: Int, isVisible: Bool) -> some View {
        modifier(RoomsRise(index: index, isVisible: isVisible))
    }
}

private struct RoomsRise: ViewModifier {
    let index: Int
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 14)
            .animation(
                RoomsLight.motion(RoomsLight.smooth, reduceMotion: reduceMotion).delay(Double(index) * RoomsLight.stagger),
                value: isVisible,
            )
    }
}
