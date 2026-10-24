import APIClient
import AppCore
import Foundation
import HTTPTypes
import OpenAPIRuntime
import os
@testable import FeatureDeck

let testRoom = RoomID(rawValue: "de000000-0000-4000-8000-000000000001")

/// A fixed clock for tests.
let testNow = Date(timeIntervalSince1970: 1_793_040_000)

/// Records every request and answers each operation from a table, like the server would.
final class RecordingTransport: ClientTransport, @unchecked Sendable {
    struct Sent: Sendable {
        let operationID: String
        let method: HTTPRequest.Method
        let path: String
        let body: Data?
    }

    struct Answer: Sendable {
        var status: Int
        var json: String?
    }

    private struct State {
        var answers: [String: [Answer]]
        var sent: [Sent] = []
        var received: [Data] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    init(_ answers: [String: [Answer]]) {
        state = OSAllocatedUnfairLock(uncheckedState: State(answers: answers))
    }

    convenience init(_ answers: [String: Answer]) {
        self.init(answers.mapValues { [$0] })
    }

    var sent: [Sent] {
        state.withLockUnchecked { $0.sent }
    }

    /// Every response body the app was handed, for traffic checks.
    var received: [Data] {
        state.withLockUnchecked { $0.received }
    }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL _: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        var bodyData: Data?
        if let body {
            bodyData = try await Data(collecting: body, upTo: 1_000_000)
        }
        let answer = state.withLockUnchecked { state -> Answer in
            state.sent.append(Sent(operationID: operationID, method: request.method, path: request.path ?? "", body: bodyData))
            guard var queue = state.answers[operationID], !queue.isEmpty else { return Answer(status: 501, json: nil) }
            let next = queue.count > 1 ? queue.removeFirst() : queue[0]
            state.answers[operationID] = queue
            if let json = next.json {
                state.received.append(Data(json.utf8))
            }
            return next
        }
        var fields = HTTPFields()
        if answer.json != nil {
            fields[.contentType] = "application/json"
        }
        return (HTTPResponse(status: .init(code: answer.status), headerFields: fields), answer.json.map { HTTPBody(Data($0.utf8)) })
    }
}

func api(_ transport: RecordingTransport) -> GlowAPI {
    GlowAPI(
        serverURL: URL(string: "http://localhost:3000")!,
        transport: transport,
        middlewares: GlowAPI.standardMiddlewares(
            baseURL: URL(string: "http://localhost:3000")!,
            tokens: StaticAccessToken("token"),
            retry: .none,
        ),
    )
}

/// A deck card as the server sends it.
func cardJSON(_ index: Int, top: String = "green", tapped: Bool = false, extras: String = #"["glasses"]"#) -> String {
    let id = FixtureDeckService.fixtureUUID(index)
    return """
    {"id":"\(id)","image":{"url":"/api/cards/\(id)/image?exp=1793040060&sig=Xb3fQ0x2lN4m3P1QeRrS5T6uV7wX8yZ9a0b1c2d3e4f",\
    "expiresAt":"2026-10-24T20:16:00.000Z"},"tags":{"topColor":"\(top)","hairLength":"short","hairColor":"brown",\
    "extras":\(extras)},"tappedByMe":\(tapped)}
    """
}

func deckJSON(cards: [String], viewsLeft: Int = 40, hasMore: Bool = false, nextOffset: Int? = nil, emptyReason: String? = nil) -> String {
    var fields = [#""cards":[\#(cards.joined(separator: ","))]"#, #""viewsLeftToday":\#(viewsLeft)"#, #""hasMore":\#(hasMore)"#]
    if let nextOffset {
        fields.append(#""nextOffset":\#(nextOffset)"#)
    }
    if let emptyReason {
        fields.append(#""emptyReason":"\#(emptyReason)""#)
    }
    return "{\(fields.joined(separator: ","))}"
}

let roomStateJSON = """
{"room":{"id":"de000000-0000-4000-8000-000000000001","slug":"demo","name":"Glow demo room (test data)","status":"live",\
"startsAt":"2026-10-23T06:00:00.000Z","endsAt":"2026-11-22T06:00:00.000Z"},\
"checkin":{"cardId":"bbbbbbbb-0000-4000-8000-000000000009","roomId":"de000000-0000-4000-8000-000000000001",\
"tags":{"topColor":"blue","extras":[]},"visible":true,"joinedAt":"2026-10-24T19:00:00.000Z",\
"expiresAt":"2026-10-24T22:00:00.000Z","image":{"url":"/api/cards/bbbbbbbb-0000-4000-8000-000000000009/image?exp=1&sig=x",\
"expiresAt":"2026-10-24T20:16:00.000Z"}},"tapsLeftToday":2,"viewsLeftToday":37}
"""
