import APIClient
import AppCore
import Foundation
import HTTPTypes
import OpenAPIRuntime
import UIKit

// Owner: X2. Blind mode over the real API, `/api/blind/*`, with Double Blind's request and
// response shapes (ids are opaque per-viewer card ids). Every request goes through `GlowAPI`, so it
// carries the bearer token, only ever to the API's own host, and 401/404/429 arrive as `APIError`s.

struct LiveBlindService: BlindService {
    let api: GlowAPI

    // MARK: Membership

    func me() async throws(BlindError) -> BlindMe {
        let wire: Wire.Me = try await call(.get, "/api/blind/me", operationID: "blindGetMe")
        return wire.model
    }

    func join() async throws(BlindError) -> BlindMe {
        let wire: Wire.Me = try await call(.post, "/api/blind/join", operationID: "blindJoin")
        return wire.model
    }

    func leaveBlind() async throws(BlindError) {
        let _: Wire.Ok = try await call(.delete, "/api/blind/join", operationID: "blindLeave")
    }

    // MARK: Deck

    func deck(limit: Int) async throws(BlindError) -> [BlindCard] {
        let wire: Wire.Cards = try await call(.get, "/api/blind/deck?limit=\(limit)", operationID: "blindGetDeck")
        return wire.cards.compactMap(\.model)
    }

    func swipe(_ card: BlindCardID, kind: BlindSwipeKind) async throws(BlindError) -> BlindSwipeResult {
        let body = Wire.SwipeRequest(targetId: card.rawValue, kind: kind.rawValue)
        let wire: Wire.Counters = try await call(.post, "/api/blind/swipe", body: body, operationID: "blindSwipe")
        return BlindSwipeResult(rightRemaining: wire.rightRemaining, rightCount: wire.rightCount)
    }

    func pool() async throws(BlindError) -> BlindPool {
        let wire: Wire.Pool = try await call(.get, "/api/blind/pool", operationID: "blindGetPool")
        return BlindPool(rightCount: wire.rightCount, rightRemaining: wire.rightRemaining, canDrop: wire.canDrop)
    }

    func poolCards() async throws(BlindError) -> [BlindCard] {
        let wire: Wire.Cards = try await call(.get, "/api/blind/pool/cards", operationID: "blindGetPoolCards")
        return wire.cards.compactMap(\.model)
    }

    // MARK: Drop

    func dropStatus() async throws(BlindError) -> BlindDropStatus {
        let wire: Wire.DropStatus = try await call(.get, "/api/blind/drop", operationID: "blindGetDrop")
        return BlindDropStatus(
            ready: wire.ready,
            demo: wire.demo,
            nextDropAt: wire.nextDropAt,
            rightCount: wire.rightCount,
            canDrop: wire.canDrop,
        )
    }

    func openDrop() async throws(BlindError) -> BlindDropResult {
        let wire: Wire.DropResult = try await call(.post, "/api/blind/drop", operationID: "blindOpenDrop")
        let chats = (wire.chats ?? []).compactMap { chat in
            BlindChatID(validating: chat.id).map { BlindDropChat(id: $0, codename: chat.codename) }
        }
        return BlindDropResult(opened: wire.opened, chats: chats)
    }

    // MARK: Chats

    func chats() async throws(BlindError) -> [BlindChatSummary] {
        let wire: Wire.ChatList = try await call(.get, "/api/blind/chats", operationID: "blindListChats")
        return wire.chats.compactMap(\.model)
    }

    func chat(_ id: BlindChatID) async throws(BlindError) -> BlindChatDetail {
        let wire: Wire.ChatDetail = try await call(.get, "/api/blind/chats/\(id.rawValue)", operationID: "blindGetChat")
        guard let model = wire.model else { throw .unexpected }
        return model
    }

    func messages(_ id: BlindChatID, after: Int?) async throws(BlindError) -> [BlindMessage] {
        let query = after.map { "?after=\($0)" } ?? ""
        let wire: Wire.Messages = try await call(
            .get, "/api/blind/chats/\(id.rawValue)/messages\(query)", operationID: "blindListMessages",
        )
        return wire.messages.map(\.model)
    }

    func send(_ id: BlindChatID, text: String, confirm: Bool) async throws(BlindError) -> BlindSendResult {
        let body = Wire.SendRequest(text: text, confirm: confirm)
        let wire: Wire.SendResult = try await call(
            .post, "/api/blind/chats/\(id.rawValue)/messages", body: body, operationID: "blindSendMessage",
        )
        return BlindSendResult(message: wire.message?.model, warning: wire.warning?.reason)
    }

    func reveal(_ id: BlindChatID) async throws(BlindError) -> BlindChatStatus {
        let wire: Wire.Status = try await call(.post, "/api/blind/chats/\(id.rawValue)/reveal", operationID: "blindReveal")
        return BlindChatStatus(rawValue: wire.status) ?? .open
    }

    func leaveChat(_ id: BlindChatID) async throws(BlindError) {
        let _: Wire.Ok = try await call(.post, "/api/blind/chats/\(id.rawValue)/leave", operationID: "blindLeaveChat")
    }

    func guess(_ id: BlindChatID, card: BlindCardID) async throws(BlindError) {
        let _: Wire.Ok = try await call(
            .post, "/api/blind/chats/\(id.rawValue)/guess", body: Wire.GuessRequest(guessId: card.rawValue), operationID: "blindGuess",
        )
    }

    // MARK: Safety

    func block(_ id: BlindChatID) async throws(BlindError) {
        let _: Wire.Ok = try await call(.post, "/api/blind/chats/\(id.rawValue)/block", operationID: "blindBlock")
    }

    func report(_ id: BlindChatID, reason: String) async throws(BlindError) {
        let _: Wire.Ok = try await call(
            .post, "/api/blind/chats/\(id.rawValue)/report", body: Wire.ReportRequest(reason: reason), operationID: "blindReport",
        )
    }

    // MARK: Photos

    /// A relative `/api/...` link goes through the API with the token; an absolute signed storage
    /// link is fetched without it, on an ephemeral session with no cache, so the token never leaves
    /// the API's host and nothing reaches the disk.
    func photo(_ photo: BlindPhoto) async throws(BlindError) -> PrivateImage {
        let data: Data
        if photo.url.hasPrefix("/api/") {
            var fields = HTTPFields()
            fields[.accept] = "image/jpeg"
            fields[.cacheControl] = "no-store"
            let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: photo.url, headerFields: fields)
            do {
                let (response, body) = try await api.send(request, operationID: "blindGetPhoto")
                guard response.status.code == 200, let body else { throw BlindError.notFound }
                data = try await Data(collecting: body, upTo: 8 * 1024 * 1024)
            } catch let error as BlindError {
                throw error
            } catch let error as APIError {
                throw BlindError(error)
            } catch {
                throw .unexpected
            }
        } else {
            guard let url = URL(string: photo.url), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
                throw .notFound
            }
            do {
                let (body, response) = try await Self.photoSession.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw BlindError.notFound }
                data = body
            } catch let error as BlindError {
                throw error
            } catch {
                throw .offline
            }
        }
        guard let image = UIImage(data: data) else { throw .unexpected }
        return PrivateImage(image: image)
    }

    private static let photoSession = URLSession(configuration: .glowAPI)

    // MARK: Plumbing

    private func call<Output: Decodable>(
        _ method: HTTPRequest.Method,
        _ path: String,
        body: (some Encodable)? = Wire.Empty?.none,
        operationID: String,
    ) async throws(BlindError) -> Output {
        var fields = HTTPFields()
        fields[.accept] = "application/json"
        var payload: HTTPBody?
        if let body {
            fields[.contentType] = "application/json"
            guard let data = try? Self.encoder.encode(body) else { throw .invalid }
            payload = HTTPBody(data)
        }
        let request = HTTPRequest(method: method, scheme: nil, authority: nil, path: path, headerFields: fields)
        let response: HTTPResponse
        let responseBody: HTTPBody?
        do {
            (response, responseBody) = try await api.send(request, body: payload, operationID: operationID)
        } catch {
            throw BlindError(error)
        }
        var data = Data()
        if let responseBody {
            do {
                data = try await Data(collecting: responseBody, upTo: 2 * 1024 * 1024)
            } catch {
                throw .unexpected
            }
        }
        switch response.status.code {
        case 200 ..< 300:
            do {
                return try Self.decoder.decode(Output.self, from: data)
            } catch {
                throw .unexpected
            }
        case 400, 422: throw .invalid
        case 409:
            let code = (try? Self.decoder.decode(Wire.ErrorEnvelope.self, from: data))?.error.code
            throw BlindError(conflictCode: code)
        case 503: throw .offline
        default: throw .unexpected
        }
    }

    private static let encoder = JSONEncoder()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)) {
                return date
            }
            if let date = try? Date(text, strategy: .iso8601) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 date"))
        }
        return decoder
    }()
}

extension BlindError {
    init(_ error: APIError) {
        switch error {
        case .notFound: self = .notFound
        case .unauthorized: self = .unauthorized
        case .rateLimited: self = .rateLimited
        case .offline: self = .offline
        case .cancelled: self = .cancelled
        case .unexpected: self = .unexpected
        }
    }

    /// A 409's error code, as Double Blind's contract names them.
    init(conflictCode code: String?) {
        switch code {
        case "right_cap_reached": self = .rightCapReached
        case "drop_not_ready": self = .dropNotReady
        case "chat_closed", "chat_not_open", "chat_left": self = .chatClosed
        default: self = .unexpected
        }
    }
}

/// The JSON on the wire. Only what the app reads; unknown fields are ignored.
enum Wire {
    struct Empty: Codable {}

    struct Ok: Decodable {
        let ok: Bool?
    }

    struct ErrorEnvelope: Decodable {
        struct Body: Decodable {
            let code: String
        }

        let error: Body
    }

    struct Me: Decodable {
        let member: Bool?
        let isMember: Bool?
        let joined: Bool?
        let rightRemaining: Int
        let rightCount: Int
        let canDrop: Bool

        var model: BlindMe {
            BlindMe(
                isMember: member ?? isMember ?? joined ?? false,
                rightRemaining: rightRemaining,
                rightCount: rightCount,
                canDrop: canDrop,
            )
        }
    }

    struct Card: Decodable {
        let id: String
        let photoUrl: String

        var model: BlindCard? {
            BlindCardID(validating: id).map { BlindCard(id: $0, photo: BlindPhoto(url: photoUrl)) }
        }
    }

    struct Cards: Decodable {
        let cards: [Card]
    }

    struct SwipeRequest: Encodable {
        let targetId: String
        let kind: String
    }

    struct Counters: Decodable {
        let rightRemaining: Int
        let rightCount: Int
    }

    struct Pool: Decodable {
        let rightCount: Int
        let rightRemaining: Int
        let canDrop: Bool
    }

    struct DropStatus: Decodable {
        let ready: Bool
        let demo: Bool
        let nextDropAt: Date
        let rightCount: Int
        let canDrop: Bool
    }

    struct DropChat: Decodable {
        let id: String
        let codename: String
    }

    struct DropResult: Decodable {
        let opened: Int
        let chats: [DropChat]?
    }

    struct LastMessage: Decodable {
        let mine: Bool
        let text: String
        let at: Date
    }

    struct ChatSummary: Decodable {
        let id: String
        let codename: String
        let status: String
        let lastMessage: LastMessage?
        let unread: Bool

        var model: BlindChatSummary? {
            guard let chatID = BlindChatID(validating: id) else { return nil }
            return BlindChatSummary(
                id: chatID,
                codename: codename,
                status: BlindChatStatus(rawValue: status) ?? .open,
                lastMessage: lastMessage.map { BlindLastMessage(mine: $0.mine, text: $0.text, at: $0.at) },
                unread: unread,
            )
        }
    }

    struct ChatList: Decodable {
        let chats: [ChatSummary]
    }

    struct Partner: Decodable {
        let name: String
        let photos: [String]
    }

    struct ChatDetail: Decodable {
        let id: String
        let codename: String
        let status: String
        let iTappedReveal: Bool
        let theyLeft: Bool
        let partner: Partner?
        let guessCorrect: Bool?

        var model: BlindChatDetail? {
            guard let chatID = BlindChatID(validating: id) else { return nil }
            let status = BlindChatStatus(rawValue: status) ?? .open
            return BlindChatDetail(
                id: chatID,
                codename: codename,
                status: status,
                iTappedReveal: iTappedReveal,
                theyLeft: theyLeft,
                // B1, belt and braces: a partner is only ever shown on a revealed chat.
                partner: status == .revealed ? partner.map { BlindPartner(name: $0.name, photos: $0.photos.map(BlindPhoto.init)) } : nil,
                guessCorrect: status == .revealed ? guessCorrect : nil,
            )
        }
    }

    struct Message: Decodable {
        let id: Int
        let mine: Bool
        let text: String
        let at: Date

        var model: BlindMessage {
            BlindMessage(id: id, mine: mine, text: text, at: at)
        }
    }

    struct Messages: Decodable {
        let messages: [Message]
    }

    struct SendRequest: Encodable {
        let text: String
        let confirm: Bool
    }

    struct Warning: Decodable {
        let reason: String
    }

    struct SendResult: Decodable {
        let message: Message?
        let warning: Warning?
    }

    struct Status: Decodable {
        let status: String
    }

    struct GuessRequest: Encodable {
        let guessId: String
    }

    struct ReportRequest: Encodable {
        let reason: String
    }
}
