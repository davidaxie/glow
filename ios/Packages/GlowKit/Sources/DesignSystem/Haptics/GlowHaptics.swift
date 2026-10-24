import CoreHaptics
import SwiftUI

// Owner: B6. Haptics for the mutual moment, the glow pulse and light taps.
//
//     .glowHaptic(.lightTap, trigger: tapCount)          // a card tap
//     .glowHaptic(.mutual, trigger: match?.id)           // "Someone you noticed noticed you back."
//     GlowHaptics.shared.play(.glowPulse)                // a few soft beats when the glow starts
//
// The Simulator can't play haptics (spec), so these do nothing there. Check them on a device.

/// A haptic moment.
public enum GlowHaptic: String, CaseIterable, Sendable {
    /// A light tap: selecting a card, a chip, a step.
    case lightTap
    /// A selection changing, like moving between tags.
    case selection
    /// Something worked (sent, saved).
    case success
    /// Something needs attention (a failed room check).
    case warning
    /// The mutual moment: three rising taps that bloom into a soft swell.
    case mutual
    /// Three soft heartbeats in time with the glow's pulse.
    case glowPulse
}

/// A Core Haptics pattern as plain data, so its shape can be tested without hardware.
public struct GlowHapticPattern: Equatable, Sendable {
    public struct Event: Equatable, Sendable {
        /// Seconds from the start.
        public let time: TimeInterval
        /// 0 to 1.
        public let intensity: Float
        /// 0 (round) to 1 (crisp).
        public let sharpness: Float
        /// Seconds, for a continuous buzz. Nil for a single tap.
        public let duration: TimeInterval?

        public init(time: TimeInterval, intensity: Float, sharpness: Float, duration: TimeInterval? = nil) {
            self.time = time
            self.intensity = intensity
            self.sharpness = sharpness
            self.duration = duration
        }
    }

    public let events: [Event]

    public init(events: [Event]) {
        self.events = events
    }

    /// When the last event ends.
    public var duration: TimeInterval {
        events.map { $0.time + ($0.duration ?? 0) }.max() ?? 0
    }

    /// Three taps, each stronger than the last, then a soft swell. About 0.75 s.
    public static let mutual = GlowHapticPattern(events: [
        Event(time: 0, intensity: 0.45, sharpness: 0.5),
        Event(time: 0.12, intensity: 0.7, sharpness: 0.55),
        Event(time: 0.24, intensity: 1, sharpness: 0.6),
        Event(time: 0.36, intensity: 0.55, sharpness: 0.15, duration: 0.4),
    ])

    /// Soft double beats ("lub-dub"), one per glow pulse. Three by default: enough to feel the
    /// glow start, without buzzing for 15 minutes.
    public static func heartbeat(beats: Int = 3) -> GlowHapticPattern {
        let events = (0 ..< max(beats, 1)).flatMap { beat -> [Event] in
            let start = Double(beat) * GlowPulse.period
            return [
                Event(time: start, intensity: 0.5, sharpness: 0.1),
                Event(time: start + 0.16, intensity: 0.3, sharpness: 0.1),
            ]
        }
        return GlowHapticPattern(events: events)
    }

    public static let glowPulse = heartbeat()

    /// The Core Haptics pattern.
    public func makePattern() throws -> CHHapticPattern {
        let events = events.map { event in
            let parameters = [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: event.sharpness),
            ]
            if let duration = event.duration {
                return CHHapticEvent(eventType: .hapticContinuous, parameters: parameters, relativeTime: event.time, duration: duration)
            }
            return CHHapticEvent(eventType: .hapticTransient, parameters: parameters, relativeTime: event.time)
        }
        return try CHHapticPattern(events: events, parameters: [])
    }
}

/// Plays custom patterns with Core Haptics. Quietly does nothing on hardware without haptics
/// (the Simulator, iPads) or if the engine fails: haptics are never essential.
@MainActor
public final class GlowHaptics {
    public static let shared = GlowHaptics()

    private var engine: CHHapticEngine?

    public init() {}

    /// Whether this device can play haptics at all.
    public nonisolated static var isSupported: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// Plays one of the custom moments. The simple ones (taps, success) use SwiftUI's
    /// `sensoryFeedback` through `glowHaptic(_:trigger:)` instead.
    public func play(_ haptic: GlowHaptic) {
        switch haptic {
        case .mutual: play(pattern: .mutual)
        case .glowPulse: play(pattern: .glowPulse)
        case .lightTap, .selection, .success, .warning: break
        }
    }

    public func play(pattern: GlowHapticPattern) {
        guard Self.isSupported else { return }
        do {
            let engine = try runningEngine()
            let player = try engine.makePlayer(with: pattern.makePattern())
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // A haptic that doesn't play is not worth surfacing; start over next time.
            engine = nil
        }
    }

    private func runningEngine() throws -> CHHapticEngine {
        if let engine {
            return engine
        }
        let engine = try CHHapticEngine()
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = true
        try engine.start()
        self.engine = engine
        return engine
    }
}

extension View {
    /// Plays `haptic` each time `trigger` changes.
    public func glowHaptic(_ haptic: GlowHaptic, trigger: some Equatable) -> some View {
        modifier(GlowHapticModifier(haptic: haptic, trigger: trigger))
    }
}

private struct GlowHapticModifier<Trigger: Equatable>: ViewModifier {
    let haptic: GlowHaptic
    let trigger: Trigger

    func body(content: Content) -> some View {
        switch haptic {
        case .lightTap:
            content.sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: trigger)
        case .selection:
            content.sensoryFeedback(.selection, trigger: trigger)
        case .success:
            content.sensoryFeedback(.success, trigger: trigger)
        case .warning:
            content.sensoryFeedback(.warning, trigger: trigger)
        case .mutual, .glowPulse:
            content.onChange(of: trigger) { GlowHaptics.shared.play(haptic) }
        }
    }
}
