import Foundation

// Owner: X2 (Blind mode). This file and Mocks/PreviewBlindService.swift change together.
//
// Blind mode is Double Blind inside Glow: opt in, swipe on photos only, mutual likes stay hidden
// until a drop opens them as blind chats with codenames, and names show only when both tap Reveal.
//
// Blindness (Double Blind's B1): before a mutual reveal nothing here carries another person's ID,
// name or anything about rooms or location. A card's ID is opaque and different for every viewer
// (`blind_cards` on the server), so it can only be used to swipe or guess. A chat's partner exists
// only on a revealed `BlindChatDetail`.

public enum BlindChatKind: IdentifierKind { public static let name = "blind_chat" }
public enum BlindCardKind: IdentifierKind { public static let name = "blind_card" }

/// A blind chat. The caller's own chat ID, never a user ID.
public typealias BlindChatID = Identifier<BlindChatKind>
/// A Blind deck or Guess Who card. Opaque and per viewer: never a user ID (B1).
public typealias BlindCardID = Identifier<BlindCardKind>

/// The fixed numbers of Blind mode (Double Blind's contract constants).
public enum BlindRulesConstants {
    /// Right swipes (like or love) allowed per UTC day (B4).
    public static let dailyRightLimit = 20
    /// Lifetime right swipes needed before a drop can open (B3).
    public static let dropMinimumRightSwipes = 5
    /// At most this many chats open in one drop.
    public static let dropMaximumChats = 5
    /// The longest message.
    public static let messageMaxLength = 1000
    /// The longest report reason.
    public static let reportMaxLength = 500
}

/// A signed photo link as the server sent it. It expires within a minute and works only for the
/// person it was made for. Never printed.
public struct BlindPhoto: Hashable, Sendable, CustomStringConvertible {
    public let url: String

    public init(url: String) {
        self.url = url
    }

    public var description: String {
        "BlindPhoto(redacted)"
    }
}

/// `GET /api/blind/me`: whether I joined, and my own counters. Nothing about anyone else.
public struct BlindMe: Hashable, Sendable {
    public var isMember: Bool
    public var rightRemaining: Int
    public var rightCount: Int
    public var canDrop: Bool

    public init(isMember: Bool, rightRemaining: Int, rightCount: Int, canDrop: Bool) {
        self.isMember = isMember
        self.rightRemaining = rightRemaining
        self.rightCount = rightCount
        self.canDrop = canDrop
    }
}

/// A photo-only card. No name, age, distance or room.
public struct BlindCard: Hashable, Sendable, Identifiable {
    public let id: BlindCardID
    public let photo: BlindPhoto

    public init(id: BlindCardID, photo: BlindPhoto) {
        self.id = id
        self.photo = photo
    }
}

public enum BlindSwipeKind: String, Hashable, Sendable, CaseIterable {
    case pass, like, love

    public var isRight: Bool {
        self != .pass
    }
}

/// The reply to a swipe: my own counters only. Never whether they liked back (B2).
public struct BlindSwipeResult: Hashable, Sendable {
    public var rightRemaining: Int
    public var rightCount: Int

    public init(rightRemaining: Int, rightCount: Int) {
        self.rightRemaining = rightRemaining
        self.rightCount = rightCount
    }
}

/// `GET /api/blind/pool`: my lifetime right swipes and today's remaining ones.
public struct BlindPool: Hashable, Sendable {
    public var rightCount: Int
    public var rightRemaining: Int
    public var canDrop: Bool

    public init(rightCount: Int, rightRemaining: Int, canDrop: Bool) {
        self.rightCount = rightCount
        self.rightRemaining = rightRemaining
        self.canDrop = canDrop
    }
}

/// `GET /api/blind/drop`. Deliberately nothing about waiting matches (B2): a drop is the only way
/// to learn what is in it.
public struct BlindDropStatus: Hashable, Sendable {
    /// True in demo mode, or inside the nightly window.
    public var ready: Bool
    /// True when the server runs with `BLIND_DEMO_MODE` (stage only): a drop opens any time.
    public var demo: Bool
    /// The next nightly drop (8pm Pacific).
    public var nextDropAt: Date
    public var rightCount: Int
    /// `rightCount >= 5`.
    public var canDrop: Bool

    public init(ready: Bool, demo: Bool, nextDropAt: Date, rightCount: Int, canDrop: Bool) {
        self.ready = ready
        self.demo = demo
        self.nextDropAt = nextDropAt
        self.rightCount = rightCount
        self.canDrop = canDrop
    }
}

/// One chat a drop opened: my chat ID and the codename I know them by.
public struct BlindDropChat: Hashable, Sendable, Identifiable {
    public let id: BlindChatID
    public let codename: String

    public init(id: BlindChatID, codename: String) {
        self.id = id
        self.codename = codename
    }
}

/// `POST /api/blind/drop`: the chats new to me, whoever's drop opened them.
public struct BlindDropResult: Hashable, Sendable {
    public var opened: Int
    public var chats: [BlindDropChat]

    public init(opened: Int, chats: [BlindDropChat]) {
        self.opened = opened
        self.chats = chats
    }
}

public enum BlindChatStatus: String, Hashable, Sendable {
    case open, left, revealed
}

public struct BlindLastMessage: Hashable, Sendable {
    public var mine: Bool
    public var text: String
    public var at: Date

    public init(mine: Bool, text: String, at: Date) {
        self.mine = mine
        self.text = text
        self.at = at
    }
}

public struct BlindChatSummary: Hashable, Sendable, Identifiable {
    public let id: BlindChatID
    public var codename: String
    public var status: BlindChatStatus
    public var lastMessage: BlindLastMessage?
    public var unread: Bool

    public init(id: BlindChatID, codename: String, status: BlindChatStatus, lastMessage: BlindLastMessage?, unread: Bool) {
        self.id = id
        self.codename = codename
        self.status = status
        self.lastMessage = lastMessage
        self.unread = unread
    }
}

/// Who they are. Only ever present on a revealed chat (B1).
public struct BlindPartner: Hashable, Sendable {
    public var name: String
    public var photos: [BlindPhoto]

    public init(name: String, photos: [BlindPhoto]) {
        self.name = name
        self.photos = photos
    }
}

public struct BlindChatDetail: Hashable, Sendable, Identifiable {
    public let id: BlindChatID
    public var codename: String
    public var status: BlindChatStatus
    /// My own tap only. Nothing says whether they tapped (B5).
    public var iTappedReveal: Bool
    public var theyLeft: Bool
    /// Only when `status == .revealed`.
    public var partner: BlindPartner?
    /// Only after the reveal, and only if I guessed: nil (no guess), right or wrong.
    public var guessCorrect: Bool? // swiftlint:disable:this discouraged_optional_boolean

    public init(
        id: BlindChatID,
        codename: String,
        status: BlindChatStatus,
        iTappedReveal: Bool,
        theyLeft: Bool,
        partner: BlindPartner? = nil,
        guessCorrect: Bool? = nil, // swiftlint:disable:this discouraged_optional_boolean
    ) {
        self.id = id
        self.codename = codename
        self.status = status
        self.iTappedReveal = iTappedReveal
        self.theyLeft = theyLeft
        self.partner = partner
        self.guessCorrect = guessCorrect
    }
}

public struct BlindMessage: Hashable, Sendable, Identifiable {
    public let id: Int
    public let mine: Bool
    public let text: String
    public let at: Date

    public init(id: Int, mine: Bool, text: String, at: Date) {
        self.id = id
        self.mine = mine
        self.text = text
        self.at = at
    }
}

/// When `warning` is set the message was NOT sent: send again with `confirm: true` to send anyway.
public struct BlindSendResult: Hashable, Sendable {
    public var message: BlindMessage?
    public var warning: String?

    public init(message: BlindMessage? = nil, warning: String? = nil) {
        self.message = message
        self.warning = warning
    }
}

/// What a Blind call ended in, when it didn't work.
public enum BlindError: Error, Hashable, Sendable {
    /// 404: it doesn't exist or isn't mine (P11), including a chat the other person blocked.
    case notFound
    /// 409 `right_cap_reached`: no right swipes left today.
    case rightCapReached
    /// 409 `drop_not_ready`: before the nightly drop.
    case dropNotReady
    /// 409: the chat is closed (they left).
    case chatClosed
    /// 400: the request broke the contract.
    case invalid
    case rateLimited
    case offline
    case unauthorized
    case cancelled
    case unexpected

    /// A calm sentence for the screen. Never echoes anything the server sent.
    public var message: String {
        switch self {
        case .notFound: String(localized: "That isn't available any more.")
        case .rightCapReached: String(localized: "You're out of right swipes for today.")
        case .dropNotReady: String(localized: "Your drop opens at 8pm.")
        case .chatClosed: String(localized: "They left this chat.")
        case .invalid: String(localized: "That didn't go through. Check it and try again.")
        case .rateLimited: String(localized: "Slow down a little and try again.")
        case .offline: String(localized: "You're offline. Try again in a moment.")
        case .unauthorized: String(localized: "Sign in again to continue.")
        case .cancelled: String(localized: "Cancelled.")
        case .unexpected: String(localized: "Something went wrong. Try again.")
        }
    }
}

/// Every call Blind mode makes. `LiveBlindService` (FeatureBlind) is the real API under
/// `/api/blind/*`; `PreviewBlindService` follows the same rules in memory, for previews, tests and
/// Debug Simulator runs (`-GlowDebugBlind`).
public protocol BlindService: Sendable {
    // Membership
    func me() async throws(BlindError) -> BlindMe
    /// Opt in. Your photos (never your name) are shown to other Blind members.
    func join() async throws(BlindError) -> BlindMe
    /// Opt out. Deletes your Blind swipes, matches and chats.
    func leaveBlind() async throws(BlindError)

    // Deck
    func deck(limit: Int) async throws(BlindError) -> [BlindCard]
    func swipe(_ card: BlindCardID, kind: BlindSwipeKind) async throws(BlindError) -> BlindSwipeResult
    func pool() async throws(BlindError) -> BlindPool
    /// Guess Who: my own right swipes as photo-only cards. Never filtered by matches, chats or
    /// blocks, so the list can't give a chat partner away (B1).
    func poolCards() async throws(BlindError) -> [BlindCard]

    // Drop
    func dropStatus() async throws(BlindError) -> BlindDropStatus
    /// Opens my waiting chats. Throws `.dropNotReady` before the drop.
    func openDrop() async throws(BlindError) -> BlindDropResult

    // Chats
    func chats() async throws(BlindError) -> [BlindChatSummary]
    func chat(_ id: BlindChatID) async throws(BlindError) -> BlindChatDetail
    func messages(_ id: BlindChatID, after: Int?) async throws(BlindError) -> [BlindMessage]
    func send(_ id: BlindChatID, text: String, confirm: Bool) async throws(BlindError) -> BlindSendResult
    func reveal(_ id: BlindChatID) async throws(BlindError) -> BlindChatStatus
    func leaveChat(_ id: BlindChatID) async throws(BlindError)
    func guess(_ id: BlindChatID, card: BlindCardID) async throws(BlindError)

    // Safety: Glow's own blocks and reports, so a block applies in both modes.
    func block(_ id: BlindChatID) async throws(BlindError)
    func report(_ id: BlindChatID, reason: String) async throws(BlindError)

    // Photos
    /// Loads a signed photo into memory. Nothing is cached on disk.
    func photo(_ photo: BlindPhoto) async throws(BlindError) -> PrivateImage
}
