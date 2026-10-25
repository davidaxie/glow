import AppCore
import Foundation
import Observation

/// One bubble. Server rows come from the messages call; pending rows are what I just typed, shown
/// at once (optimistic send) until the server confirms or the send fails.
struct BlindChatRow: Identifiable, Equatable {
    enum State: Equatable {
        case sent, sending, failed
    }

    let id: String
    var serverID: Int?
    let mine: Bool
    let text: String
    let at: Date
    var state: State
    /// I already saw the give-away warning for this text and chose Send anyway.
    var confirmed = false

    init(message: BlindMessage) {
        id = "m\(message.id)"
        serverID = message.id
        mine = message.mine
        text = message.text
        at = message.at
        state = .sent
    }

    init(pendingText text: String, confirmed: Bool) {
        id = "local-\(UUID().uuidString)"
        serverID = nil
        mine = true
        self.text = text
        at = Date()
        state = .sending
        self.confirmed = confirmed
    }
}

/// A message the give-away check held back. Nothing was sent.
struct BlindPendingWarning: Identifiable, Equatable {
    let id = UUID()
    let reason: String
    let text: String
}

/// Chats whose reveal screen this run has already opened, so reopening the chat shows the
/// conversation instead of bouncing to the reveal again.
@MainActor
final class BlindRevealAnnouncements {
    static let shared = BlindRevealAnnouncements()
    private var ids: Set<BlindChatID> = []

    /// True the first time it's asked about a chat.
    func claim(_ id: BlindChatID) -> Bool {
        ids.insert(id).inserted
    }
}

/// State and logic of the blind chat, ported from Double Blind's ChatViewModel. Message text lives
/// only in memory and is never logged (B12). It only ever holds what the API returns: codename,
/// mine or theirs, text and times. No ids of people.
@MainActor
@Observable
final class BlindChatModel {
    enum Connection: Equatable {
        case live, offline
    }

    private(set) var detail: BlindChatDetail?
    private(set) var confirmed: [BlindChatRow] = []
    private(set) var pending: [BlindChatRow] = []
    var draft = ""
    private(set) var warning: BlindPendingWarning?
    private(set) var connection: Connection = .live
    private(set) var errorText: String?
    /// Messages from them that arrived while I was scrolled up.
    private(set) var newBelow = 0
    var atBottom = true
    private(set) var loaded = false
    /// Bumped on every message from them, for a soft haptic.
    private(set) var arrivals = 0

    /// Called once when the chat flips to revealed (the view opens the reveal screen).
    @ObservationIgnored var onRevealed: (() -> Void)?
    /// Called when the server says this chat is no longer mine (404).
    @ObservationIgnored var onGone: (() -> Void)?

    let chatID: BlindChatID
    @ObservationIgnored private let service: any BlindService
    @ObservationIgnored private let analytics: any Analytics
    @ObservationIgnored private let announcements: BlindRevealAnnouncements
    @ObservationIgnored private var cursor = 0
    @ObservationIgnored private var pollCount = 0
    @ObservationIgnored private var lastActivity = Date()
    @ObservationIgnored private var announcedReveal = false
    @ObservationIgnored private var rateLimitedUntil: Date?

    static let activeInterval: Duration = .milliseconds(1500)
    static let idleInterval: Duration = .seconds(3)
    static let idleAfter: TimeInterval = 30
    static let rateLimitedInterval: Duration = .seconds(6)
    /// The chat detail every this many message polls.
    static let detailEvery = 4

    init(
        chatID: BlindChatID,
        service: any BlindService,
        analytics: any Analytics = NoopAnalytics(),
        announcements: BlindRevealAnnouncements = .shared,
    ) {
        self.chatID = chatID
        self.service = service
        self.analytics = analytics
        self.announcements = announcements
    }

    // MARK: Derived

    var rows: [BlindChatRow] {
        confirmed + pending
    }

    var theyLeft: Bool {
        detail?.theyLeft == true || detail?.status == .left
    }

    var isRevealed: Bool {
        detail?.status == .revealed
    }

    var canSend: Bool {
        !theyLeft && BlindChatRules.canSend(draft)
    }

    var codename: String {
        detail?.codename ?? String(localized: "Chat")
    }

    /// Their name once BOTH revealed (the server sends `partner` only then, B1), else the codename.
    var title: String {
        if isRevealed, let name = detail?.partner?.name, !name.isEmpty {
            return name
        }
        return codename
    }

    func nextInterval(now: Date = Date()) -> Duration {
        if let until = rateLimitedUntil, until > now {
            return Self.rateLimitedInterval
        }
        return now.timeIntervalSince(lastActivity) > Self.idleAfter ? Self.idleInterval : Self.activeInterval
    }

    // MARK: Loading and polling

    func load() async {
        await refreshDetail()
        await pollOnce()
        loaded = true
    }

    /// Runs until cancelled. The view runs it only while the app is in the foreground.
    func run() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: nextInterval())
            if Task.isCancelled {
                break
            }
            await pollOnce()
        }
    }

    func pollOnce() async {
        do {
            let new = try await service.messages(chatID, after: cursor)
            connection = .live
            merge(new)
            pollCount += 1
            if pollCount.isMultiple(of: Self.detailEvery) {
                await refreshDetail()
            }
        } catch {
            handle(error, quietly: true)
        }
    }

    func refreshDetail() async {
        do {
            let fresh = try await service.chat(chatID)
            connection = .live
            detail = fresh
            if fresh.status == .revealed, !announcedReveal {
                announcedReveal = true
                if announcements.claim(chatID) {
                    onRevealed?()
                }
            }
        } catch {
            handle(error, quietly: true)
        }
    }

    private func merge(_ messages: [BlindMessage]) {
        var incoming = 0
        for message in messages {
            cursor = max(cursor, message.id)
            guard !confirmed.contains(where: { $0.serverID == message.id }) else { continue }
            if message.mine {
                // The server stored one of mine before the send call answered: drop its placeholder.
                if let index = pending.firstIndex(where: { $0.text == message.text && $0.state != .sent }) {
                    pending.remove(at: index)
                }
            } else {
                incoming += 1
            }
            confirmed.append(BlindChatRow(message: message))
        }
        confirmed.sort { ($0.serverID ?? 0) < ($1.serverID ?? 0) }
        if incoming > 0 {
            lastActivity = Date()
            if !atBottom {
                newBelow += incoming
            } else if loaded {
                arrivals += 1
            }
        }
    }

    func scrolledToBottom() {
        newBelow = 0
    }

    // MARK: Sending

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !text.isEmpty else { return }
        draft = ""
        await deliver(text: text, confirm: false)
    }

    private func deliver(text: String, confirm: Bool, reusing rowID: String? = nil) async {
        lastActivity = Date()
        errorText = nil
        let id: String
        if let rowID, let index = pending.firstIndex(where: { $0.id == rowID }) {
            pending[index].state = .sending
            id = rowID
        } else {
            let row = BlindChatRow(pendingText: text, confirmed: confirm)
            pending.append(row)
            id = row.id
        }
        do {
            let result = try await service.send(chatID, text: text, confirm: confirm)
            if let reason = result.warning {
                // Held back, nothing was sent: take the bubble back and ask.
                pending.removeAll { $0.id == id }
                warning = BlindPendingWarning(reason: reason, text: text)
                return
            }
            pending.removeAll { $0.id == id }
            if let message = result.message, !confirmed.contains(where: { $0.serverID == message.id }) {
                confirmed.append(BlindChatRow(message: message))
                confirmed.sort { ($0.serverID ?? 0) < ($1.serverID ?? 0) }
            }
            analytics.track(AnalyticsEvent("blind_message_sent", ["confirmed": .bool(confirm)]))
        } catch .chatClosed {
            pending.removeAll { $0.id == id }
            draft = text
            errorText = BlindError.chatClosed.message
            await refreshDetail()
        } catch .notFound {
            pending.removeAll { $0.id == id }
            onGone?()
        } catch {
            if let index = pending.firstIndex(where: { $0.id == id }) {
                pending[index].state = .failed
            }
            handle(error, quietly: false)
        }
    }

    func retry(_ rowID: String) async {
        guard let row = pending.first(where: { $0.id == rowID }), row.state == .failed else { return }
        await deliver(text: row.text, confirm: row.confirmed, reusing: rowID)
    }

    func discard(_ rowID: String) {
        pending.removeAll { $0.id == rowID }
    }

    // MARK: The give-away warning

    /// "Send anyway". Clears the warning at once, so the sheet's own dismissal finds nothing to
    /// restore. Returns the sending task so tests can await it.
    @discardableResult
    func confirmWarning() -> Task<Void, Never>? {
        guard let held = warning else { return nil }
        warning = nil
        return Task { await deliver(text: held.text, confirm: true) }
    }

    /// "Edit": the text goes back into the composer, nothing was sent.
    func editWarning() {
        guard let held = warning else { return }
        warning = nil
        draft = held.text
    }

    func clearError() {
        errorText = nil
    }

    // MARK: Errors

    private func handle(_ error: BlindError, quietly: Bool) {
        switch error {
        case .notFound:
            onGone?()
        case .rateLimited:
            rateLimitedUntil = Date().addingTimeInterval(6)
        case .offline:
            connection = .offline
            if !quietly {
                errorText = error.message
            }
        default:
            if !quietly {
                errorText = error.message
            }
        }
    }
}
