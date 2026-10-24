import APIClient
import AppCore
import Foundation

/// How someone got to a room: a QR link (slug plus token) or a typed room code.
/// Either one only gets them to the location check, never into the room by itself.
public enum RoomEntry: Hashable, Sendable, CustomStringConvertible {
    case link(slug: String, token: String)
    case code(String)

    /// A link with no token can't be resolved; the person types the code instead.
    public init?(link: RoomLink) {
        guard let token = link.token else { return nil }
        self = .link(slug: link.slug, token: token)
    }

    /// For analytics: how they came in. Never the code or token itself.
    var via: AnalyticsValue {
        switch self {
        case .link: "link"
        case .code: "code"
        }
    }

    /// A rotating screen token (8 characters) goes stale in 30 to 60 seconds; a poster token (16)
    /// doesn't. Tells "the code on the screen changed" apart from "no such room".
    var isRotatingToken: Bool {
        if case let .link(_, token) = self {
            return token.count == GlowConstants.qrTokenLength
        }
        return false
    }

    /// Never prints the token (it opens the room's location check).
    public var description: String {
        switch self {
        case let .link(slug, _): "RoomEntry.link(\(slug), token: redacted)"
        case .code: "RoomEntry.code(redacted)"
        }
    }
}

/// Room codes: ROOM_CODE_LENGTH characters from ABCDEFGHJKLMNPQRSTUVWXYZ23456789. People type them
/// in any case, with spaces or dashes; the look-alikes O, 0, I, 1 are never in a code.
public enum RoomCode {
    public static let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    public static let length = GlowConstants.roomCodeLength

    /// Uppercases, drops spaces and dashes, and keeps only characters a code can have,
    /// up to the code's length. For live filtering of the text field.
    public static func normalize(_ input: String) -> String {
        String(input.uppercased().filter { alphabet.contains($0) }.prefix(length))
    }

    public static func isComplete(_ code: String) -> Bool {
        code.count == length && code.allSatisfy { alphabet.contains($0) }
    }
}

/// What the app may know about a room: never its location or secrets.
public struct RoomInfo: Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        case live
        case paused
        case ended
    }

    public let id: RoomID
    public let slug: String
    public let name: String
    public let status: Status
    public let startsAt: Date
    public let endsAt: Date

    public init(id: RoomID, slug: String, name: String, status: Status, startsAt: Date, endsAt: Date) {
        self.id = id
        self.slug = slug
        self.name = name
        self.status = status
        self.startsAt = startsAt
        self.endsAt = endsAt
    }

    /// Why this room can't be joined right now, if it can't.
    func closedReason(now: Date) -> JoinFailure? {
        switch status {
        case .ended: return .roomEnded
        case .paused: return .roomPaused
        case .live:
            if now >= endsAt {
                return .roomEnded
            }
            if now < startsAt {
                return .roomNotOpenYet(startsAt)
            }
            return nil
        }
    }
}
