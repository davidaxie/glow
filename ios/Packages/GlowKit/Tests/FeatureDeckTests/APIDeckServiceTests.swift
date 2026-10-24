import APIClient
import AppCore
import Foundation
import Testing
@testable import FeatureDeck

/// The live service against canned server answers: what it sends, and what it makes of replies.
struct APIDeckServiceTests {
    @Test func deckSendsTheFiltersInTheContractsShape() async throws {
        let transport = RecordingTransport(["getDeck": .init(
            status: 200,
            json: deckJSON(cards: [cardJSON(1)], hasMore: true, nextOffset: 10),
        )])
        let service = APIDeckService(api: api(transport))
        var filters = NoticedFilters()
        filters.topColors = [.blue, .green]
        filters.extras = [.glasses]
        filters.genders = [.woman]

        let page = try await service.deck(testRoom, filters: filters, offset: 10)

        #expect(page.cards.count == 1)
        #expect(page.nextOffset == 10)
        #expect(page.viewsLeftToday == 40)
        let sent = try #require(transport.sent.first)
        #expect(sent.method == .post)
        #expect(sent.path == "/api/rooms/de000000-0000-4000-8000-000000000001/deck")
        let body = try #require(sent.body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["offset"] as? Int == 10)
        let sentFilters = try #require(body["filters"] as? [String: [String]])
        // Lists come in the contract's enum order; parts I didn't pick are left out.
        #expect(sentFilters == ["topColor": ["green", "blue"], "extras": ["glasses"], "gender": ["woman"]])
    }

    @Test func noFiltersSendsNoFilters() async throws {
        let transport = RecordingTransport(["getDeck": .init(status: 200, json: deckJSON(cards: [], emptyReason: "quiet"))])
        let page = try await APIDeckService(api: api(transport)).deck(testRoom, filters: .none, offset: 0)
        #expect(page.emptyReason == .quiet)
        let body = try #require(transport.sent.first?.body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["filters"] == nil)
    }

    /// P1 on the phone too: the generated decoder refuses any field the contract doesn't have, so a
    /// deck reply carrying a user ID (or anything else) is thrown away, never shown.
    @Test func aDeckReplyWithAUserIDIsRefused() async throws {
        let leaky = cardJSON(1).replacingOccurrences(
            of: #""tappedByMe":false"#,
            with: #""tappedByMe":false,"userId":"7e570000-0000-4000-8000-000000000001""#,
        )
        let transport = RecordingTransport(["getDeck": .init(status: 200, json: deckJSON(cards: [leaky]))])
        await #expect(throws: DeckFailure.unexpected) {
            try await APIDeckService(api: api(transport)).deck(testRoom, filters: .none, offset: 0)
        }
    }

    @Test func aSentTapSaysOnlyWhatsLeft() async throws {
        let transport = RecordingTransport(["createTap": .init(status: 200, json: #"{"result":"sent","tapsLeftToday":2}"#)])
        let card = CardID(rawValue: FixtureDeckService.fixtureUUID(3))
        let outcome = try await APIDeckService(api: api(transport)).tap(card, in: testRoom)
        #expect(outcome == .sent(tapsLeftToday: 2))
        let body = try #require(transport.sent.first?.body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        #expect(body == ["cardId": card.rawValue])
    }

    @Test func aMutualTapCarriesTheMatch() async throws {
        let json = #"{"result":"mutual","tapsLeftToday":1,"matchId":"64bfd966-bf7f-426a-b7aa-f0dc371bae1a"}"#
        let transport = RecordingTransport(["createTap": .init(status: 200, json: json)])
        let outcome = try await APIDeckService(api: api(transport)).tap(CardID(rawValue: FixtureDeckService.fixtureUUID(3)), in: testRoom)
        #expect(outcome == .mutual(MatchID(rawValue: "64bfd966-bf7f-426a-b7aa-f0dc371bae1a"), tapsLeftToday: 1))
    }

    @Test func tapErrorsMapToWhatTheScreenSays() async {
        let limit = RecordingTransport(["createTap": .init(
            status: 409,
            json: #"{"error":{"code":"tap_limit_reached","message":"No taps left."}}"#,
        )])
        await #expect(throws: DeckFailure.tapLimitReached) {
            try await APIDeckService(api: api(limit)).tap(CardID(rawValue: FixtureDeckService.fixtureUUID(3)), in: testRoom)
        }
        let gone = RecordingTransport(["createTap": .init(status: 404, json: #"{"error":{"code":"not_found","message":"Not found."}}"#)])
        await #expect(throws: DeckFailure.notFound) {
            try await APIDeckService(api: api(gone)).tap(CardID(rawValue: FixtureDeckService.fixtureUUID(3)), in: testRoom)
        }
    }

    @Test func roomStateReadsMyCheckinAndWhatsLeft() async throws {
        let transport = RecordingTransport(["getRoomState": .init(status: 200, json: roomStateJSON)])
        let state = try await APIDeckService(api: api(transport)).roomState(testRoom)
        #expect(state.name == "Glow demo room (test data)")
        #expect(state.slug == "demo")
        #expect(state.tapsLeftToday == 2)
        #expect(state.viewsLeftToday == 37)
        #expect(state.checkin?.visible == true)
        #expect(transport.sent.first?.method == .get)
    }

    @Test func leavePausesAndCaptureReports() async throws {
        let transport = RecordingTransport([
            "leaveRoom": .init(status: 204, json: nil),
            "setPaused": .init(status: 200, json: #"{"paused":true}"#),
            "logCapture": .init(status: 204, json: nil),
        ])
        let service = APIDeckService(api: api(transport))
        try await service.leave(testRoom)
        #expect(try await service.setPaused(true))
        await service.reportCapture(.screenshot, in: testRoom)

        #expect(transport.sent.map(\.operationID) == ["leaveRoom", "setPaused", "logCapture"])
        #expect(transport.sent[0].path == "/api/rooms/de000000-0000-4000-8000-000000000001/leave")
        let capture = try #require(transport.sent[2].body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        // Only the kind and the room: never who or what was on screen.
        #expect(capture == ["kind": "screenshot", "roomId": testRoom.rawValue])
    }

    @Test func aFailedCaptureReportNeverThrows() async {
        let transport = RecordingTransport(["logCapture": .init(status: 500, json: #"{"error":{"code":"internal","message":"x"}}"#)])
        await APIDeckService(api: api(transport)).reportCapture(.recording, in: testRoom)
        #expect(transport.sent.count == 1)
    }

    @Test func onlyCardImageLinksAreFetched() {
        let id = FixtureDeckService.fixtureUUID(1)
        #expect(APICardImageLoader.isCardImageLink("/api/cards/\(id)/image?exp=1&sig=abc"))
        #expect(!APICardImageLoader.isCardImageLink("https://evil.example/api/cards/\(id)/image?exp=1&sig=abc"))
        #expect(!APICardImageLoader.isCardImageLink("//evil.example/api/cards/\(id)/image?exp=1&sig=abc"))
        #expect(!APICardImageLoader.isCardImageLink("/api/me/photos/\(id)"))
        #expect(!APICardImageLoader.isCardImageLink("/api/cards/\(id.uppercased())/image?exp=1&sig=abc"))
        #expect(!APICardImageLoader.isCardImageLink("/api/cards/\(id)/image?exp=1&sig=abc&next=x"))
    }
}
