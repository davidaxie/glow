import APIClient
import AppCore
import Foundation

/// A match from my side. The other person is only ever a first name and a photo count: no user ID
/// ever reaches the app, even after a match (P1, D20).
public struct MatchSnapshot: Hashable, Sendable {
    public enum Status: String, Hashable, Sendable {
        /// The choice window is open.
        case choosing
        /// Both chose Find and the glow is on.
        case glowing
        /// The chat is open.
        case chatting
        /// Both tapped We met. The chat stays open.
        case met
    }

    public enum Choice: String, Hashable, Sendable {
        case find
        case chat
    }

    public let id: MatchID
    public var status: Status
    /// The other person's first name.
    public var firstName: String
    /// How many of their photos `GET /api/matches/{id}/photos/{n}` serves.
    public var photoCount: Int
    public var roomName: String
    public var createdAt: Date
    public var choiceDeadline: Date
    public var yourChoice: Choice?

    public init(
        id: MatchID,
        status: Status,
        firstName: String,
        photoCount: Int,
        roomName: String,
        createdAt: Date,
        choiceDeadline: Date,
        yourChoice: Choice? = nil,
    ) {
        self.id = id
        self.status = status
        self.firstName = firstName
        self.photoCount = max(0, min(photoCount, GlowConstants.profilePhotosMax))
        self.roomName = roomName
        self.createdAt = createdAt
        self.choiceDeadline = choiceDeadline
        self.yourChoice = yourChoice
    }

    /// Where this match lives once choosing is over: the glow or the chat. Nil while choosing.
    public var destination: Route? {
        switch status {
        case .choosing: nil
        case .glowing: .glow(id)
        case .chatting, .met: .chat(id)
        }
    }

    /// Seconds left to choose, never below zero.
    public func secondsLeft(at now: Date) -> TimeInterval {
        max(0, choiceDeadline.timeIntervalSince(now))
    }
}

/// What happens after a choice.
public struct ChoiceOutcome: Hashable, Sendable {
    public enum Next: String, Hashable, Sendable {
        /// Waiting for the other person (or for their fresh location check).
        case waiting
        /// Both chose Find: the glow started.
        case glow
        /// The chat opened.
        case chat
    }

    public enum Reason: String, Hashable, Sendable {
        case otherUndecided = "other_undecided"
        case otherLocationStale = "other_location_stale"
        case bothFind = "both_find"
        case choseChat = "chose_chat"
        case timeout
        case notCheckedIn = "not_checked_in"
        case alreadyDecided = "already_decided"
    }

    public let next: Next
    public let reason: Reason
    public let match: MatchSnapshot

    public init(next: Next, reason: Reason, match: MatchSnapshot) {
        self.next = next
        self.reason = reason
        self.match = match
    }
}

/// One row in the matches list.
public struct MatchSummary: Hashable, Sendable, Identifiable {
    public let id: MatchID
    public var status: MatchSnapshot.Status
    public var firstName: String
    public var roomName: String
    public var createdAt: Date
    public var choiceDeadline: Date
    public var lastMessageAt: Date?

    public init(
        id: MatchID,
        status: MatchSnapshot.Status,
        firstName: String,
        roomName: String,
        createdAt: Date,
        choiceDeadline: Date,
        lastMessageAt: Date? = nil,
    ) {
        self.id = id
        self.status = status
        self.firstName = firstName
        self.roomName = roomName
        self.createdAt = createdAt
        self.choiceDeadline = choiceDeadline
        self.lastMessageAt = lastMessageAt
    }

    /// "Now" in the list: choosing or glowing. "Earlier": chatting or met.
    public var isNow: Bool {
        status == .choosing || status == .glowing
    }

    /// The screen a tap on this row opens.
    public var route: Route {
        switch status {
        case .choosing: .match(id)
        case .glowing: .glow(id)
        case .chatting, .met: .chat(id)
        }
    }
}

/// Why a match call failed, in the words the screens need.
public enum MatchError: Error, Hashable, Sendable {
    /// 404: the match ended (unmatch or block), or was never mine. The server never says which (P11).
    case notFound
    /// The fix was outside the room's area.
    case notInRoom
    /// The fix was too rough, or the phone couldn't get one in time.
    case locationInaccurate
    /// Find needs location permission, and it isn't allowed.
    case locationDenied
    case offline
    case rateLimited
    case unauthorized
    case failed

    init(_ error: APIError) {
        switch error {
        case .notFound: self = .notFound
        case .unauthorized: self = .unauthorized
        case .rateLimited: self = .rateLimited
        case .offline: self = .offline
        case .cancelled, .unexpected: self = .failed
        }
    }
}

// MARK: - From the generated contract types

extension MatchSnapshot.Status {
    init(_ status: Components.Schemas.MatchStatus) {
        switch status {
        case .choosing: self = .choosing
        case .glowing: self = .glowing
        case .chatting: self = .chatting
        case .met: self = .met
        }
    }
}

extension MatchSnapshot {
    /// Nil if the server sent an ID that isn't a UUID.
    init?(_ detail: Components.Schemas.MatchDetail) {
        guard let id = MatchID(validating: detail.id) else { return nil }
        self.init(
            id: id,
            status: Status(detail.status),
            firstName: detail.firstName,
            photoCount: detail.photoCount,
            roomName: detail.roomName,
            createdAt: detail.createdAt,
            choiceDeadline: detail.choiceDeadline,
            yourChoice: detail.yourChoice.map { $0 == .find ? .find : .chat },
        )
    }
}

extension ChoiceOutcome {
    init?(_ result: Components.Schemas.ChoiceResult) {
        guard let match = MatchSnapshot(result.match),
              let reason = Reason(rawValue: result.reason.rawValue)
        else { return nil }
        let next: Next = switch result.next {
        case .waiting: .waiting
        case .glow: .glow
        case .chat: .chat
        }
        self.init(next: next, reason: reason, match: match)
    }
}

extension MatchSummary {
    init?(_ summary: Components.Schemas.MatchSummary) {
        guard let id = MatchID(validating: summary.id) else { return nil }
        self.init(
            id: id,
            status: MatchSnapshot.Status(summary.status),
            firstName: summary.firstName,
            roomName: summary.roomName,
            createdAt: summary.createdAt,
            choiceDeadline: summary.choiceDeadline,
            lastMessageAt: summary.lastMessageAt,
        )
    }
}
