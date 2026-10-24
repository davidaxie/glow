import Foundation

/// What an `Identifier` points at. Each kind gets its own type, so a `MatchID` can never be passed
/// where a `RoomID` is expected.
public protocol IdentifierKind: Sendable {
    static var name: String { get }
}

/// A typed wrapper around a server ID (a UUID string).
///
/// There is deliberately no user ID type here: before a mutual match the app never holds another
/// person's ID (P1), and a card's ID is its check-in's ID, never a user ID.
public struct Identifier<Kind: IdentifierKind>: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    /// Wraps a raw ID as is. Use `init?(validating:)` for anything from outside the app.
    public init(rawValue: String) {
        self.rawValue = rawValue.lowercased()
    }

    /// Wraps a raw ID only if it is a UUID. Use this for links and push payloads.
    public init?(validating string: String) {
        guard UUID(uuidString: string) != nil else { return nil }
        self.init(rawValue: string)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String {
        "\(Kind.name)(\(rawValue))"
    }
}

public enum RoomKind: IdentifierKind { public static let name = "room" }
public enum MatchKind: IdentifierKind { public static let name = "match" }
public enum CardKind: IdentifierKind { public static let name = "card" }

/// A room. Rooms are public venues, so their IDs are not personal data.
public typealias RoomID = Identifier<RoomKind>
/// A mutual match between the signed-in person and someone else.
public typealias MatchID = Identifier<MatchKind>
/// A today's-look card. Equal to its check-in's ID, never a user ID.
public typealias CardID = Identifier<CardKind>
