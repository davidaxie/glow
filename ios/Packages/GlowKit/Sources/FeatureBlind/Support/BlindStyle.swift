import DesignSystem
import SwiftUI

// Owner: X2. Module-local stand-ins for the design direction (docs/design/DIRECTION.md) until U1's
// Motion presets and display type land in DesignSystem. Same names, same values: swap these for
// the DesignSystem ones when they arrive, and delete this file's copies.

/// The motion contract from DIRECTION.md. Springs only for movement; opacity-only fades may ease out.
enum BlindMotion {
    static let snappy = Animation.spring(response: 0.35, dampingFraction: 0.86)
    static let smooth = Animation.spring(response: 0.5, dampingFraction: 0.9)
    static let gentle = Animation.spring(response: 0.8, dampingFraction: 0.95)
    /// Opacity only.
    static let fade = Animation.easeOut(duration: 0.25)
    /// Between items appearing in a list or a set of cards.
    static let stagger: Duration = .milliseconds(40)
    static let staggerSeconds = 0.04
    /// Waiting states breathe at a resting heart rate.
    static let breathPeriod = 4.0
    /// The veil lifting at reveal.
    static let veilLift = 1.2

    /// The spring, or the calm crossfade under Reduce Motion.
    static func motion(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }
}

/// Display type: New York (the system serif) for codenames, names at reveal and big statements.
/// Everything else uses DesignSystem's `glowFont`. Each one scales with Dynamic Type.
enum BlindType {
    // swiftlint:disable glow_feature_fonts
    // DIRECTION.md asks for New York on display moments, and DesignSystem has no serif style yet
    // (U1 is adding it on design/u1-foundation). Replace these with U1's tokens when they land.
    static let codenameHero = Font.system(.largeTitle, design: .serif, weight: .semibold)
    static let codename = Font.system(.title3, design: .serif, weight: .semibold)
    static let codenameItalic = Font.system(.title, design: .serif, weight: .regular).italic()
    static let revealName = Font.system(.largeTitle, design: .serif, weight: .regular)
    static let statement = Font.system(.title2, design: .serif, weight: .regular)
    static let counter = Font.system(.largeTitle, design: .rounded, weight: .semibold).monospacedDigit()
    // swiftlint:enable glow_feature_fonts
}

/// The two-beat heartbeat (two soft impacts 120 ms apart) for the mutual reveal.
enum BlindHaptics {
    static let heartbeat = GlowHapticPattern(events: [
        GlowHapticPattern.Event(time: 0, intensity: 0.55, sharpness: 0.12),
        GlowHapticPattern.Event(time: 0.12, intensity: 0.35, sharpness: 0.1),
    ])

    @MainActor
    static func playHeartbeat() {
        GlowHaptics.shared.play(pattern: heartbeat)
    }
}

// MARK: - The canvas

/// The warm near-black room: the background, a very subtle vertical light and a faint grain.
struct BlindCanvas: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.glowBackground)
            LinearGradient(
                colors: [.glowSurfaceRaised.opacity(0.55), .glowBackground.opacity(0)],
                startPoint: .top,
                endPoint: .center,
            )
            BlindGrain()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A faint film grain, drawn once per size, 2 to 3 percent strong.
struct BlindGrain: View {
    var body: some View {
        Canvas { context, size in
            var generator = SeededGenerator(seed: 7)
            let count = Int(size.width * size.height / 90)
            for _ in 0 ..< count {
                let x = CGFloat.random(in: 0 ..< size.width, using: &generator)
                let y = CGFloat.random(in: 0 ..< size.height, using: &generator)
                let light = Bool.random(using: &generator)
                context.fill(
                    Path(CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(light ? .glowTextPrimary.opacity(0.03) : .glowBackground.opacity(0.5)),
                )
            }
        }
        .allowsHitTesting(false)
    }
}

/// A tiny deterministic generator, so the grain and the veil look the same on every launch.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

// MARK: - Glass

extension View {
    /// A lifted glass surface: the surface color, a 1 px highlight on the top edge and a soft shadow.
    func blindGlass(cornerRadius: CGFloat = 24, highlighted: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(.glowSurface.opacity(0.92), in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.glowTextPrimary.opacity(highlighted ? 0.28 : 0.12), .glowTextPrimary.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                    lineWidth: 1,
                )
            }
            .overlay {
                if highlighted {
                    shape.strokeBorder(.glowAccent.opacity(0.45), lineWidth: 1)
                }
            }
            .shadow(color: .glowBackground.opacity(0.7), radius: 18, y: 10)
    }
}

// MARK: - Breathing

/// Waiting states breathe: a 4 s cycle, scale 1.0 to 1.03 and opacity 0.6 to 1.0. Under Reduce
/// Motion only the opacity moves, slowly.
struct BlindBreathing: ViewModifier {
    var isActive = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if isActive {
            TimelineView(.animation) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: BlindMotion.breathPeriod)
                let wave = (1 - cos(phase / BlindMotion.breathPeriod * 2 * .pi)) / 2
                content
                    .scaleEffect(reduceMotion ? 1 : 1 + 0.03 * wave)
                    .opacity(0.6 + 0.4 * wave)
            }
        } else {
            content
        }
    }
}

extension View {
    func blindBreathing(_ isActive: Bool = true) -> some View {
        modifier(BlindBreathing(isActive: isActive))
    }
}

// MARK: - The veil

/// Before reveal, a person is frosted, out-of-focus light: soft colored blobs behind frost, drifting
/// very slowly. The colors come from the codename, so the same chat always has the same light.
struct BlindVeilOrb: View {
    let seed: String
    var size: CGFloat = 48
    var drifts = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let hues = BlindVeilOrb.hues(for: seed)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !drifts || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().fill(.glowSurfaceRaised)
                ForEach(0 ..< 3, id: \.self) { index in
                    let angle = time / (9 + Double(index) * 3) + Double(index) * 2.1
                    Circle()
                        .fill(hues[index].color.opacity(0.85))
                        .frame(width: size * 0.62, height: size * 0.62)
                        .offset(x: cos(angle) * size * 0.2, y: sin(angle) * size * 0.2)
                }
            }
            .blur(radius: size * 0.16)
            .overlay {
                Circle().fill(.ultraThinMaterial).opacity(0.35)
            }
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(
                    LinearGradient(
                        colors: [.glowTextPrimary.opacity(0.3), .glowTextPrimary.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                    lineWidth: 1,
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Three glow hues picked from the codename.
    static func hues(for seed: String) -> [GlowHue] {
        let all = GlowHue.allCases.filter { $0 != .pearl && $0 != .lime }
        var generator = SeededGenerator(seed: UInt64(seed.unicodeScalars.reduce(5381) { ($0 &* 33) &+ UInt64($1.value) }))
        return (0 ..< 3).map { _ in all[Int(generator.next() % UInt64(all.count))] }
    }
}

/// A bloom: radial light that grows from a point and settles, 600 ms.
struct BlindBloom: View {
    var hue: Color = .glowAccent
    @State private var bloomed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let radius = max(proxy.size.width, proxy.size.height)
            RadialGradient(colors: [hue.opacity(0.35), hue.opacity(0)], center: .center, startRadius: 0, endRadius: radius * 0.7)
                .scaleEffect(bloomed || reduceMotion ? 1 : 0.2)
                .opacity(bloomed ? 0.8 : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(BlindMotion.motion(.spring(response: 0.6, dampingFraction: 0.9), reduceMotion: reduceMotion)) {
                bloomed = true
            }
        }
    }
}
