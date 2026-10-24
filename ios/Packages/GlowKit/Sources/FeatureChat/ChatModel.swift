import APIClient
import AppCore
import Foundation
import Observation

// Owner: C4. The thread's state: what's on screen, what's on its way, and what failed.
//
// The server is the truth. Each refresh of the newest page replaces everything it covers, so a
// message B8's review flagged after the fact disappears, and a thread that ended (unmatch, block,
// a deleted account) is cleared at once. Messages the person is sending stay at the bottom until
// the server has them, matched up by client ID, so a resend never shows twice.

@MainActor
@Observable
final class ChatModel {
    enum Phase: Hashable, Sendable {
        case loading
        case ready
        /// Still choosing (409 `chat_not_open`).
        case notOpen
        /// Unmatched, blocked or gone. The thread is cleared and nothing can be sent.
        case ended
        /// The first load didn't work.
        case failed
    }

    /// Something worth a short toast.
    enum Notice: Hashable, Sendable {
        case unmatchFailed
    }

    let matchID: MatchID
    private(set) var phase: Phase = .loading
    private(set) var header: ChatHeader?
    /// Messages the server has, oldest to newest.
    private(set) var messages: [ChatMessage] = []
    /// My messages on their way or failed, in the order I wrote them.
    private(set) var outgoing: [ChatMessage] = []
    private(set) var hasOlder = false
    private(set) var isLoadingOlder = false
    private(set) var isUnmatching = false
    var notice: Notice?
    var draft = ""

    private let api: any ChatAPI
    private let analytics: any Analytics
    private let now: @Sendable () -> Date
    let calendar: Calendar
    private var olderCursor: Date?
    private var isRefreshing = false
    private var refreshAgain = false

    init(
        matchID: MatchID,
        api: any ChatAPI,
        analytics: any Analytics = NoopAnalytics(),
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent,
    ) {
        self.matchID = matchID
        self.api = api
        self.analytics = analytics
        self.now = now
        self.calendar = calendar
    }

    /// A model already showing a state, without loading anything: for previews and snapshots,
    /// which render synchronously.
    static func showing(
        _ phase: Phase,
        messages: [ChatMessage] = [],
        outgoing: [ChatMessage] = [],
        header: ChatHeader? = nil,
        draft: String = "",
        api: any ChatAPI = PreviewChatAPI(),
        now: @escaping @Sendable () -> Date = { PreviewChatAPI.sampleNow },
        calendar: Calendar = .autoupdatingCurrent,
    ) -> ChatModel {
        let model = ChatModel(matchID: PreviewChatAPI.sampleMatch, api: api, now: now, calendar: calendar)
        model.phase = phase
        model.messages = messages
        model.outgoing = outgoing
        model.header = header
        model.draft = draft
        return model
    }

    /// Everything the thread shows, oldest first.
    var items: [ChatMessage] {
        messages + outgoing
    }

    /// The thread as laid out on screen.
    var rows: [ChatRow] {
        ChatLayout.rows(for: items, now: now(), calendar: calendar)
    }

    // MARK: Composer

    /// The longest message the server takes. It counts UTF-16 code units (JavaScript string
    /// length), so an emoji can count as two.
    static let maxLength = GlowConstants.messageMaxChars

    /// What would be sent: the draft without leading and trailing spaces and blank lines.
    var outgoingBody: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Characters left, counted the way the server counts them.
    var remaining: Int {
        Self.maxLength - outgoingBody.utf16.count
    }

    var canSend: Bool {
        phase == .ready && !outgoingBody.isEmpty && remaining >= 0
    }

    // MARK: Loading

    /// The first load: the newest page and the header.
    func start() async {
        async let header = api.header(matchID)
        await refresh()
        if let header = await header {
            self.header = header
        }
        if phase == .ready {
            analytics.track(AnalyticsEvent("chat_opened", ["messages": .int(min(messages.count, 50))]))
        }
    }

    /// Fetches the newest page again. Calls that arrive while one is running are folded into one
    /// more fetch, so a burst of events costs at most two requests.
    func refresh() async {
        if isRefreshing {
            refreshAgain = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshAgain = false
            do {
                let page = try await api.page(matchID, before: nil)
                applyNewest(page)
            } catch {
                handleLoadError(error)
            }
        } while refreshAgain && phase != .ended
    }

    /// The page before the oldest message on screen.
    func loadOlder() async {
        guard hasOlder, !isLoadingOlder, let cursor = olderCursor, phase == .ready else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let page = try await api.page(matchID, before: cursor)
            let known = Set(messages.map(\.id))
            messages = page.messages.filter { !known.contains($0.id) } + messages
            olderCursor = page.nextBefore
            hasOlder = page.hasMore && page.nextBefore != nil
        } catch {
            handleLoadError(error)
        }
    }

    /// Refreshes on every event about this match, whatever it is: a new message, or the match
    /// ending (the refresh then answers 404 and the thread closes). Runs until cancelled.
    func listen(to events: AsyncStream<RealtimeEvent>) async {
        for await event in events where event.matchID == matchID {
            guard phase != .ended else { return }
            await refresh()
        }
    }

    private func applyNewest(_ page: ChatPage) {
        let landed = Set(page.messages.compactMap(\.clientID))
        // Mine that the server already has, including any whose answer was lost on the way.
        outgoing.removeAll { $0.clientID.map(landed.contains) ?? false }

        let pageIDs = Set(page.messages.map(\.id))
        if !page.hasMore {
            // The page is the whole thread.
            messages = page.messages
            hasOlder = false
            olderCursor = nil
        } else if let oldest = page.messages.first?.createdAt {
            // Keep older pages loaded earlier; the newest page replaces everything it covers.
            let older = messages.filter { $0.createdAt < oldest && !pageIDs.contains($0.id) }
            if older.isEmpty {
                olderCursor = page.nextBefore
                hasOlder = page.nextBefore != nil
            }
            messages = older + page.messages
        }
        phase = .ready
    }

    private func handleLoadError(_ error: ChatError) {
        switch error {
        case .ended: end()
        case .notOpen: phase = .notOpen
        case .cancelled: break
        default:
            // Keep what's on screen; only a first load that never worked shows the error.
            if phase == .loading {
                phase = .failed
            }
        }
    }

    private func end() {
        phase = .ended
        messages = []
        outgoing = []
        hasOlder = false
        olderCursor = nil
        draft = ""
    }

    // MARK: Sending

    /// Sends the draft. It shows at once as sending, then as sent or failed.
    func send() async {
        guard canSend else { return }
        let body = outgoingBody
        draft = ""
        let clientID = UUID().uuidString.lowercased()
        let message = ChatMessage(
            id: clientID,
            clientID: clientID,
            body: body,
            createdAt: now(),
            fromMe: true,
            delivery: .sending,
        )
        outgoing.append(message)
        await deliver(message, isRetry: false)
    }

    /// Sends a failed message again, with the same client ID, so it can never arrive twice.
    func retry(_ id: ChatMessage.ID) async {
        guard phase == .ready, let index = outgoing.firstIndex(where: { $0.id == id }),
              case let .failed(reason) = outgoing[index].delivery, reason != .rejected
        else { return }
        outgoing[index].delivery = .sending
        await deliver(outgoing[index], isRetry: true)
    }

    /// Forgets a failed message.
    func discard(_ id: ChatMessage.ID) {
        outgoing.removeAll { $0.id == id && $0.delivery != .sending }
    }

    /// Puts a failed message back in the composer to rewrite it.
    func edit(_ id: ChatMessage.ID) {
        guard let message = outgoing.first(where: { $0.id == id && $0.delivery != .sending }) else { return }
        discard(id)
        draft = message.body
    }

    private func deliver(_ message: ChatMessage, isRetry: Bool) async {
        guard let clientID = message.clientID else { return }
        do {
            let sent = try await api.send(matchID, body: message.body, clientID: clientID)
            outgoing.removeAll { $0.id == message.id }
            insert(sent)
            analytics.track(AnalyticsEvent("chat_message_sent", ["retry": .bool(isRetry)]))
        } catch {
            switch error {
            case .ended:
                end()
            case .notOpen:
                phase = .notOpen
            default:
                let reason = error.sendFailure
                if let index = outgoing.firstIndex(where: { $0.id == message.id }) {
                    outgoing[index].delivery = .failed(reason)
                }
                analytics.track(AnalyticsEvent("chat_message_failed", ["reason": reason.analyticsValue]))
            }
        }
    }

    private func insert(_ message: ChatMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
            return
        }
        let at = messages.lastIndex(where: { $0.createdAt <= message.createdAt }).map { $0 + 1 } ?? 0
        messages.insert(message, at: at)
    }

    // MARK: Unmatch

    /// Ends the match for both people. True once it's over (also if it already was).
    func unmatch() async -> Bool {
        guard !isUnmatching else { return false }
        isUnmatching = true
        defer { isUnmatching = false }
        do {
            try await api.unmatch(matchID)
        } catch {
            guard error == .ended else {
                notice = .unmatchFailed
                return false
            }
        }
        end()
        analytics.track(AnalyticsEvent("chat_unmatched"))
        return true
    }
}

extension SendFailure {
    fileprivate var analyticsValue: AnalyticsValue {
        switch self {
        case .rejected: "rejected"
        case .rateLimited: "rate_limited"
        case .network: "network"
        }
    }
}
