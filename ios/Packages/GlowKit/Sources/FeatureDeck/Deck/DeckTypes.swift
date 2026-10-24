import APIClient
import AppCore
import Foundation

// Owner: C1. The deck's own value types, built from the generated contract types.
//
// Nothing here can hold another person's user ID, name, face or distance (P1): a card is its card
// ID (the check-in ID), a signed image link, its outfit tags and whether *I* tapped it (P5).

typealias Gender = Components.Schemas.Gender
typealias TopColor = Components.Schemas.TopColor
typealias HairLength = Components.Schemas.HairLength
typealias HairColor = Components.Schemas.HairColor
typealias CardExtra = Components.Schemas.CardExtra
typealias CardTags = Components.Schemas.CardTags
typealias DeckEmptyReason = Components.Schemas.DeckEmptyReason

/// One today's-look card.
struct DeckCard: Identifiable, Hashable, Sendable {
    let id: CardID
    /// The signed image link exactly as the server sent it. Relative, lasts CARD_URL_TTL, and only
    /// works for me. Never logged.
    var imageURL: String
    var imageExpiresAt: Date
    let tags: CardTags
    /// I already tapped this person here in the last TAP_TTL. Says nothing about them (P5).
    var tappedByMe: Bool

    init(id: CardID, imageURL: String, imageExpiresAt: Date, tags: CardTags, tappedByMe: Bool) {
        self.id = id
        self.imageURL = imageURL
        self.imageExpiresAt = imageExpiresAt
        self.tags = tags
        self.tappedByMe = tappedByMe
    }

    /// From the contract's card. Nil if the card ID isn't a UUID.
    init?(_ card: Components.Schemas.Card) {
        guard let id = CardID(validating: card.id) else { return nil }
        self.init(
            id: id,
            imageURL: card.image.url,
            imageExpiresAt: card.image.expiresAt,
            tags: card.tags,
            tappedByMe: card.tappedByMe,
        )
    }
}

/// One page of the deck.
struct DeckPage: Hashable, Sendable {
    var cards: [DeckCard]
    var viewsLeftToday: Int
    /// Where the next page starts, when there is one.
    var nextOffset: Int?
    /// Why the page is empty, when it is.
    var emptyReason: DeckEmptyReason?

    init(cards: [DeckCard], viewsLeftToday: Int, nextOffset: Int? = nil, emptyReason: DeckEmptyReason? = nil) {
        self.cards = cards
        self.viewsLeftToday = viewsLeftToday
        self.nextOffset = nextOffset
        self.emptyReason = emptyReason
    }

    init(_ deck: Components.Schemas.Deck) {
        self.init(
            cards: deck.cards.compactMap(DeckCard.init),
            viewsLeftToday: max(0, deck.viewsLeftToday),
            nextOffset: deck.hasMore ? deck.nextOffset : nil,
            emptyReason: deck.cards.isEmpty ? deck.emptyReason : nil,
        )
    }
}

/// The room and my place in it, for the room home.
struct RoomSnapshot: Hashable, Sendable {
    struct Checkin: Hashable, Sendable {
        var joinedAt: Date
        var expiresAt: Date
        /// False after the room's hosts removed my card.
        var visible: Bool

        init(joinedAt: Date, expiresAt: Date, visible: Bool) {
            self.joinedAt = joinedAt
            self.expiresAt = expiresAt
            self.visible = visible
        }
    }

    var name: String
    var slug: String
    var status: Components.Schemas.RoomStatus
    var endsAt: Date
    /// My open check-in here, if any.
    var checkin: Checkin?
    var tapsLeftToday: Int
    var viewsLeftToday: Int

    init(
        name: String,
        slug: String,
        status: Components.Schemas.RoomStatus,
        endsAt: Date,
        checkin: Checkin?,
        tapsLeftToday: Int,
        viewsLeftToday: Int,
    ) {
        self.name = name
        self.slug = slug
        self.status = status
        self.endsAt = endsAt
        self.checkin = checkin
        self.tapsLeftToday = tapsLeftToday
        self.viewsLeftToday = viewsLeftToday
    }

    init(_ state: Components.Schemas.RoomState) {
        self.init(
            name: state.room.name,
            slug: state.room.slug,
            status: state.room.status,
            endsAt: state.room.endsAt,
            checkin: state.checkin.map { Checkin(joinedAt: $0.joinedAt, expiresAt: $0.expiresAt, visible: $0.visible) },
            tapsLeftToday: max(0, state.tapsLeftToday),
            viewsLeftToday: max(0, state.viewsLeftToday),
        )
    }

    /// My check-in is open, now.
    func isCheckedIn(at now: Date) -> Bool {
        guard let checkin else { return false }
        return checkin.expiresAt > now
    }
}

/// What a tap did.
enum TapOutcome: Hashable, Sendable {
    /// Saved, and secret. Says nothing about the other person (P5).
    case sent(tapsLeftToday: Int)
    /// They had tapped me too: a match exists.
    case mutual(MatchID, tapsLeftToday: Int)

    var tapsLeftToday: Int {
        switch self {
        case let .sent(left), let .mutual(_, left): left
        }
    }
}

/// Why a deck call didn't work. Every case is safe to log.
enum DeckFailure: Error, Hashable, Sendable {
    /// 404: it doesn't exist or isn't mine to see (P11). For a tap, the card left my deck.
    case notFound
    /// 409: no taps left today in this room.
    case tapLimitReached
    case rateLimited
    case offline
    case signedOut
    case cancelled
    case unexpected

    init(_ error: APIError) {
        switch error {
        case .notFound: self = .notFound
        case .unauthorized: self = .signedOut
        case .rateLimited: self = .rateLimited
        case .offline: self = .offline
        case .cancelled: self = .cancelled
        case .unexpected: self = .unexpected
        }
    }
}
