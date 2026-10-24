import AppCore
import Foundation

// Owner: C4. A chat that never touches the network, for previews, snapshots and tests. Made-up
// messages between made-up people.

/// Answers from memory. Sending appends to the thread unless a failure is queued.
final class PreviewChatAPI: ChatAPI, @unchecked Sendable {
    // @unchecked: every property is only touched under `lock`.
    private let lock = NSLock()
    private var thread: [ChatMessage]
    private let firstName: String?
    private let pageSize: Int
    private var failures: [ChatError] = []
    private var pageFailure: ChatError?
    private var clock: Date
    private var sends: [(body: String, clientID: String)] = []
    private var pages: [Date?] = []
    private var unmatches = 0
    private var sendDelay: Duration = .zero

    init(
        thread: [ChatMessage] = PreviewChatAPI.sampleThread,
        firstName: String? = "Sam",
        pageSize: Int = 50,
        clock: Date = PreviewChatAPI.sampleNow,
    ) {
        self.thread = thread
        self.firstName = firstName
        self.pageSize = pageSize
        self.clock = clock
    }

    /// The next sends fail like this, in order.
    func failNextSends(_ errors: ChatError...) {
        lock.withLock { failures.append(contentsOf: errors) }
    }

    /// Sends wait this long before the server answers, to see them on their way.
    func delaySends(by delay: Duration) {
        lock.withLock { sendDelay = delay }
    }

    /// Every page load fails like this until set back to nil.
    func failPages(_ error: ChatError?) {
        lock.withLock { pageFailure = error }
    }

    /// The other person sends a message (or the server's review removes one).
    func receive(_ body: String, at date: Date? = nil) {
        lock.withLock {
            clock = date ?? clock.addingTimeInterval(30)
            thread.append(ChatMessage(
                id: UUID().uuidString.lowercased(),
                clientID: nil,
                body: body,
                createdAt: clock,
                fromMe: false,
                delivery: .sent,
            ))
        }
    }

    func remove(_ id: ChatMessage.ID) {
        lock.withLock { thread.removeAll { $0.id == id } }
    }

    var messageCount: Int {
        lock.withLock { thread.count }
    }

    /// Bodies the server accepted, in order.
    var sentBodies: [String] {
        lock.withLock { sends.map(\.body) }
    }

    /// Client IDs of every accepted send, retries included.
    var sentClientIDs: [String] {
        lock.withLock { sends.map(\.clientID) }
    }

    /// The `before` of every page request, nil for the newest page.
    var pageRequests: [Date?] {
        lock.withLock { pages }
    }

    var unmatchCount: Int {
        lock.withLock { unmatches }
    }

    func page(_: MatchID, before: Date?) async throws(ChatError) -> ChatPage {
        let result: Result<ChatPage, ChatError> = lock.withLock {
            pages.append(before)
            if let pageFailure {
                return .failure(pageFailure)
            }
            let older = thread.filter { before == nil || $0.createdAt < before! }
            let page = Array(older.suffix(pageSize))
            let hasMore = older.count > page.count
            return .success(ChatPage(messages: page, hasMore: hasMore, nextBefore: hasMore ? page.first?.createdAt : nil))
        }
        return try result.get()
    }

    func send(_: MatchID, body: String, clientID: String) async throws(ChatError) -> ChatMessage {
        let delay = lock.withLock { sendDelay }
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        let result: Result<ChatMessage, ChatError> = lock.withLock {
            if !failures.isEmpty {
                return .failure(failures.removeFirst())
            }
            sends.append((body, clientID))
            if let first = thread.first(where: { $0.clientID == clientID }) {
                return .success(first)
            }
            clock = clock.addingTimeInterval(5)
            let message = ChatMessage(
                id: UUID().uuidString.lowercased(),
                clientID: clientID,
                body: body,
                createdAt: clock,
                fromMe: true,
                delivery: .sent,
            )
            thread.append(message)
            return .success(message)
        }
        return try result.get()
    }

    func unmatch(_: MatchID) async throws(ChatError) {
        let failure: ChatError? = lock.withLock {
            unmatches += 1
            if !failures.isEmpty {
                return failures.removeFirst()
            }
            thread = []
            return nil
        }
        if let failure {
            throw failure
        }
    }

    func header(_: MatchID) async -> ChatHeader? {
        lock.withLock { firstName.map(ChatHeader.init(firstName:)) }
    }
}

extension PreviewChatAPI {
    /// 2026-10-24 at 8:30 PM UTC, the evening of the demo.
    static let sampleNow = Date(timeIntervalSince1970: 1_792_873_800)

    static let sampleMatch = MatchID(rawValue: "64bfd966-bf7f-426a-b7aa-f0dc371bae1a")

    static func sample(_ index: Int, _ body: String, fromMe: Bool, minutesAgo: Double) -> ChatMessage {
        ChatMessage(
            id: "00000000-0000-4000-8000-\(String(format: "%012d", index))",
            clientID: fromMe ? "00000000-0000-4000-9000-\(String(format: "%012d", index))" : nil,
            body: body,
            createdAt: sampleNow.addingTimeInterval(-minutesAgo * 60),
            fromMe: fromMe,
            delivery: .sent,
        )
    }

    /// A short, made-up conversation.
    static let sampleThread: [ChatMessage] = [
        sample(1, "Hi! I think we were both at the water station earlier.", fromMe: false, minutesAgo: 42),
        sample(2, "Ha, yes. The green jacket?", fromMe: true, minutesAgo: 41),
        sample(3, "That's me. Are you staying for the last set?", fromMe: false, minutesAgo: 40),
        sample(4, "Planning to. Want to meet by the stage after?", fromMe: true, minutesAgo: 12),
        sample(5, "Sounds good. See you there.", fromMe: false, minutesAgo: 11),
    ]
}
