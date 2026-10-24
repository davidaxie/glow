import APIClient
import AppCore
import Foundation

// Owner: C1. A made-up room for previews, snapshot tests, the 200-person find test and Debug
// launches (`-GlowDebugDeckFixture 200`). No real people: every card is generated from a seed, and
// there are no user IDs anywhere, only card IDs. The rules mirror `get_deck` and `record_tap`
// (docs/CONTRACTS.md) closely enough to exercise every screen state.

actor FixtureDeckService: DeckService {
    /// One made-up person in the room. The gender is only known here, like on the server, to apply
    /// show me and the gender filter. It never reaches a card.
    struct Person: Hashable, Sendable {
        let card: CardID
        let gender: Gender
        let tags: CardTags
    }

    enum Scenario: String, Sendable, CaseIterable {
        /// A busy room.
        case normal
        /// Nobody else here fits me yet.
        case quiet
        /// My check-in ended.
        case checkinEnded
        /// I'm paused.
        case paused
        /// Today's views are used up.
        case viewLimitReached
    }

    /// The card that always taps back, so tapping it shows the mutual hand-off.
    static let mutualCard = CardID(rawValue: "aaaaaaaa-0000-4000-8000-000000000001")
    /// The match that tapping `mutualCard` makes.
    static let mutualMatch = MatchID(rawValue: "64bfd966-bf7f-426a-b7aa-f0dc371bae1a")
    /// The look the find test hunts for: a woman in a green top, short blonde hair, glasses and
    /// headphones. The only card in the room with all of those.
    static let targetTags = CardTags(topColor: .green, hairLength: .short, hairColor: .blonde, extras: [.glasses, .headphones])

    private(set) var people: [Person]
    private let showMe: Set<Gender>
    private let roomName: String
    private var scenario: Scenario
    private var seen: Set<CardID> = []
    private var tapped: Set<CardID> = []
    private var tapsLeft = GlowConstants.tapsPerRoomPerDay
    private var paused: Bool
    private var checkinEndsAt: Date?
    private let now: @Sendable () -> Date
    private(set) var captures: [Components.Schemas.CaptureKind] = []
    private(set) var deckRequests = 0
    private(set) var leftRoom = false

    /// - Parameters:
    ///   - count: people in the room besides me.
    ///   - showMe: who I want to see.
    init(
        count: Int = 24,
        scenario: Scenario = .normal,
        showMe: Set<Gender> = Set(Gender.allCases),
        roomName: String = "Glow demo room (test data)",
        seed: UInt64 = 26,
        now: @escaping @Sendable () -> Date = Date.init,
    ) {
        people = scenario == .quiet ? [] : Self.makePeople(count: count, seed: seed)
        self.showMe = showMe
        self.roomName = roomName
        self.scenario = scenario
        self.now = now
        paused = scenario == .paused
        checkinEndsAt = scenario == .checkinEnded ? nil : now().addingTimeInterval(2 * 3600 + 41 * 60)
        if scenario == .viewLimitReached {
            // Cards seen earlier today that have since left: the cap is used up.
            seen = Set((0 ..< GlowConstants.cardViewsPerRoomPerDay).map { CardID(rawValue: Self.fixtureUUID(10000 + $0)) })
        }
    }

    // MARK: DeckService

    func roomState(_: RoomID) async throws(DeckFailure) -> RoomSnapshot {
        RoomSnapshot(
            name: roomName,
            slug: "demo",
            status: .live,
            endsAt: now().addingTimeInterval(6 * 3600),
            checkin: checkinEndsAt.map { RoomSnapshot.Checkin(joinedAt: now().addingTimeInterval(-19 * 60), expiresAt: $0, visible: true) },
            tapsLeftToday: tapsLeft,
            viewsLeftToday: max(0, GlowConstants.cardViewsPerRoomPerDay - seen.count),
        )
    }

    func deck(_: RoomID, filters: NoticedFilters, offset: Int) async throws(DeckFailure) -> DeckPage {
        deckRequests += 1
        let limit = GlowConstants.cardViewsPerRoomPerDay
        guard isCheckedIn else {
            return DeckPage(cards: [], viewsLeftToday: viewsLeft, emptyReason: .checkinEnded)
        }
        if paused {
            return DeckPage(cards: [], viewsLeftToday: viewsLeft, emptyReason: .paused)
        }
        let eligible = people.filter { showMe.contains($0.gender) }
        if eligible.isEmpty {
            return DeckPage(cards: [], viewsLeftToday: viewsLeft, emptyReason: .quiet)
        }
        let fitting = eligible.filter { filters.matches($0.tags, gender: $0.gender) }
        // Like get_deck: cards already seen today are free; new ones count until the cap.
        var visible: [Person] = []
        var newViews = seen
        for person in fitting {
            if newViews.contains(person.card) {
                visible.append(person)
            } else if newViews.count < limit {
                newViews.insert(person.card)
                visible.append(person)
            }
        }
        let page = Array(visible.dropFirst(offset).prefix(GlowConstants.deckPageSize))
        seen.formUnion(page.map(\.card))
        let next = offset + page.count
        let hasMore = next < visible.count
        if page.isEmpty {
            let reason: DeckEmptyReason = fitting.isEmpty ? .noMatch : .viewLimitReached
            return DeckPage(cards: [], viewsLeftToday: viewsLeft, emptyReason: offset == 0 ? reason : nil)
        }
        let expires = now().addingTimeInterval(GlowConstants.cardURLTTL)
        let cards = page.map { person in
            DeckCard(
                id: person.card,
                imageURL: Self.imageURL(for: person, expires: expires),
                imageExpiresAt: expires,
                tags: person.tags,
                tappedByMe: tapped.contains(person.card),
            )
        }
        return DeckPage(cards: cards, viewsLeftToday: viewsLeft, nextOffset: hasMore ? next : nil)
    }

    func tap(_ card: CardID, in _: RoomID) async throws(DeckFailure) -> TapOutcome {
        guard isCheckedIn, !paused, seen.contains(card), people.contains(where: { $0.card == card }) else {
            throw .notFound
        }
        if !tapped.contains(card) {
            guard tapsLeft > 0 else { throw .tapLimitReached }
            tapsLeft -= 1
            tapped.insert(card)
        }
        if card == Self.mutualCard {
            return .mutual(Self.mutualMatch, tapsLeftToday: tapsLeft)
        }
        return .sent(tapsLeftToday: tapsLeft)
    }

    func leave(_: RoomID) async throws(DeckFailure) {
        leftRoom = true
        checkinEndsAt = nil
    }

    func setPaused(_ paused: Bool) async throws(DeckFailure) -> Bool {
        self.paused = paused
        return paused
    }

    func reportCapture(_ kind: Components.Schemas.CaptureKind, in _: RoomID) async {
        captures.append(kind)
    }

    // MARK: Driving the room (tests and previews)

    /// Someone leaves, pauses or blocks: their card leaves the room (P8).
    func remove(_ card: CardID) {
        people.removeAll { $0.card == card }
    }

    /// Someone new checks in.
    func add(_ person: Person) {
        people.insert(person, at: 0)
    }

    var isPaused: Bool {
        paused
    }

    // MARK: Helpers

    private var isCheckedIn: Bool {
        guard let checkinEndsAt else { return false }
        return checkinEndsAt > now()
    }

    private var viewsLeft: Int {
        max(0, GlowConstants.cardViewsPerRoomPerDay - seen.count)
    }

    /// A link shaped like the server's, plus the top color, so the fixture image loader can draw the
    /// look. Only `FixtureImagingService` ever reads these.
    static func imageURL(for person: Person, expires: Date) -> String {
        let exp = Int(expires.timeIntervalSince1970)
        return "/api/cards/\(person.card.rawValue)/image?exp=\(exp)&sig=fixture&top=\(person.tags.topColor.rawValue)"
    }

    /// `count` made-up people, the same for the same seed. The first card always taps back; the
    /// target look is somewhere in the middle, and nobody else has all of its tags.
    static func makePeople(count: Int, seed: UInt64) -> [Person] {
        var random = SplitMix64(seed: seed)
        var people: [Person] = []
        let targetIndex = count > 1 ? count * 3 / 5 : 0
        for index in 0 ..< count {
            let card = index == 0 ? mutualCard : CardID(rawValue: fixtureUUID(index))
            if index == targetIndex {
                people.append(Person(card: card, gender: .woman, tags: targetTags))
                continue
            }
            var tags: CardTags
            repeat {
                tags = CardTags(
                    topColor: random.pick(TopColor.allCases),
                    hairLength: random.chance(0.9) ? random.pick(HairLength.allCases) : nil,
                    hairColor: random.chance(0.9) ? random.pick(HairColor.allCases) : nil,
                    extras: CardExtra.allCases.filter { _ in random.chance(0.22) },
                )
            } while tags.isTargetLook
            people.append(Person(card: card, gender: random.pick(Gender.allCases), tags: tags))
        }
        return people
    }

    static func fixtureUUID(_ index: Int) -> String {
        String(format: "aaaaaaaa-0000-4000-8000-%012x", index + 1)
    }
}

extension CardTags {
    /// Has every tag of the find test's target (it may have more).
    fileprivate var isTargetLook: Bool {
        let target = FixtureDeckService.targetTags
        return topColor == target.topColor && hairLength == target.hairLength && hairColor == target.hairColor
            && Set(target.extras).isSubset(of: Set(extras))
    }
}

/// A tiny seeded generator, so fixture rooms are the same on every run.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func pick<Value>(_ values: [Value]) -> Value {
        values[Int(next() % UInt64(values.count))]
    }

    mutating func chance(_ probability: Double) -> Bool {
        Double(next() % 10000) / 10000 < probability
    }
}
