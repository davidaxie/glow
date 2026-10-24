import APIClient
import AppCore
import Foundation
import HTTPTypes
import OpenAPIRuntime
import SwiftUI
import Testing
@testable import FeatureRooms

// MARK: - Test doubles

/// Test data only: the seeded demo room, a placeholder venue (D11).
enum Demo {
    static let roomID = RoomID(rawValue: "de000000-0000-4000-8000-000000000001")
    static let now = Date(timeIntervalSince1970: 1_793_000_000)
    static let room = RoomInfo(
        id: roomID,
        slug: "demo",
        name: "Glow demo room (test data)",
        status: .live,
        startsAt: now.addingTimeInterval(-3600),
        endsAt: now.addingTimeInterval(3600),
    )
    static let link = RoomEntry.link(slug: "demo", token: "DEMOSTATICTOKEN2")
    static let fix = LocationFix(latitude: 37.8029, longitude: -122.4484, accuracy: 5, timestamp: now)
}

final class MockJoining: RoomJoining, @unchecked Sendable {
    var resolveResults: [Result<RoomInfo, JoinFailure>]
    var joinResults: [Result<JoinTicket, JoinFailure>]
    private(set) var resolveCalls = 0
    private(set) var joinCalls: [(RoomID, RoomEntry)] = []

    init(resolve: [Result<RoomInfo, JoinFailure>] = [.success(Demo.room)], join: [Result<JoinTicket, JoinFailure>] = [.success(JoinTicket("T"))]) {
        resolveResults = resolve
        joinResults = join
    }

    func resolve(_: RoomEntry) async throws(JoinFailure) -> RoomInfo {
        resolveCalls += 1
        let result = resolveResults.count > 1 ? resolveResults.removeFirst() : resolveResults[0]
        return try result.get()
    }

    func join(_ room: RoomID, entry: RoomEntry, fix _: LocationFix) async throws(JoinFailure) -> JoinTicket {
        joinCalls.append((room, entry))
        let result = joinResults.count > 1 ? joinResults.removeFirst() : joinResults[0]
        return try result.get()
    }
}

final class RecordingAnalytics: Analytics, @unchecked Sendable {
    private(set) var events: [AnalyticsEvent] = []
    func track(_ event: AnalyticsEvent) {
        events.append(event)
    }

    func record(_: any Error, context _: StaticString) {}
}

@MainActor
func makeModel(
    entry: RoomEntry = Demo.link,
    joining: MockJoining = MockJoining(),
    location: PreviewLocationService = PreviewLocationService(fix: Demo.fix),
    analytics: RecordingAnalytics = RecordingAnalytics(),
) -> JoinModel {
    JoinModel(entry: entry, service: joining, location: location, analytics: analytics, now: { Demo.now })
}

// MARK: - The join flow

@MainActor
struct JoinModelTests {
    @Test func passesInsideTheRoomAndHandsOverTheTicket() async {
        let joining = MockJoining(join: [.success(JoinTicket("ticket-1"))])
        let model = makeModel(joining: joining)
        await model.startIfNeeded()
        #expect(model.phase == .passed(Demo.roomID, JoinTicket("ticket-1"), expiresAt: Demo.now.addingTimeInterval(GlowConstants.joinTicketTTL)))
        #expect(model.room == Demo.room)
        #expect(joining.joinCalls.count == 1)
        #expect(model.liveTicket?.1 == JoinTicket("ticket-1"))
    }

    @Test func startsOnlyOnce() async {
        let joining = MockJoining()
        let model = makeModel(joining: joining)
        await model.startIfNeeded()
        await model.startIfNeeded()
        #expect(joining.resolveCalls == 1)
        #expect(joining.joinCalls.count == 1)
    }

    @Test func showsNotInRoomAndTriesTheLocationAgainWithoutALookup() async {
        let joining = MockJoining(join: [.failure(.notInRoom), .success(JoinTicket("ticket-2"))])
        let model = makeModel(joining: joining)
        await model.startIfNeeded()
        #expect(model.phase == .failed(.notInRoom))
        await model.retry()
        #expect(joining.resolveCalls == 1)
        #expect(model.liveTicket?.1 == JoinTicket("ticket-2"))
    }

    @Test func aTimedOutFixIsAWeakSignal() async {
        let model = makeModel(location: PreviewLocationService(error: .timedOut))
        await model.startIfNeeded()
        #expect(model.phase == .failed(.weakSignal))
    }

    @Test func aRoughFixTheServerRefusesIsAWeakSignal() async {
        let model = makeModel(joining: MockJoining(join: [.failure(.weakSignal)]))
        await model.startIfNeeded()
        #expect(model.phase == .failed(.weakSignal))
    }

    @Test func locationOffShowsTheSettingsScreen() async {
        let model = makeModel(location: PreviewLocationService(authorization: .denied))
        await model.startIfNeeded()
        #expect(model.phase == .failed(.locationDenied))
        #expect(JoinFailure.locationDenied.primaryAction == .openSettings)
    }

    @Test func asksForLocationWhenNotYetAsked() async {
        let joining = MockJoining()
        let model = makeModel(
            joining: joining,
            location: PreviewLocationService(authorization: .notDetermined, requestedAuthorization: .precise, fix: Demo.fix),
        )
        await model.startIfNeeded()
        #expect(model.liveTicket != nil)
    }

    @Test func approximateOnlyAsksForPreciseAndExplainsWhenDeclined() async {
        let model = makeModel(location: PreviewLocationService(authorization: .approximate, requestedAuthorization: .approximate))
        await model.startIfNeeded()
        #expect(model.phase == .failed(.preciseLocationOff))
    }

    @Test func anEndedRoomStopsBeforeAskingForLocation() async {
        let ended = RoomInfo(
            id: Demo.roomID, slug: "demo", name: "Done", status: .ended,
            startsAt: Demo.now.addingTimeInterval(-7200), endsAt: Demo.now.addingTimeInterval(-3600),
        )
        let joining = MockJoining(resolve: [.success(ended)])
        let model = makeModel(joining: joining, location: PreviewLocationService(error: .denied))
        await model.startIfNeeded()
        #expect(model.phase == .failed(.roomEnded))
        #expect(joining.joinCalls.isEmpty)
    }

    @Test func aLiveRoomPastItsEndIsEnded() async {
        let late = RoomInfo(
            id: Demo.roomID, slug: "demo", name: "Late", status: .live,
            startsAt: Demo.now.addingTimeInterval(-7200), endsAt: Demo.now,
        )
        let model = makeModel(joining: MockJoining(resolve: [.success(late)]))
        await model.startIfNeeded()
        #expect(model.phase == .failed(.roomEnded))
    }

    @Test func aRoomThatHasNotStartedSaysWhenItOpens() async {
        let opens = Demo.now.addingTimeInterval(1800)
        let early = RoomInfo(id: Demo.roomID, slug: "demo", name: "Soon", status: .live, startsAt: opens, endsAt: opens.addingTimeInterval(3600))
        let model = makeModel(joining: MockJoining(resolve: [.success(early)]))
        await model.startIfNeeded()
        #expect(model.phase == .failed(.roomNotOpenYet(opens)))
    }

    @Test func aPausedRoomRetriesTheLookup() async {
        let paused = RoomInfo(id: Demo.roomID, slug: "demo", name: "P", status: .paused, startsAt: Demo.room.startsAt, endsAt: Demo.room.endsAt)
        let joining = MockJoining(resolve: [.success(paused), .success(Demo.room)])
        let model = makeModel(joining: joining)
        await model.startIfNeeded()
        #expect(model.phase == .failed(.roomPaused))
        await model.retry()
        #expect(joining.resolveCalls == 2)
        #expect(model.liveTicket != nil)
    }

    @Test func aRoomThatClosesMidCheckIsLookedUpAgain() async {
        let paused = RoomInfo(id: Demo.roomID, slug: "demo", name: "P", status: .paused, startsAt: Demo.room.startsAt, endsAt: Demo.room.endsAt)
        let joining = MockJoining(resolve: [.success(Demo.room), .success(paused)], join: [.failure(.roomClosed)])
        let model = makeModel(joining: joining)
        await model.startIfNeeded()
        #expect(model.phase == .failed(.roomPaused))
    }

    @Test func aWrongCodeIsNotFound() async {
        let model = makeModel(entry: .code("ZZZZZZ"), joining: MockJoining(resolve: [.failure(.roomNotFound)]))
        await model.startIfNeeded()
        #expect(model.phase == .failed(.roomNotFound))
        #expect(JoinFailure.roomNotFound.primaryAction == .typeCode)
    }

    @Test func analyticsCarryOnlyLiterals() async {
        let analytics = RecordingAnalytics()
        let model = makeModel(joining: MockJoining(join: [.failure(.notInRoom)]), analytics: analytics)
        await model.startIfNeeded()
        #expect(analytics.events.map(\.name) == ["room_join_started", "room_join_failed"])
        #expect(analytics.events[1].properties["reason"] == "not_in_room")
        let everything = analytics.events.map { "\($0)" }.joined()
        #expect(!everything.contains("37.8"))
        #expect(!everything.contains("DEMOSTATICTOKEN2"))
    }
}

// MARK: - Server answers

struct APIRoomJoiningTests {
    static let summary = #"{"id":"de000000-0000-4000-8000-000000000001","slug":"demo","name":"Glow demo room (test data)","status":"live","startsAt":"2026-10-23T06:00:00.000Z","endsAt":"2026-11-22T06:00:00.000Z"}"#

    static func error(_ code: String) -> String {
        #"{"error":{"code":"\#(code)","message":"x"}}"#
    }

    func service(_ responses: [String: MockTransport.Response]) -> APIRoomJoining {
        APIRoomJoining(api: .mock(.responses(responses)))
    }

    @Test func resolvesARoom() async throws {
        let room = try await service(["resolveRoom": .json(Self.summary)]).resolve(Demo.link)
        #expect(room.id == Demo.roomID)
        #expect(room.name == "Glow demo room (test data)")
        #expect(room.status == .live)
    }

    @Test(arguments: [
        (MockTransport.Response.status(.notFound), JoinFailure.roomNotFound),
        (.json(error("bad_request"), status: .badRequest), .roomNotFound),
        (.json(error("onboarding_incomplete"), status: .conflict), .onboardingIncomplete),
        (.status(.tooManyRequests), .rateLimited),
        (.json(error("internal"), status: .internalServerError), .unexpected),
    ])
    func resolveFailures(response: MockTransport.Response, expected: JoinFailure) async {
        await #expect(throws: expected) { try await service(["resolveRoom": response]).resolve(Demo.link) }
    }

    @Test func joinReturnsTheTicket() async throws {
        let ticket = try await service(["joinRoom": .json(#"{"ticket":"abc.def","expiresAt":"2026-10-24T20:10:00.000Z"}"#)])
            .join(Demo.roomID, entry: Demo.link, fix: Demo.fix)
        #expect(ticket == JoinTicket("abc.def"))
    }

    @Test(arguments: [
        (MockTransport.Response.json(error("not_in_room"), status: .unprocessableContent), JoinFailure.notInRoom),
        (.json(error("location_inaccurate"), status: .unprocessableContent), .weakSignal),
        (.json(error("room_not_live"), status: .conflict), .roomClosed),
        (.status(.notFound), .roomNotFound),
    ])
    func joinFailures(response: MockTransport.Response, expected: JoinFailure) async {
        await #expect(throws: expected) {
            try await service(["joinRoom": response]).join(Demo.roomID, entry: Demo.link, fix: Demo.fix)
        }
    }

    @Test func aStaleScreenCodeIsCodeChanged() async {
        let screen = RoomEntry.link(slug: "demo", token: "ABCDEFGH")
        await #expect(throws: JoinFailure.codeChanged) {
            try await service(["joinRoom": .status(.notFound)]).join(Demo.roomID, entry: screen, fix: Demo.fix)
        }
    }

    @Test func sendsOneFixAndTheAccessAndNothingElse() async throws {
        let seen = BodyRecorder()
        let api = GlowAPI.mock(MockTransport { _, body, _, _ in
            if let body {
                await seen.set(try await Data(collecting: body, upTo: 10000))
            }
            var fields = HTTPFields()
            fields[.contentType] = "application/json"
            return (HTTPResponse(status: .ok, headerFields: fields), HTTPBody(#"{"ticket":"t","expiresAt":"2026-10-24T20:10:00.000Z"}"#))
        })
        _ = try await APIRoomJoining(api: api).join(Demo.roomID, entry: Demo.link, fix: Demo.fix)
        let json = try #require(await seen.data.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(Set(json.keys) == ["access", "location"])
        let location = try #require(json["location"] as? [String: Any])
        #expect(Set(location.keys) == ["latitude", "longitude", "accuracy"])
    }
}

actor BodyRecorder {
    var data: Data?
    func set(_ value: Data) {
        data = value
    }
}

// MARK: - Codes and links

struct RoomCodeTests {
    @Test func normalizesWhatPeopleType() {
        #expect(RoomCode.normalize("hack26") == "HACK26")
        #expect(RoomCode.normalize("ha-ck 26") == "HACK26")
        #expect(RoomCode.normalize("HACK26XYZ") == "HACK26")
        // O, 0, I and 1 are never in a code.
        #expect(RoomCode.normalize("O0I1AB") == "AB")
    }

    @Test func knowsAWholeCode() {
        #expect(RoomCode.isComplete("HACK26"))
        #expect(!RoomCode.isComplete("HACK2"))
        #expect(!RoomCode.isComplete("HACK2O"))
    }

    @Test func aLinkWithoutATokenNeedsTheCode() {
        #expect(RoomEntry(link: RoomLink(slug: "demo", token: nil)) == nil)
        #expect(RoomEntry(link: RoomLink(slug: "demo", token: "DEMOSTATICTOKEN2")) == Demo.link)
    }

    @Test func entriesNeverPrintTheirSecrets() {
        #expect(!"\(Demo.link)".contains("DEMOSTATICTOKEN2"))
        #expect(!"\(RoomEntry.code("HACK26"))".contains("HACK26"))
    }

    @Test func tellsScreenTokensFromPosterTokens() {
        #expect(RoomEntry.link(slug: "demo", token: "ABCDEFGH").isRotatingToken)
        #expect(!Demo.link.isRotatingToken)
        #expect(!RoomEntry.code("HACK26").isRotatingToken)
    }
}

// MARK: - Screens build

@MainActor
struct RoomsScreensTests {
    @Test func everyScreenBuilds() {
        _ = RoomsHomeView().body
        _ = RoomCodeEntryView().body
        _ = RoomScannerView().body
        _ = RoomJoinView(link: RoomLink(slug: "demo", token: "DEMOSTATICTOKEN2")).body
        _ = RoomJoinView(link: RoomLink(slug: "demo", token: nil)).body
    }

    @Test func everyFailureHasCopyAndAnAction() {
        let all: [JoinFailure] = [
            .notInRoom, .weakSignal, .roomEnded, .roomPaused, .roomClosed, .roomNotOpenYet(Demo.now), .roomNotFound,
            .codeChanged, .locationDenied, .preciseLocationOff, .locationUnavailable, .onboardingIncomplete,
            .offline, .rateLimited, .unexpected,
        ]
        for failure in all {
            #expect(!failure.title.isEmpty)
            #expect(!failure.message.isEmpty)
            #expect(!failure.primaryAction.title.isEmpty)
        }
        #expect(JoinFailure.notInRoom.message == "Looks like you're not in this room yet. Try again inside.")
    }
}
