import ActivityKit
import Foundation

// Placeholder from A3. Owner: C3.
// Shared by FeatureGlow (which starts the activity) and the GlowLiveActivity widget extension
// (which draws it). It lives in its own tiny module so the extension doesn't link the API stack.

/// The glow countdown on the lock screen and in the Dynamic Island.
/// Never includes a name (P6): only the color, the code word and the meeting spot.
public struct GlowActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        /// When the glow ends (GLOW_TTL after it starts).
        public var endsAt: Date

        public init(endsAt: Date) {
            self.endsAt = endsAt
        }
    }

    /// One of the eight glow color names from the design system, like "Aqua".
    public var colorName: String
    public var codeWord: String
    public var meetingSpot: String

    public init(colorName: String, codeWord: String, meetingSpot: String) {
        self.colorName = colorName
        self.codeWord = codeWord
        self.meetingSpot = meetingSpot
    }
}
