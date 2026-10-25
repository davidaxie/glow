import Foundation
import UIKit

// Owner: X2 (Blind mode). The state behind PreviewBlindService; changes with Services/BlindService.swift.

/// The mock's state and rules as a plain value, so the actor only adds isolation and latency.
struct BlindWorld {
    /// Someone in the made-up Blind pool.
    struct Person {
        let card: BlindCardID
        let photoSeed: Int
        let name: String
        /// Did they swipe right on me? Never sent anywhere: only a drop can tell (B2).
        let likesMe: Bool
        var swiped: BlindSwipeKind?
        var blocked = false
    }

    struct Conversation {
        let id: BlindChatID
        let codename: String
        let person: Int
        var status: BlindChatStatus = .open
        var theyLeft = false
        var iTapped = false
        var theyTapped = false
        var unread = false
        var guess: BlindCardID?
        var messages: [BlindMessage] = []

        var lastActivity: Date {
            messages.last?.at ?? .distantPast
        }
    }

    private static let names = [
        "Jordan", "Sam", "Riley", "Avery", "Quinn", "Rowan", "Sky", "Noa", "Remy", "Ari",
        "Jules", "Kai", "Emery", "Sage", "Robin", "Milan", "Dani", "Reese", "Ollie", "Wren",
    ]

    var dropReady: Bool
    let autoReply: Bool
    var isMember: Bool
    var rightToday = 0
    var people: [Person]
    /// Mutual right swipes the drop hasn't opened yet. Indexes into `people`.
    var waiting: [Int] = []
    var conversations: [Conversation] = []
    var nextMessageID = 100
    var nextChatNumber = 10
    var usedCodenames: Set<String> = []
    let now = Date()

    init(_ options: PreviewBlindService.Options) {
        dropReady = options.dropReady
        autoReply = options.autoReply
        isMember = options.scenario != .newcomer
        people = (0 ..< 20).map { index in
            Person(
                card: Self.cardID(index + 1),
                photoSeed: index,
                name: Self.names[index],
                // Every other person likes me back, so a demo always has matches.
                likesMe: index.isMultiple(of: 2),
            )
        }
        switch options.scenario {
        case .newcomer:
            break
        case .swiping:
            // 0 and 2 like me back, 1 doesn't: two waiting matches, invisible until the drop.
            preSwipe([0, 1, 2])
        case .dropReady:
            preSwipe([0, 1, 2, 3, 4, 5])
        case .chatting, .revealed:
            preSwipe([0, 1, 2, 3, 4, 5, 6, 7])
            waiting = []
            openStartingChats(revealed: options.scenario == .revealed)
        case .capReached:
            preSwipe(Array(0 ..< 20))
        }
    }

    // MARK: Ids

    static func cardID(_ number: Int) -> BlindCardID {
        BlindCardID(rawValue: "b1ca0000-0000-4000-8000-" + String(format: "%012x", number))
    }

    static func chatID(_ number: Int) -> BlindChatID {
        BlindChatID(rawValue: "b1c40000-0000-4000-8000-" + String(format: "%012x", number))
    }

    static func photo(seed: Int) -> BlindPhoto {
        BlindPhoto(url: "mock://blind/\(seed)")
    }

    // MARK: Setup

    /// Right swipes made "earlier": they count toward the pool and today's cap.
    private mutating func preSwipe(_ indexes: [Int]) {
        for index in indexes {
            people[index].swiped = index.isMultiple(of: 3) ? .love : .like
            rightToday += 1
            if people[index].likesMe {
                waiting.append(index)
            }
        }
    }

    private mutating func openStartingChats(revealed: Bool) {
        var fox = Conversation(id: Self.chatID(1), codename: "Fox", person: 0, unread: true)
        fox.theyTapped = true
        fox.messages = [
            message(1, mine: false, "Hi, stranger. Best way to waste a Saturday?", minutesAgo: 30),
            message(2, mine: true, "Walking somewhere with no plan and getting lost on purpose.", minutesAgo: 28),
            message(3, mine: false, "Same. Coffee first, always.", minutesAgo: 20),
            message(4, mine: false, "Okay, what's your actual hot take?", minutesAgo: 4),
        ]
        if revealed {
            fox.iTapped = true
            fox.status = .revealed
            fox.unread = false
            fox.guess = people[0].card
        }
        var comet = Conversation(id: Self.chatID(2), codename: "Comet", person: 2)
        comet.messages = [
            message(10, mine: false, "Settle this: cats or dogs?", minutesAgo: 70),
            message(11, mine: true, "Dogs, but I respect a cat with opinions.", minutesAgo: 60),
        ]
        let otter = Conversation(id: Self.chatID(3), codename: "Otter", person: 4)
        conversations = [fox, comet, otter]
        usedCodenames = ["Fox", "Comet", "Otter"]
    }

    private func message(_ id: Int, mine: Bool, _ text: String, minutesAgo: Double) -> BlindMessage {
        BlindMessage(id: id, mine: mine, text: text, at: now.addingTimeInterval(-minutesAgo * 60))
    }

    // MARK: Rules

    mutating func leave() {
        isMember = false
        // Leaving deletes my Blind swipes, matches and chats.
        for index in people.indices {
            people[index].swiped = nil
        }
        waiting = []
        conversations = []
        usedCodenames = []
        rightToday = 0
    }

    func deck(limit: Int) throws(BlindError) -> [BlindCard] {
        try requireMember()
        let open = people.indices.filter { people[$0].swiped == nil && !people[$0].blocked }
        return open.prefix(limit).map { card($0) }
    }

    mutating func swipe(_ cardID: BlindCardID, kind: BlindSwipeKind) throws(BlindError) -> BlindSwipeResult {
        try requireMember()
        guard let index = people.firstIndex(where: { $0.card == cardID }), !people[index].blocked else { throw .notFound }
        guard people[index].swiped == nil else {
            return BlindSwipeResult(rightRemaining: rightRemaining, rightCount: rightCount)
        }
        if kind.isRight {
            guard rightToday < BlindRulesConstants.dailyRightLimit else { throw .rightCapReached }
            rightToday += 1
            if people[index].likesMe {
                waiting.append(index)
            }
        }
        people[index].swiped = kind
        // B2: nothing here says whether they liked back.
        return BlindSwipeResult(rightRemaining: rightRemaining, rightCount: rightCount)
    }

    func poolCards() throws(BlindError) -> [BlindCard] {
        try requireMember()
        // Exactly my right swipes, blocks and chats or not (B1).
        return people.indices.filter { people[$0].swiped?.isRight == true }.map { card($0) }
    }

    mutating func openDrop() throws(BlindError) -> BlindDropResult {
        try requireMember()
        guard dropReady else { throw .dropNotReady }
        // B3: under 5 right swipes nothing opens; the contract has no error for it.
        guard canDrop else { return BlindDropResult(opened: 0, chats: []) }
        let opening = Array(waiting.prefix(BlindRulesConstants.dropMaximumChats))
        waiting.removeFirst(opening.count)
        var fresh: [BlindDropChat] = []
        for person in opening where !people[person].blocked {
            let chat = Conversation(id: Self.chatID(nextChatNumber), codename: nextCodename(), person: person)
            nextChatNumber += 1
            conversations.append(chat)
            fresh.append(BlindDropChat(id: chat.id, codename: chat.codename))
        }
        return BlindDropResult(opened: fresh.count, chats: fresh)
    }

    private mutating func nextCodename() -> String {
        let name = PreviewBlindService.codenames.first { !usedCodenames.contains($0) } ?? "Drift \(nextChatNumber)"
        usedCodenames.insert(name)
        return name
    }

    func summaries() throws(BlindError) -> [BlindChatSummary] {
        try requireMember()
        return conversations
            .sorted { $0.lastActivity > $1.lastActivity }
            .map { chat in
                BlindChatSummary(
                    id: chat.id,
                    codename: chat.codename,
                    status: chat.theyLeft ? .left : chat.status,
                    lastMessage: chat.messages.last.map { BlindLastMessage(mine: $0.mine, text: $0.text, at: $0.at) },
                    unread: chat.unread,
                )
            }
    }

    func detail(_ index: Int) -> BlindChatDetail {
        let chat = conversations[index]
        let revealed = chat.status == .revealed
        let person = people[chat.person]
        return BlindChatDetail(
            id: chat.id,
            codename: chat.codename,
            status: chat.status,
            iTappedReveal: chat.iTapped,
            theyLeft: chat.theyLeft,
            // B1: who they are exists only once both tapped.
            partner: revealed
                ? BlindPartner(name: person.name, photos: [Self.photo(seed: person.photoSeed), Self.photo(seed: person.photoSeed + 100)])
                : nil,
            guessCorrect: revealed ? chat.guess.map { $0 == person.card } : nil,
        )
    }

    mutating func send(_ id: BlindChatID, text: String, confirm: Bool) throws(BlindError) -> BlindSendResult {
        let index = try chatIndex(id)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= BlindRulesConstants.messageMaxLength else { throw .invalid }
        guard !conversations[index].theyLeft else { throw .chatClosed }
        if !confirm, let reason = PreviewBlindService.giveAwayReason(trimmed) {
            return BlindSendResult(message: nil, warning: reason)
        }
        nextMessageID += 1
        let sent = BlindMessage(id: nextMessageID, mine: true, text: trimmed, at: Date())
        conversations[index].messages.append(sent)
        if autoReply {
            nextMessageID += 1
            conversations[index].messages.append(
                BlindMessage(
                    id: nextMessageID,
                    mine: false,
                    text: String(localized: "Ha. Tell me more."),
                    at: Date().addingTimeInterval(1),
                ),
            )
        }
        return BlindSendResult(message: sent)
    }

    mutating func reveal(_ id: BlindChatID) throws(BlindError) -> BlindChatStatus {
        let index = try chatIndex(id)
        guard !conversations[index].theyLeft else { return .left }
        conversations[index].iTapped = true
        // B5: a one-sided tap stays open, and nothing tells the other side.
        if conversations[index].theyTapped {
            conversations[index].status = .revealed
        }
        return conversations[index].status
    }

    mutating func guess(_ id: BlindChatID, card cardID: BlindCardID) throws(BlindError) {
        let index = try chatIndex(id)
        guard conversations[index].status == .open else { throw .invalid }
        guard people.contains(where: { $0.card == cardID && $0.swiped?.isRight == true }) else { throw .notFound }
        conversations[index].guess = cardID
    }
}

// MARK: - Counters

extension BlindWorld {
    var rightCount: Int {
        people.count(where: { $0.swiped?.isRight == true })
    }

    var rightRemaining: Int {
        max(0, BlindRulesConstants.dailyRightLimit - rightToday)
    }

    var canDrop: Bool {
        rightCount >= BlindRulesConstants.dropMinimumRightSwipes
    }

    var me: BlindMe {
        BlindMe(isMember: isMember, rightRemaining: rightRemaining, rightCount: rightCount, canDrop: canDrop)
    }

    func requireMember() throws(BlindError) {
        guard isMember else { throw .notFound }
    }

    func chatIndex(_ id: BlindChatID) throws(BlindError) -> Int {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { throw .notFound }
        return index
    }

    private func card(_ index: Int) -> BlindCard {
        BlindCard(id: people[index].card, photo: Self.photo(seed: people[index].photoSeed))
    }
}
