import APIClient
import AppCore
import Foundation

// Owner: C4. The four calls chat makes, behind a protocol so the model can be tested without a
// network. `LiveChatAPI` is the real one, over the generated client.

/// One message as the thread shows it. Messages never say who sent them, only whether it was me.
struct ChatMessage: Identifiable, Hashable, Sendable {
    /// The server's ID, or the client ID while it's still on its way.
    let id: String
    let clientID: String?
    let body: String
    let createdAt: Date
    let fromMe: Bool
    var delivery: Delivery

    enum Delivery: Hashable, Sendable {
        /// The server has it.
        case sent
        /// On its way.
        case sending
        /// Didn't go. The reason decides what the person can do about it.
        case failed(SendFailure)
    }

    var isOutgoing: Bool {
        delivery != .sent
    }
}

/// Why a message didn't send.
enum SendFailure: Hashable, Sendable {
    /// Moderation refused it (422 `message_rejected`). Sending it again won't help.
    case rejected
    /// Too many messages in a short time (429).
    case rateLimited
    /// The network dropped, or something went wrong on the server. Worth another try.
    case network
}

/// A page of the thread, oldest to newest.
struct ChatPage: Hashable, Sendable {
    let messages: [ChatMessage]
    let hasMore: Bool
    let nextBefore: Date?
}

/// What the thread's header shows: the other person's first name, once there's a match (P1).
///
/// It also carries the three things the icebreaker chips fill in (CHIPS-D1), all of which both
/// people already see: the room's name, and the glow's code word and meeting spot if they found
/// each other. Just chat has no glow, so those two are nil.
struct ChatHeader: Hashable, Sendable {
    let firstName: String
    let roomName: String?
    let codeWord: String?
    let meetingSpot: String?

    init(firstName: String, roomName: String? = nil, codeWord: String? = nil, meetingSpot: String? = nil) {
        self.firstName = firstName
        self.roomName = roomName
        self.codeWord = codeWord
        self.meetingSpot = meetingSpot
    }

    init(_ detail: Components.Schemas.MatchDetail) {
        self.init(
            firstName: detail.firstName,
            roomName: detail.roomName,
            codeWord: detail.glow?.codeWord,
            meetingSpot: detail.glow?.meetingSpot?.name,
        )
    }
}

/// How a chat call ended, when it didn't work.
enum ChatError: Error, Hashable, Sendable {
    /// 404: not my match, or it ended (unmatched, blocked, or an account was deleted). The server
    /// never says which (P11, D18).
    case ended
    /// 409 `chat_not_open`: still choosing.
    case notOpen
    /// 422 `message_rejected`.
    case rejected
    /// 400: the body broke the contract (blank or too long). The composer prevents both.
    case invalid
    case rateLimited
    case offline
    case unauthorized
    case cancelled
    case unexpected

    init(_ error: APIError) {
        switch error {
        case .notFound: self = .ended
        case .unauthorized: self = .unauthorized
        case .rateLimited: self = .rateLimited
        case .offline: self = .offline
        case .cancelled: self = .cancelled
        case .unexpected: self = .unexpected
        }
    }

    var sendFailure: SendFailure {
        switch self {
        case .rejected, .invalid: .rejected
        case .rateLimited: .rateLimited
        default: .network
        }
    }
}

protocol ChatAPI: Sendable {
    /// The newest page, or the page before `before`.
    func page(_ match: MatchID, before: Date?) async throws(ChatError) -> ChatPage
    /// Sends one message. A retry with the same client ID returns the first message, never a copy.
    func send(_ match: MatchID, body: String, clientID: String) async throws(ChatError) -> ChatMessage
    /// Ends the match for both people and deletes the thread.
    func unmatch(_ match: MatchID) async throws(ChatError)
    /// The other person's first name and what the chips fill in, or nil if it can't be loaded right now.
    func header(_ match: MatchID) async -> ChatHeader?
}

struct LiveChatAPI: ChatAPI {
    let api: GlowAPI

    func page(_ match: MatchID, before: Date?) async throws(ChatError) -> ChatPage {
        let output: Operations.ListMessages.Output
        do {
            output = try await api.perform {
                try await $0.listMessages(
                    path: .init(id: match.rawValue),
                    query: .init(before: before.map(Self.wireDate)),
                )
            }
        } catch {
            throw ChatError(error)
        }
        switch output {
        case let .ok(ok):
            guard case let .json(page) = ok.body else { throw .unexpected }
            return ChatPage(
                messages: page.messages.map(Self.message),
                hasMore: page.hasMore,
                nextBefore: page.nextBefore,
            )
        case .notFound: throw .ended
        case .conflict: throw .notOpen
        case .unauthorized: throw .unauthorized
        default: throw .unexpected
        }
    }

    func send(_ match: MatchID, body: String, clientID: String) async throws(ChatError) -> ChatMessage {
        let output: Operations.SendMessage.Output
        do {
            output = try await api.perform {
                try await $0.sendMessage(
                    path: .init(id: match.rawValue),
                    // The client ID makes a resend safe: the server answers with the first message.
                    body: .json(.init(body: body, clientId: clientID)),
                )
            }
        } catch {
            throw ChatError(error)
        }
        switch output {
        case let .created(created):
            guard case let .json(message) = created.body else { throw .unexpected }
            return Self.message(message)
        case .badRequest: throw .invalid
        case .notFound: throw .ended
        case .conflict: throw .notOpen
        case .unprocessableContent: throw .rejected
        case .tooManyRequests: throw .rateLimited
        case .unauthorized: throw .unauthorized
        default: throw .unexpected
        }
    }

    func unmatch(_ match: MatchID) async throws(ChatError) {
        let output: Operations.Unmatch.Output
        do {
            output = try await api.perform { try await $0.unmatch(path: .init(id: match.rawValue)) }
        } catch {
            throw ChatError(error)
        }
        switch output {
        case .noContent: return
        case .notFound: throw .ended
        case .unauthorized: throw .unauthorized
        default: throw .unexpected
        }
    }

    func header(_ match: MatchID) async -> ChatHeader? {
        guard let output = try? await api.perform({ try await $0.getMatch(path: .init(id: match.rawValue)) }),
              case let .ok(ok) = output,
              case let .json(detail) = ok.body
        else { return nil }
        return ChatHeader(detail)
    }

    static func message(_ message: Components.Schemas.Message) -> ChatMessage {
        ChatMessage(
            id: message.id,
            clientID: message.clientId,
            body: message.body,
            createdAt: message.createdAt,
            fromMe: message.fromMe,
            delivery: .sent,
        )
    }

    /// `nextBefore` goes back exactly as the server sent it, to the millisecond.
    ///
    /// A `Date` parsed from `…00.002Z` holds a binary fraction just under 2 ms, and the ISO 8601
    /// formatter truncates, so it would go back as `…00.001Z` and the next page would skip the
    /// messages of that millisecond. Half a millisecond on top lands inside the right one whether
    /// the formatter truncates or rounds.
    static func wireDate(_ date: Date) -> Date {
        let milliseconds = (date.timeIntervalSince1970 * 1000).rounded()
        return Date(timeIntervalSince1970: (milliseconds + 0.5) / 1000)
    }
}
