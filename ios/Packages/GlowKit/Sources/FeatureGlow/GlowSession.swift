import APIClient
import DesignSystem
import Foundation
import LiveActivityShared

// Owner: C3. A glow, as the glow screen and the Live Activity use it.

/// One glow session, from my side. Built from the API's `Glow`: the other person is only ever
/// "they" (theyMet), never a name or an ID (P1).
public struct GlowSession: Hashable, Sendable {
    public enum Status: String, Hashable, Sendable {
        case active, met, canceled, expired
    }

    public var id: String
    public var status: Status
    public var hue: GlowHue
    /// Lowercase, as the API sends it. `displayWord` is what the screen shows.
    public var codeWord: String
    public var meetingSpot: String?
    public var startedAt: Date
    public var endsAt: Date
    public var endedAt: Date?
    public var youMet: Bool
    public var theyMet: Bool

    public init(
        id: String,
        status: Status,
        hue: GlowHue,
        codeWord: String,
        meetingSpot: String?,
        startedAt: Date,
        endsAt: Date,
        endedAt: Date? = nil,
        youMet: Bool = false,
        theyMet: Bool = false,
    ) {
        self.id = id
        self.status = status
        self.hue = hue
        self.codeWord = codeWord
        self.meetingSpot = meetingSpot
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.endedAt = endedAt
        self.youMet = youMet
        self.theyMet = theyMet
    }

    /// The code word in capitals (the contract: "Show it in capitals, in SF Pro Rounded").
    public var displayWord: String {
        codeWord.uppercased()
    }

    /// Whether the glow is still on at `now`. A glow past its end is over even before the server
    /// says so.
    public func isOn(at now: Date) -> Bool {
        status == .active && now < endsAt
    }

    /// The Live Activity's phase for this glow at `now`.
    public func activityPhase(at now: Date) -> GlowActivityPhase {
        switch status {
        case .met: return .met
        case .canceled: return .canceled
        case .expired: return .expired
        case .active:
            if now >= endsAt { return .expired }
            if youMet { return .youMet }
            if theyMet { return .theyMet }
            return .glowing
        }
    }

    /// The Live Activity's fixed data. Only what's already on the glow screen (P6).
    public var activityAttributes: GlowActivityAttributes {
        GlowActivityAttributes(
            glowID: id,
            color: hue.rawValue,
            codeWord: codeWord,
            meetingSpot: meetingSpot,
            startedAt: startedAt,
        )
    }

    public func activityState(at now: Date) -> GlowActivityAttributes.ContentState {
        .init(phase: activityPhase(at: now), endsAt: endsAt)
    }
}

extension GlowSession {
    /// From the API's Glow. The hue falls back to Pearl only if the contract ever gains a color
    /// the app doesn't know yet.
    public init(_ glow: Components.Schemas.Glow) {
        self.init(
            id: glow.id,
            status: Status(glow.status),
            hue: GlowHue(rawValue: glow.color.rawValue) ?? .pearl,
            codeWord: glow.codeWord,
            meetingSpot: glow.meetingSpot?.name,
            startedAt: glow.startedAt,
            endsAt: glow.endsAt,
            endedAt: glow.endedAt,
            youMet: glow.youMet,
            theyMet: glow.theyMet,
        )
    }
}

extension GlowSession.Status {
    init(_ status: Components.Schemas.GlowStatus) {
        switch status {
        case .active: self = .active
        case .met: self = .met
        case .canceled: self = .canceled
        case .expired: self = .expired
        }
    }
}
