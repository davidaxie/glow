import APIClient
import AppCore
import Foundation
import Testing
@testable import GlowRealtime

struct GlowRealtimeTests {
    static let match = "f1c70000-0000-4000-8000-000000000001"
    static let room = "de000000-0000-4000-8000-000000000001"

    @Test func liveFactoryReturnsAService() {
        let context = ServiceContext(config: .preview, api: .mock(), session: PreviewSessionService(), analytics: NoopAnalytics())
        _ = RealtimeModule.live(context)
    }

    @Test func everyEventKindMatchesTheContract() {
        #expect(RealtimeEventKind.allCases.map(\.rawValue) == [
            "match.created", "match.choice", "match.recheck", "match.ended", "glow.started",
            "glow.ended", "message.created", "checkin.expiring", "deck.changed",
        ])
    }

    @Test(arguments: RealtimeEventKind.allCases)
    func decodesEveryContractPayload(kind: RealtimeEventKind) throws {
        let isRoomEvent = kind == .checkinExpiring || kind == .deckChanged
        let json = isRoomEvent
            ? #"{"type":"\#(kind.rawValue)","roomId":"\#(Self.room.uppercased())"}"#
            : #"{"type":"\#(kind.rawValue)","matchId":"\#(Self.match)"}"#
        let event = try #require(RealtimeEvent(eventJSON: Data(json.utf8)))
        #expect(event.kind == kind)
        #expect(event.matchID?.rawValue == (isRoomEvent ? nil : Self.match))
        #expect(event.roomID?.rawValue == (isRoomEvent ? Self.room : nil))
    }

    @Test(arguments: [
        #"{"type":"match.created","matchId":"f1c70000-0000-4000-8000-000000000001","userId":"x"}"#,
        #"{"type":"match.created","matchId":"f1c70000-0000-4000-8000-000000000001","firstName":"Robin"}"#,
        #"{"type":"match.created","matchId":"nope"}"#,
        #"{"type":"deck.changed","matchId":"f1c70000-0000-4000-8000-000000000001"}"#,
        #"{"type":"unknown","matchId":"f1c70000-0000-4000-8000-000000000001"}"#,
        #"[]"#,
    ])
    func refusesAnythingOutsideTheContract(json: String) {
        #expect(RealtimeEvent(eventJSON: Data(json.utf8)) == nil)
    }

    @Test func filteredStreamsOnlyYieldWhatWasAskedFor() async {
        let realtime = PreviewRealtimeService()
        let matchID = MatchID(rawValue: Self.match)
        let other = MatchID(rawValue: "f1c70000-0000-4000-8000-000000000002")
        let byKind = realtime.events(.matchEnded)
        let byMatch = realtime.events(for: matchID)

        // Let both streams subscribe before anything is emitted.
        try? await Task.sleep(for: .milliseconds(50))
        realtime.emit(RealtimeEvent(kind: .messageCreated, matchID: other))
        realtime.emit(RealtimeEvent(kind: .messageCreated, matchID: matchID))
        realtime.emit(RealtimeEvent(kind: .matchEnded, matchID: other))

        var kindIterator = byKind.makeAsyncIterator()
        var matchIterator = byMatch.makeAsyncIterator()
        #expect(await kindIterator.next() == RealtimeEvent(kind: .matchEnded, matchID: other))
        #expect(await matchIterator.next() == RealtimeEvent(kind: .messageCreated, matchID: matchID))
    }

    @Test func destinationsCoverEveryEvent() {
        let matchID = MatchID(rawValue: Self.match)
        let roomID = RoomID(rawValue: Self.room)
        for kind in RealtimeEventKind.allCases {
            let isRoomEvent = kind == .checkinExpiring || kind == .deckChanged
            let event = isRoomEvent ? RealtimeEvent(kind: kind, roomID: roomID) : RealtimeEvent(kind: kind, matchID: matchID)
            #expect(event.destination != nil, "\(kind.rawValue) has no screen")
        }
    }
}
