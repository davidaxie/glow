import ActivityKit
import Foundation

// Owner: C3. Shared by FeatureGlow (which starts, updates and ends the activity) and the
// GlowLiveActivity widget extension (which draws it). It lives in its own tiny module so the
// extension doesn't link the API stack (D41).

/// The glow countdown on the lock screen and in the Dynamic Island.
///
/// Privacy (P1, P6): only what's already on the glow screen. The color, the code word, the meeting
/// spot and the time. Never a name, a photo, a user ID or a match ID. `glowID` is the glow session's
/// own random ID, which the app uses to find this activity again; it's never shown.
public struct GlowActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        /// Where the glow is: on, or how it ended.
        public var phase: GlowActivityPhase
        /// When the glow ends (GLOW_TTL after it starts). The countdown runs to this.
        public var endsAt: Date

        public init(phase: GlowActivityPhase, endsAt: Date) {
            self.phase = phase
            self.endsAt = endsAt
        }
    }

    /// The glow session's ID, to find this activity again. Never shown.
    public var glowID: String
    /// The glow color's contract name (`GlowColor`), like "aqua". The extension draws it with
    /// DesignSystem's `GlowHue(rawValue:)`.
    public var color: String
    /// Lowercase, as the API sends it. Shown in capitals.
    public var codeWord: String
    /// The meeting spot's name, like "Water station", if the room has one.
    public var meetingSpot: String?
    /// When the glow started, for the progress bar.
    public var startedAt: Date

    public init(glowID: String, color: String, codeWord: String, meetingSpot: String?, startedAt: Date) {
        self.glowID = glowID
        self.color = color
        self.codeWord = codeWord
        self.meetingSpot = meetingSpot
        self.startedAt = startedAt
    }
}

/// Where a glow is, as the lock screen tells it.
public enum GlowActivityPhase: String, Codable, Hashable, Sendable, CaseIterable {
    /// On, nobody has tapped We met yet.
    case glowing
    /// On, and I tapped We met. Waiting for them.
    case youMet
    /// On, and they tapped We met. My turn.
    case theyMet
    /// Both tapped We met.
    case met
    /// Someone canceled or switched to chat.
    case canceled
    /// The time ran out.
    case expired

    /// Whether the glow is over.
    public var isOver: Bool {
        switch self {
        case .glowing, .youMet, .theyMet: false
        case .met, .canceled, .expired: true
        }
    }
}
