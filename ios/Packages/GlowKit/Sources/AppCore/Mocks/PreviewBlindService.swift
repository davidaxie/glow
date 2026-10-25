import Foundation
import UIKit

// Owner: X2 (Blind mode). This file and Services/BlindService.swift change together.

/// An in-memory Blind world for previews, tests and Debug Simulator runs (`-GlowDebugBlind`). One
/// actor holds everything, so a swipe changes the counters, a drop opens waiting matches and a
/// reveal tap flips the chat. It follows the real rules (Double Blind's B1 to B5):
///
/// - 20 right swipes a UTC day (`.rightCapReached` after that); passes are always allowed.
/// - A drop opens only from 5 lifetime right swipes, at most 5 chats at a time, and only when ready.
/// - Chats exist only for mutual right swipes, and only after a drop opened them.
/// - A one-sided reveal tap leaves the chat `open` (the tapper sees "Waiting"); the partner, with
///   name and photos, appears only once both tapped.
/// - Every photo is generated here: no real person, no network.
public actor PreviewBlindService: BlindService {
    public enum Scenario: String, Sendable, CaseIterable {
        /// Not a member yet: the opt-in screen.
        case newcomer
        /// A member with 3 right swipes, 2 of them mutual and waiting for the drop.
        case swiping
        /// 6 right swipes and 3 waiting matches: the drop is ready to open.
        case dropReady
        /// The drop already opened: Fox (they tapped Reveal already), Comet and Otter.
        case chatting
        /// Fox is revealed.
        case revealed
        /// All 20 right swipes used today.
        case capReached
    }

    public struct Options: Sendable {
        public var scenario: Scenario
        /// The server is in demo mode (drops open any time). False means before tonight's drop.
        public var dropReady: Bool
        /// They answer every message, so a chat feels alive in a demo.
        public var autoReply: Bool
        /// A delay on every call, to see loading states.
        public var latency: Duration

        public init(scenario: Scenario = .swiping, dropReady: Bool = true, autoReply: Bool = true, latency: Duration = .zero) {
            self.scenario = scenario
            self.dropReady = dropReady
            self.autoReply = autoReply
            self.latency = latency
        }
    }

    public static let codenames = ["Fox", "Comet", "Otter", "Ember", "Heron", "Juniper", "Willow", "Drift", "Lark", "Moss"]

    /// Fox's chat in `.chatting` and `.revealed`, for `-GlowDebugRoute blindChat/<id>`.
    public static let foxChatID = BlindWorld.chatID(1)
    /// Comet's chat (a one-sided reveal shows only "Waiting").
    public static let cometChatID = BlindWorld.chatID(2)
    public static let otterChatID = BlindWorld.chatID(3)

    private var world: BlindWorld
    private let latency: Duration

    public init(_ options: Options = Options()) {
        world = BlindWorld(options)
        latency = options.latency
    }

    public init(scenario: Scenario) {
        self.init(Options(scenario: scenario))
    }

    private func pause() async {
        if latency > .zero {
            try? await Task.sleep(for: latency)
        }
    }

    // MARK: BlindService

    public func me() async throws(BlindError) -> BlindMe {
        await pause()
        return world.me
    }

    public func join() async throws(BlindError) -> BlindMe {
        await pause()
        world.isMember = true
        return world.me
    }

    public func leaveBlind() async throws(BlindError) {
        await pause()
        world.leave()
    }

    public func deck(limit: Int) async throws(BlindError) -> [BlindCard] {
        await pause()
        return try world.deck(limit: limit)
    }

    public func swipe(_ card: BlindCardID, kind: BlindSwipeKind) async throws(BlindError) -> BlindSwipeResult {
        await pause()
        return try world.swipe(card, kind: kind)
    }

    public func pool() async throws(BlindError) -> BlindPool {
        await pause()
        try world.requireMember()
        return BlindPool(rightCount: world.rightCount, rightRemaining: world.rightRemaining, canDrop: world.canDrop)
    }

    public func poolCards() async throws(BlindError) -> [BlindCard] {
        await pause()
        return try world.poolCards()
    }

    public func dropStatus() async throws(BlindError) -> BlindDropStatus {
        await pause()
        try world.requireMember()
        return BlindDropStatus(
            ready: world.dropReady,
            demo: world.dropReady,
            nextDropAt: Self.nextDrop(after: Date()),
            rightCount: world.rightCount,
            canDrop: world.canDrop,
        )
    }

    public func openDrop() async throws(BlindError) -> BlindDropResult {
        await pause()
        return try world.openDrop()
    }

    public func chats() async throws(BlindError) -> [BlindChatSummary] {
        await pause()
        return try world.summaries()
    }

    public func chat(_ id: BlindChatID) async throws(BlindError) -> BlindChatDetail {
        await pause()
        return try world.detail(world.chatIndex(id))
    }

    public func messages(_ id: BlindChatID, after: Int?) async throws(BlindError) -> [BlindMessage] {
        await pause()
        let index = try world.chatIndex(id)
        world.conversations[index].unread = false
        return world.conversations[index].messages.filter { $0.id > (after ?? 0) }
    }

    public func send(_ id: BlindChatID, text: String, confirm: Bool) async throws(BlindError) -> BlindSendResult {
        await pause()
        return try world.send(id, text: text, confirm: confirm)
    }

    public func reveal(_ id: BlindChatID) async throws(BlindError) -> BlindChatStatus {
        await pause()
        return try world.reveal(id)
    }

    public func leaveChat(_ id: BlindChatID) async throws(BlindError) {
        await pause()
        let index = try world.chatIndex(id)
        // A revealed chat can't be left, only blocked.
        guard world.conversations[index].status != .revealed else { throw .invalid }
        world.conversations.remove(at: index)
    }

    public func guess(_ id: BlindChatID, card: BlindCardID) async throws(BlindError) {
        await pause()
        try world.guess(id, card: card)
    }

    public func block(_ id: BlindChatID) async throws(BlindError) {
        await pause()
        let index = try world.chatIndex(id)
        // Glow's blocks: gone for both, in both modes. I never learn who it was.
        world.people[world.conversations[index].person].blocked = true
        world.conversations.remove(at: index)
    }

    public func report(_ id: BlindChatID, reason: String) async throws(BlindError) {
        await pause()
        _ = try world.chatIndex(id)
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= BlindRulesConstants.reportMaxLength else { throw .invalid }
    }

    public func photo(_ photo: BlindPhoto) async throws(BlindError) -> PrivateImage {
        await pause()
        guard photo.url.hasPrefix("mock://blind/"), let seed = Int(photo.url.dropFirst("mock://blind/".count)) else {
            throw .notFound
        }
        return PrivateImage(image: Self.portrait(seed: seed))
    }

    // MARK: The other person, for tests and demos

    /// They tap Reveal too. Reveals the chat if I already tapped.
    public func partnerTapsReveal(_ id: BlindChatID) throws(BlindError) {
        let index = try world.chatIndex(id)
        world.conversations[index].theyTapped = true
        if world.conversations[index].iTapped {
            world.conversations[index].status = .revealed
        }
    }

    public func partnerLeaves(_ id: BlindChatID) throws(BlindError) {
        let index = try world.chatIndex(id)
        world.conversations[index].theyLeft = true
        world.conversations[index].status = .left
    }

    public func partnerSends(_ id: BlindChatID, _ text: String) throws(BlindError) {
        let index = try world.chatIndex(id)
        world.nextMessageID += 1
        world.conversations[index].messages.append(BlindMessage(id: world.nextMessageID, mine: false, text: text, at: Date()))
        world.conversations[index].unread = true
    }

    /// A new UTC day: the right-swipe cap resets.
    public func startNewDay() {
        world.rightToday = 0
    }

    public func setDropReady(_ ready: Bool) {
        world.dropReady = ready
    }

    // MARK: Helpers

    /// The next 8pm on this phone's clock (the mock's stand-in for 8pm Pacific).
    public static func nextDrop(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: date, matching: DateComponents(hour: 20, minute: 0, second: 0), matchingPolicy: .nextTime)
            ?? date.addingTimeInterval(24 * 3600)
    }

    /// Close enough to the server's give-away check (regex first) to exercise the warning sheet.
    public static func giveAwayReason(_ text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("@") {
            return String(localized: "That looks like a handle or an email address.")
        }
        if ["instagram", "insta ", "snapchat", "my number", "text me", "linkedin"].contains(where: lower.contains) {
            return String(localized: "That might point to who you are.")
        }
        if text.count(where: \.isNumber) >= 7 {
            return String(localized: "That looks like a phone number.")
        }
        return nil
    }

    /// A made-up portrait: a soft gradient and an abstract head-and-shoulders shape. No real person.
    public static func portrait(seed: Int, size: CGSize = CGSize(width: 600, height: 800)) -> UIImage {
        let palettes: [(UInt32, UInt32)] = [
            (0x3B2F6B, 0xD98E73), (0x15546B, 0x9BD1C0), (0x5B2A4E, 0xF0B6A0), (0x1F3B5C, 0xA9B8FF),
            (0x4A3B2A, 0xE8C48A), (0x23483A, 0xC6E3A8), (0x52313A, 0xF2A7B8), (0x2C2F4A, 0xE6C6F2),
        ]
        let palette = palettes[abs(seed) % palettes.count]
        let variant = seed >= 100
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let colors = [rgb(palette.0).cgColor, rgb(palette.1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(
                    gradient,
                    start: variant ? CGPoint(x: size.width, y: 0) : .zero,
                    end: CGPoint(x: variant ? 0 : size.width, y: size.height),
                    options: [],
                )
            }
            // Soft light behind the figure.
            UIColor(white: 1, alpha: 0.10).setFill()
            cg.fillEllipse(in: CGRect(x: size.width * 0.05, y: size.height * 0.08, width: size.width * 0.6, height: size.width * 0.6))
            // Head and shoulders, in a darker tone of the palette.
            rgb(palette.0).withAlphaComponent(0.55).setFill()
            let headSize = size.width * (0.30 + CGFloat(abs(seed) % 3) * 0.02)
            let headX = (size.width - headSize) / 2 + CGFloat((abs(seed) % 5) - 2) * 6
            cg.fillEllipse(in: CGRect(x: headX, y: size.height * 0.30, width: headSize, height: headSize * 1.18))
            UIBezierPath(
                roundedRect: CGRect(x: size.width * 0.14, y: size.height * 0.64, width: size.width * 0.72, height: size.height * 0.5),
                cornerRadius: size.width * 0.3,
            ).fill()
        }
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1,
        )
    }
}

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

    // MARK: Counters

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
                BlindMessage(id: nextMessageID, mine: false, text: String(localized: "Ha. Tell me more."), at: Date().addingTimeInterval(1)),
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
