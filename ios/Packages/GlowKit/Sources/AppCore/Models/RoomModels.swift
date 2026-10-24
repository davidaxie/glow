import Foundation

/// What a room's QR code, poster or link carries: `https://{DOMAIN}/r/{slug}?t={token}`.
///
/// A link only gets someone as far as the location check, never into a room by itself.
/// Its `description` never prints the token, so logging a route can't leak it.
public struct RoomLink: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Lowercase letters, digits and dashes.
    public let slug: String
    /// A static poster token or a rotating screen token. Nil when the link had none (the person can type the room code).
    public let token: String?

    public init(slug: String, token: String?) {
        self.slug = slug.lowercased()
        self.token = token
    }

    public var description: String {
        "RoomLink(slug: \(slug), token: \(token == nil ? "none" : "redacted"))"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["slug": slug])
    }

    /// Slugs: 1 to 64 of a-z, 0-9 and dashes, not starting or ending with a dash.
    public static func isValidSlug(_ slug: String) -> Bool {
        let scalars = Array(slug.unicodeScalars)
        guard (1 ... 64).contains(scalars.count), scalars.first != "-", scalars.last != "-" else { return false }
        return scalars.allSatisfy { ("a" ... "z").contains($0) || ("0" ... "9").contains($0) || $0 == "-" }
    }

    /// Tokens: 1 to 128 of A-Z, a-z, 0-9, dash and underscore (base32 and base64url both fit).
    public static func isValidToken(_ token: String) -> Bool {
        let scalars = Array(token.unicodeScalars)
        guard (1 ... 128).contains(scalars.count) else { return false }
        return scalars.allSatisfy {
            ("a" ... "z").contains($0) || ("A" ... "Z").contains($0) || ("0" ... "9").contains($0) || $0 == "-" || $0 == "_"
        }
    }
}

/// The 10-minute join ticket `POST /api/rooms/:id/join` returns, which check-in needs.
/// Never printed or logged.
public struct JoinTicket: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        "JoinTicket(redacted)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}

/// Where a block or report starts from. The server works out who the person is (B8),
/// so the app never needs their user ID.
public enum SafetyContext: Hashable, Sendable {
    case card(CardID)
    case match(MatchID)
    case chat(MatchID)
}
