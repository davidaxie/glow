import CoreHaptics
import DesignSystem
import SwiftUI
import UIKit

// Owner: C3. STAND-INS for B6's glow surface, brightness, keep-awake and haptics from draft PR #24
// (`DesignSystem/Glow/` and `DesignSystem/Haptics/`), until it merges (AGENTS.md, "Mocks").
//
// Same names and signatures as #24's DesignSystem README, but internal to FeatureGlow, so the glow
// screen's code is already written against B6's API. WHEN #24 MERGES, DELETE THIS FILE: everything
// then resolves to DesignSystem's real components, with no other change.
//
// Kept as close to B6's code as the "no colors or fonts in feature modules" rule allows: white comes
// from `GlowRGB.white`, and the code word's size goes through the one rule exception below.

// MARK: - The surface

/// B6's `GlowSurface`: the glow color with a soft, flash-safe bloom (GlowPulse: 1.25 s, never
/// darker than 70%; a 4 s fade with no scaling under Reduce Motion), full brightness and keep-awake.
struct GlowSurface<Content: View>: View {
    private let hue: GlowHue
    private let isPulsing: Bool
    private let controlsScreen: Bool
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ hue: GlowHue, isPulsing: Bool = true, controlsScreen: Bool = true, @ViewBuilder content: () -> Content) {
        self.hue = hue
        self.isPulsing = isPulsing
        self.controlsScreen = controlsScreen
        self.content = content()
    }

    var body: some View {
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
                        colors: [
                            GlowRGB.white.color.opacity(GlowPulse.bloomStrength * frame.opacity),
                            GlowRGB.white.color.opacity(0),
                        ],
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
    /// B6's `GlowPulse.Frame`: one moment of the pulse.
    struct Frame: Equatable {
        let opacity: Double
        let scale: Double

        static let resting = Frame(opacity: 0.6, scale: 1)
    }

    /// B6's `GlowPulse.frame(at:reduceMotion:)`: a smooth cosine wave. Reduce Motion only fades,
    /// more slowly, and never changes size.
    static func frame(at time: TimeInterval, reduceMotion: Bool) -> Frame {
        let length = reduceMotion ? reducedPeriod : period
        let phase = time.truncatingRemainder(dividingBy: length) / length
        let wave = 0.5 - 0.5 * cos(2 * Double.pi * phase)
        return Frame(opacity: 0.2 + 0.8 * wave, scale: reduceMotion ? 1 : 0.85 + 0.15 * wave)
    }
}

extension EnvironmentValues {
    @Entry var glowHue: GlowHue?
}

/// B6's `GlowCodeWord`: as big as it fits, SF Pro Rounded heavy, scaling with Dynamic Type.
struct GlowCodeWord: View {
    private let word: String
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 76

    init(_ word: String) {
        self.word = word
    }

    var body: some View {
        Text(verbatim: word)
            // The one exception to B6's font rule, for this stand-in only: #24's GlowCodeWord sets
            // this exact font inside DesignSystem.
            // swiftlint:disable:next glow_feature_fonts
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .accessibilityLabel(Text("Code word: \(word)"))
            .accessibilityAddTraits(.isHeader)
    }
}

/// B6's `.glowOnSurface`: filled with the color's ink, labelled in the color.
struct GlowOnSurfaceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlowOnSurfaceButtonBody(label: configuration.label, isPressed: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlowOnSurfaceButtonStyle {
    static var glowOnSurface: GlowOnSurfaceButtonStyle {
        GlowOnSurfaceButtonStyle()
    }
}

struct GlowOnSurfaceButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool

    @Environment(\.glowHue) private var hue
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var height = GlowSize.buttonHeight

    var body: some View {
        let hue = hue ?? .pearl
        let shape = RoundedRectangle(cornerRadius: GlowRadius.control, style: .continuous)
        label
            .font(.glow(.button))
            .foregroundStyle(hue.color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, GlowSpacing.lg)
            .padding(.vertical, GlowSpacing.xs)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(hue.ink.color.opacity(isPressed ? 0.85 : 1), in: shape)
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(GlowMotion.ui, value: isPressed)
    }
}

// MARK: - Brightness

@MainActor
protocol GlowBrightnessAdjustable: AnyObject {
    var brightness: CGFloat { get set }
}

extension UIScreen: GlowBrightnessAdjustable {}

/// B6's `GlowBrightness`: raises brightness while anything holds it, and restores the person's own
/// level when the last holder lets go.
@MainActor
final class GlowBrightness {
    static let shared = GlowBrightness()

    let raisedLevel: CGFloat
    private var holders: Set<UUID> = []
    private var savedLevel: CGFloat?
    private var screen: (any GlowBrightnessAdjustable)?

    init(raisedLevel: CGFloat = 1) {
        self.raisedLevel = min(max(raisedLevel, 0), 1)
    }

    var isRaised: Bool {
        !holders.isEmpty
    }

    var levelToRestore: CGFloat? {
        savedLevel
    }

    func raise(for holder: UUID, on screen: any GlowBrightnessAdjustable) {
        if let current = self.screen, current !== screen {
            restore()
            holders.removeAll()
        }
        if holders.isEmpty {
            savedLevel = screen.brightness
            self.screen = screen
        }
        holders.insert(holder)
        screen.brightness = max(raisedLevel, savedLevel ?? 0)
    }

    func release(_ holder: UUID) {
        guard holders.remove(holder) != nil else { return }
        if holders.isEmpty {
            restore()
        }
    }

    private func restore() {
        if let screen, let savedLevel {
            screen.brightness = savedLevel
        }
        savedLevel = nil
        screen = nil
    }
}

extension View {
    func glowFullBrightness(_ isActive: Bool = true) -> some View {
        modifier(GlowFullBrightnessModifier(isActive: isActive, controller: .shared))
    }

    func glowKeepAwake(_ isActive: Bool = true) -> some View {
        modifier(GlowKeepAwakeModifier(isActive: isActive))
    }
}

struct GlowFullBrightnessModifier: ViewModifier {
    let isActive: Bool
    let controller: GlowBrightness

    @Environment(\.scenePhase) private var scenePhase
    @State private var holder = UUID()
    @State private var isVisible = false
    @State private var screen: UIScreen?

    func body(content: Content) -> some View {
        content
            .background(GlowWindowSceneReader { screen = $0?.screen })
            .onAppear {
                isVisible = true
                update()
            }
            .onDisappear {
                isVisible = false
                update()
            }
            .onChange(of: scenePhase) { update() }
            .onChange(of: isActive) { update() }
            .onChange(of: screen) { update() }
    }

    private func update() {
        if isActive, isVisible, scenePhase == .active, let screen {
            controller.raise(for: holder, on: screen)
        } else {
            controller.release(holder)
        }
    }
}

struct GlowWindowSceneReader: UIViewRepresentable {
    let onChange: @MainActor (UIWindowScene?) -> Void

    func makeUIView(context _: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: ReaderView, context _: Context) {
        view.onChange = onChange
    }

    final class ReaderView: UIView {
        var onChange: (@MainActor (UIWindowScene?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            let scene = window?.windowScene
            Task { @MainActor [onChange] in onChange?(scene) }
        }
    }
}

// MARK: - Keep awake

struct GlowKeepAwakeModifier: ViewModifier {
    let isActive: Bool

    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var savedValue: Bool?

    func body(content: Content) -> some View {
        content
            .onAppear {
                isVisible = true
                update()
            }
            .onDisappear {
                isVisible = false
                update()
            }
            .onChange(of: scenePhase) { update() }
            .onChange(of: isActive) { update() }
    }

    private func update() {
        let application = UIApplication.shared
        if isActive, isVisible, scenePhase == .active {
            if savedValue == nil {
                savedValue = application.isIdleTimerDisabled
            }
            application.isIdleTimerDisabled = true
        } else if let savedValue {
            application.isIdleTimerDisabled = savedValue
            self.savedValue = nil
        }
    }
}

// MARK: - Haptics

/// B6's `GlowHaptic`, only the moment the glow uses.
enum GlowHaptic {
    /// Three soft heartbeats in time with the glow's pulse.
    case glowPulse
}

/// B6's `GlowHaptics`: soft double beats, one per glow pulse. Nothing in the Simulator.
@MainActor
final class GlowHaptics {
    static let shared = GlowHaptics()
    private var engine: CHHapticEngine?

    func play(_: GlowHaptic) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try engine ?? CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true
            try engine.start()
            self.engine = engine
            let events = (0 ..< 3).flatMap { beat -> [CHHapticEvent] in
                let start = Double(beat) * GlowPulse.period
                return [
                    Self.tap(at: start, intensity: 0.5),
                    Self.tap(at: start + 0.16, intensity: 0.3),
                ]
            }
            try engine.makePlayer(with: CHHapticPattern(events: events, parameters: [])).start(atTime: CHHapticTimeImmediate)
        } catch {
            engine = nil
        }
    }

    private static func tap(at time: TimeInterval, intensity: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1),
            ],
            relativeTime: time,
        )
    }
}

extension View {
    /// B6's `glowHaptic(_:trigger:)`: plays the haptic each time `trigger` changes.
    func glowHaptic(_ haptic: GlowHaptic, trigger: some Equatable) -> some View {
        onChange(of: trigger) { GlowHaptics.shared.play(haptic) }
    }
}
