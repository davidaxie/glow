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
