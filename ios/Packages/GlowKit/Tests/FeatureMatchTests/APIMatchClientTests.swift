import APIClient
import AppCore
import Foundation
import HTTPTypes
import OpenAPIRuntime
import os
import Testing
@testable import FeatureMatch

private let matchID = MatchID(rawValue: "64bfd966-bf7f-426a-b7aa-f0dc371bae1a")

private let detailJSON = """
{"id":"64bfd966-bf7f-426a-b7aa-f0dc371bae1a","status":"choosing","firstName":"Blake","photoCount":2,
"roomId":"de000000-0000-4000-8000-000000000001","roomName":"Glow demo room","createdAt":"2026-10-24T20:10:00.000Z",
"choiceDeadline":"2026-10-24T20:20:00.000Z","otherHasChosen":false}
"""

/// Records each request's operation, path and JSON body, and answers from `responses`.
private final class Recorder: Sendable {
    struct Sent: Sendable {
        let operation: String
        let path: String?
        let body: Data?
    }

    private let sent = OSAllocatedUnfairLock<[Sent]>(initialState: [])
    let responses: [String: MockTransport.Response]

    init(_ responses: [String: MockTransport.Response]) {
        self.responses = responses
    }

    var requests: [Sent] {
        sent.withLock { $0 }
    }

    var api: GlowAPI {
        GlowAPI.mock(MockTransport { [self] request, body, _, operation in
            let data: Data? = if let body {
                try await Data(collecting: body, upTo: 1 << 20)
            } else {
                nil
            }
            sent.withLock { $0.append(Sent(operation: operation, path: request.path, body: data)) }
            let response = responses[operation] ?? .status(.notImplemented)
            var fields = HTTPFields()
            if let type = response.contentType {
                fields[.contentType] = type
            }
            return (HTTPResponse(status: response.status, headerFields: fields), response.body.map { HTTPBody($0) })
        })
    }
}

struct APIMatchClientTests {
    @Test func readsAMatch() async throws {
        let recorder = Recorder(["getMatch": .json(detailJSON)])
        let match = try await APIMatchClient(api: recorder.api).match(matchID)
        #expect(match.id == matchID)
        #expect(match.firstName == "Blake")
        #expect(match.photoCount == 2)
        #expect(match.status == .choosing)
        #expect(match.yourChoice == nil)
        #expect(recorder.requests.first?.path == "/api/matches/64bfd966-bf7f-426a-b7aa-f0dc371bae1a")
    }

    @Test func anEndedMatchIsNotFound() async {
        let recorder = Recorder(["getMatch": .json(#"{"error":{"code":"not_found","message":"Not found."}}"#, status: .notFound)])
        await #expect(throws: MatchError.notFound) {
            try await APIMatchClient(api: recorder.api).match(matchID)
        }
    }

    @Test func findSendsTheFixAndChatSendsNone() async throws {
        let result = #"{"next":"waiting","reason":"other_undecided","match":\#(detailJSON)}"#
        let recorder = Recorder(["setChoice": .json(result)])
        let client = APIMatchClient(api: recorder.api)
        let fix = LocationFix(latitude: 37.8029, longitude: -122.4484, accuracy: 12, timestamp: .now)

        let outcome = try await client.choose(.find, for: matchID, fix: fix)
        #expect(outcome.next == .waiting)
        #expect(outcome.reason == .otherUndecided)
        _ = try await client.choose(.chat, for: matchID, fix: nil)

        let bodies = try recorder.requests.map { try JSONSerialization.jsonObject(with: #require($0.body)) as? [String: Any] }
        #expect(bodies[0]?["choice"] as? String == "find")
        let location = try #require(bodies[0]?["location"] as? [String: Double])
        // Exactly the contract's three numbers: no timestamp, nothing else about the phone.
        #expect(Set(location.keys) == ["latitude", "longitude", "accuracy"])
        #expect(bodies[1]?["choice"] as? String == "chat")
        #expect(bodies[1]?["location"] == nil)
        #expect(recorder.requests.allSatisfy { $0.path == "/api/matches/64bfd966-bf7f-426a-b7aa-f0dc371bae1a/choice" })
    }

    @Test(arguments: [
        ("not_in_room", MatchError.notInRoom),
        ("location_inaccurate", .locationInaccurate),
        ("location_required", .locationInaccurate),
    ])
    func locationRefusalsBecomeNotes(code: String, expected: MatchError) async {
        let body = #"{"error":{"code":"\#(code)","message":"No."}}"#
        let recorder = Recorder(["setChoice": .json(body, status: .unprocessableContent)])
        await #expect(throws: expected) {
            try await APIMatchClient(api: recorder.api).choose(.find, for: matchID, fix: nil)
        }
    }

    @Test func decodesTheGlowOutcome() async throws {
        let glowing = detailJSON.replacingOccurrences(of: #""status":"choosing""#, with: #""status":"glowing""#)
        let recorder = Recorder(["setChoice": .json(#"{"next":"glow","reason":"both_find","match":\#(glowing)}"#)])
        let outcome = try await APIMatchClient(api: recorder.api).choose(.find, for: matchID, fix: nil)
        #expect(outcome.next == .glow)
        #expect(outcome.match.destination == .glow(matchID))
    }

    @Test func listsMatches() async throws {
        let list = """
        {"matches":[{"id":"64bfd966-bf7f-426a-b7aa-f0dc371bae1a","status":"chatting","firstName":"Blake",
        "roomName":"Glow demo room","createdAt":"2026-10-24T20:10:00.000Z","choiceDeadline":"2026-10-24T20:20:00.000Z"}]}
        """
        let recorder = Recorder(["listMatches": .json(list)])
        let matches = try await APIMatchClient(api: recorder.api).matches()
        #expect(matches.map(\.status) == [.chatting])
        #expect(matches.first?.route == .chat(matchID))
    }
}
