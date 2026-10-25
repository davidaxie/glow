import DesignSystem
import SwiftUI

// Owner: U2 (design wave). The deck's half of docs/design/DIRECTION.md, "light as the language":
// the warm dark room, a breathing light for waiting, a staggered rise, and the soft ripple of a
// one-sided tap. Module-local until U1's `Motion` presets and serif type land in DesignSystem
// (design/u1-foundation); the numbers are DIRECTION.md's, so swapping is a rename.

enum DeckLight {
    // MARK: Motion (DIRECTION.md "Motion system")

    /// Selections and small answers to a touch.
    static let snappy = Animation.spring(response: 0.35, dampingFraction: 0.86)
    /// Most UI movement: cards, panels, screens settling.
    static let smooth = Animation.spring(response: 0.5, dampingFraction: 0.9)
    /// Big, slow arrivals.
    static let gentle = Animation.spring(response: 0.8, dampingFraction: 0.95)
    /// Opacity-only changes, and every movement under Reduce Motion.
    static let fade = Animation.easeOut(duration: 0.25)
    /// Seconds between cards appearing.
    static let stagger = 0.04
    /// The furthest card in a stagger: later ones arrive with it, so a long deck never waits.
    static let staggerCap = 8
    /// One breath, in seconds.
    static let breathPeriod = 4.0
    /// A bloom: light from the point of interaction, then it settles.
    static let bloomDuration = 0.6

    static func motion(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }

    // MARK: Shape

    /// Cards: a large continuous corner (DIRECTION.md "Surfaces": 24 to 32).
    static let cardRadius: CGFloat = 26
    /// Sheets' top corners.
    static let sheetRadius: CGFloat = 20

    // MARK: Type

    // New York for display moments (DIRECTION.md "Type"). A bridge until U1 adds the serif text
    // styles to DesignSystem; each one scales with Dynamic Type like every Glow style.
    // swiftlint:disable:next glow_feature_fonts
    static let displaySerif = Font.system(.largeTitle, design: .serif, weight: .regular)
    // swiftlint:disable:next glow_feature_fonts
    static let titleSerif = Font.system(.title2, design: .serif, weight: .regular)
}

extension EnvironmentValues {
    /// Breathing lights move. Snapshot tests turn it off so every render is the same frame.
    @Entry var deckLightBreathes = true
}

// MARK: - The room

/// The warm, dark room every deck screen sits in: a near-black canvas, a whisper of warmth from
/// the top, and a light whose strength is `warmth` (0 to 1).
struct DeckCanvas: View {
    var warmth: Double = 0.4

    var body: some View {
        ZStack {
            Color.glowBackground
            LinearGradient(
                colors: [GlowHue.ember.color.opacity(0.06), .glowClear],
                startPoint: .top,
                endPoint: .center,
            )
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

// MARK: - Breathing

/// A soft light that breathes at a resting heart rate: a 4 s cycle, scale 1.0 to 1.03, light 0.6
/// to 1.0. Under Reduce Motion it only brightens and dims, slower. Decorative.
struct DeckBreathingLight: View {
    var size: CGFloat = 200
    var intensity: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.deckLightBreathes) private var breathes

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !breathes)) { timeline in
            let wave = breathes ? Self.wave(at: timeline.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion) : 1
            orb
                .scaleEffect(reduceMotion ? 1 : 1 + 0.03 * wave)
                .opacity(reduceMotion ? 0.75 + 0.25 * wave : 0.6 + 0.4 * wave)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var orb: some View {
        ZStack {
            Circle().fill(RadialGradient(
                colors: [
                    Color.glowAccent.opacity(0.42 * intensity),
                    Color.glowAccent.opacity(0.12 * intensity),
                    Color.glowAccent.opacity(0),
                ],
                center: .center,
                startRadius: 0,
                endRadius: size / 2,
            ))
            Circle().fill(RadialGradient(
                colors: [GlowHue.pearl.color.opacity(0.55 * intensity), GlowHue.pearl.color.opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: size * 0.11,
            ))
        }
    }

    /// 0 at rest, 1 at the top of a breath: a smooth cosine.
    static func wave(at time: TimeInterval, reduceMotion: Bool) -> Double {
        let period = reduceMotion ? DeckLight.breathPeriod * 1.5 : DeckLight.breathPeriod
        let phase = time.truncatingRemainder(dividingBy: period) / period
        return 0.5 - 0.5 * cos(2 * .pi * phase)
    }
}

// MARK: - Rise

extension View {
    /// Rises into place when `isVisible` turns true, the `index`th item 40 ms after the one before,
    /// on the smooth spring. Fades only under Reduce Motion.
    func deckRise(index: Int, isVisible: Bool) -> some View {
        modifier(DeckRise(index: index, isVisible: isVisible))
    }
}

private struct DeckRise: ViewModifier {
    let index: Int
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 18)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.97, anchor: .bottom)
            .animation(
                DeckLight.motion(DeckLight.smooth, reduceMotion: reduceMotion)
                    .delay(Double(min(max(index, 0), DeckLight.staggerCap)) * DeckLight.stagger),
                value: isVisible,
            )
    }
}

// MARK: - Ripple

/// The one-sided tap's quiet acknowledgement: a soft ring of light that ripples out from the
/// middle of the card once per `trigger`, then settles (600 ms). Under Reduce Motion, a glow that
/// fades in and out in place. Decorative, and only ever on the tapper's own screen.
struct DeckRipple: View {
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let reach = max(proxy.size.width, proxy.size.height) * 1.25
            Circle()
                .strokeBorder(Color.glowTextPrimary.opacity(0.7), lineWidth: 1.5)
                .background(Circle().fill(RadialGradient(
                    colors: [Color.glowAccent.opacity(0.0), Color.glowAccent.opacity(0.35)],
                    center: .center,
                    startRadius: 0,
                    endRadius: reach / 2,
                )))
                .frame(width: reach, height: reach)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .keyframeAnimator(initialValue: RippleFrame(), trigger: trigger) { ring, frame in
                    ring
                        .scaleEffect(reduceMotion ? 1 : frame.scale)
                        .opacity(frame.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        LinearKeyframe(0.08, duration: 0.001)
                        CubicKeyframe(1, duration: DeckLight.bloomDuration)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(0.95, duration: 0.001)
                        CubicKeyframe(0.6, duration: DeckLight.bloomDuration * 0.5)
                        CubicKeyframe(0, duration: DeckLight.bloomDuration * 0.5)
                    }
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct RippleFrame {
    var scale: CGFloat = 1
    var opacity: Double = 0
}

// MARK: - Glass

extension View {
    /// A lifted glass surface: material over the room, a 1 pt highlight on the top edge, a soft
    /// shadow below (DIRECTION.md "Surfaces").
    func deckGlass(cornerRadius: CGFloat = DeckLight.cardRadius) -> some View {
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
}

/// A quiet, centered state in the room: a breathing light, one honest line in New York, a softer
/// line under it, and the one thing to do (DIRECTION.md "Empty and waiting states").
struct DeckQuietState<Actions: View>: View {
    let title: String
    var message: String?
    var intensity: Double = 1
    @ViewBuilder var actions: Actions

    @ScaledMetric(relativeTo: .largeTitle) private var lightSize: CGFloat = 180

    var body: some View {
        VStack(spacing: GlowSpacing.lg) {
            DeckBreathingLight(size: lightSize, intensity: intensity)
                .padding(.bottom, -GlowSpacing.lg)
            VStack(spacing: GlowSpacing.xs) {
                Text(title)
                    .font(DeckLight.titleSerif)
                    .tracking(-0.3)
                    .foregroundStyle(.glowTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message)
                        .glowFont(.body)
                        .foregroundStyle(.glowTextSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: GlowSpacing.xs) {
                actions
            }
        }
        .padding(.horizontal, GlowSpacing.lg)
        .frame(maxWidth: .infinity)
    }
}

extension DeckQuietState where Actions == EmptyView {
    init(title: String, message: String? = nil, intensity: Double = 1) {
        self.init(title: title, message: message, intensity: intensity) { EmptyView() }
    }
}
