import SwiftUI

// Owner: U1 (design wave). The three ways light moves in Glow (docs/design/DIRECTION.md):
//
//     GlowBreathingLight()                                   // waiting: a soft light that breathes
//     content.glowBloom(trigger: tapCount, at: .center)      // arriving: light blooms from a point
//     photo.glowVeil(isLifted: revealed)                     // Blind: the veil lifts from the center
//
// Each one has a calm Reduce Motion alternative, and holds still under tests so snapshots are
// stable.

/// Whether time-driven light (breathing, blooms) holds still: under unit and snapshot tests.
enum GlowMotionClock {
    static let isFrozen: Bool = NSClassFromString("XCTestCase") != nil
}

// MARK: - Breathing light

/// A soft orb of light that breathes at a resting heart rate. For waiting and empty states, in
/// place of a spinner: "never a spinner where a breath will do".
public struct GlowBreathingLight: View {
    private let rgb: GlowRGB
    private let isActive: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 132

    /// - Parameters:
    ///   - hue: the light's color; the accent when nil.
    ///   - isActive: false holds it still, at rest.
    public init(hue: GlowHue? = nil, isActive: Bool = true) {
        rgb = hue?.rgb ?? GlowPalette.accent
        self.isActive = isActive
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [rgb.color.opacity(0.42), rgb.color.opacity(0.12), rgb.color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2,
                ))
            Circle()
                .fill(RadialGradient(
                    colors: [Color.white.opacity(0.5), rgb.color.opacity(0.55), rgb.color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.16,
                ))
                .frame(width: size * 0.32, height: size * 0.32)
                .blur(radius: 2)
        }
        .frame(width: size, height: size)
        .glowBreathing(isActive: isActive && !GlowMotionClock.isFrozen)
        .accessibilityHidden(true)
    }
}

// MARK: - Wordmark

/// "Glow", set large in New York with a soft light behind it. For the welcome screen and the
/// launch moment.
public struct GlowWordmark: View {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 68

    public init() {}

    public var body: some View {
        Text(verbatim: "Glow")
            .font(.system(size: size, weight: .regular, design: .serif))
            .tracking(-size * 0.025)
            .foregroundStyle(.glowTextPrimary)
            .shadow(color: .glowAccent.opacity(0.35), radius: 24)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Bloom

extension View {
    /// Blooms light from `origin` each time `trigger` changes: a radial light that swells out over
    /// 600 ms and settles. Under Reduce Motion, a brief soft brightening instead.
    public func glowBloom(trigger: some Equatable, at origin: UnitPoint = .center, hue: GlowHue? = nil) -> some View {
        modifier(GlowBloomModifier(trigger: trigger, origin: origin, rgb: hue?.rgb ?? GlowPalette.accent))
    }
}

private struct GlowBloomModifier<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    let origin: UnitPoint
    let rgb: GlowRGB

    @State private var progress: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    let reach = max(proxy.size.width, proxy.size.height) * 1.2
                    RadialGradient(
                        colors: [rgb.color.opacity(0.55), rgb.color.opacity(0.18), rgb.color.opacity(0)],
                        center: origin,
                        startRadius: 0,
                        endRadius: reduceMotion ? reach : max(reach * progress, 1),
                    )
                    .opacity(progress >= 1 ? 0 : (reduceMotion ? 0.5 : 1 - progress * progress))
                    .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onChange(of: trigger) {
                progress = 0
                withAnimation(reduceMotion ? Motion.fade : .easeOut(duration: Motion.bloomDuration)) {
                    progress = 1
                }
            }
    }
}

// MARK: - Veil

extension View {
    /// Blind mode's veil: frosted, soft, out-of-focus light. When `isLifted` turns true the blur
    /// and frost dissolve from the center outward over `Motion.veilLiftDuration` (1.2 s). Under
    /// Reduce Motion, a calm crossfade.
    public func glowVeil(isLifted: Bool) -> some View {
        modifier(GlowVeilModifier(isLifted: isLifted))
    }
}

private struct GlowVeilModifier: ViewModifier {
    let isLifted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .modifier(GlowVeilEffect(progress: isLifted ? 1 : 0, reduceMotion: reduceMotion))
            .animation(
                reduceMotion ? .easeOut(duration: 0.6) : .easeInOut(duration: Motion.veilLiftDuration),
                value: isLifted,
            )
    }
}

/// The veil at `progress` (0 veiled, 1 lifted). Every part (the blur, the growing clear center,
/// the frost's opacity) animates natively, so one animation on `progress` lifts it smoothly.
struct GlowVeilEffect: ViewModifier {
    let progress: Double
    let reduceMotion: Bool

    /// The blur at full veil, in points.
    static let blur: CGFloat = 26

    func body(content: Content) -> some View {
        content
            .blur(radius: Self.blur * (1 - progress), opaque: true)
            .overlay {
                GeometryReader { proxy in
                    let diameter = hypot(proxy.size.width, proxy.size.height) * 1.3
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Color.white.opacity(0.06))
                        .mask {
                            // A clear center that grows outward, with a soft edge.
                            Rectangle()
                                .overlay {
                                    Circle()
                                        .frame(width: diameter, height: diameter)
                                        .scaleEffect(reduceMotion ? 1 : max(progress, 0.001))
                                        .blur(radius: 40)
                                        .opacity(reduceMotion ? 0 : 1)
                                        .blendMode(.destinationOut)
                                }
                                .compositingGroup()
                        }
                        .opacity(1 - progress)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}
