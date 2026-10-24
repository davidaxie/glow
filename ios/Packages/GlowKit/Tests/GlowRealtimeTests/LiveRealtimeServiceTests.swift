import APIClient
import AppCore
import Foundation
import os
import Testing
@testable import GlowRealtime

@Suite(.timeLimit(.minutes(1)))
struct LiveRealtimeServiceTests {
    static let alex = "7E570000-0000-4000-8000-00000000000A"
    static let blake = "7e570000-0000-4000-8000-00000000000b"
    static let match = "f1c70000-0000-4000-8000-000000000001"
    static let room = RoomID(rawValue: "de000000-0000-4000-8000-000000000001")
    static let otherRoom = RoomID(rawValue: "de000000-0000-4000-8000-000000000002")

    @Test func joinsTheOwnUserChannelOnSignInWithALowercaseTopic() async {
        let harness = Self.make(userID: Self.alex)
        let service = harness.service
        let transport = harness.transport
        #expect(await eventually { transport.joined == ["user:7e570000-0000-4000-8000-00000000000a"] })
        #expect(await eventually { await service.firstState() == .connected })
    }

    @Test func deliversContractEventsAndDropsEverythingElse() async throws {
        let harness = Self.make(userID: Self.alex)
        let service = harness.service
        let transport = harness.transport
        #expect(await eventually { !transport.joined.isEmpty })
        let topic = try #require(transport.joined.first)
        var events = service.events().makeAsyncIterator()

        transport.deliver(topic, "match.created", #"{"type":"match.created","matchId":"\#(Self.match)","userId":"x"}"#)
        transport.deliver(topic, "match.created", #"{"type":"match.created","matchId":"\#(Self.match)","firstName":"Sam"}"#)
        transport.deliver(topic, "glow.started", #"{"type":"match.created","matchId":"\#(Self.match)"}"#)
        transport.deliver(topic, "match.created", #"{"type":"match.created","matchId":"not-a-uuid"}"#)
        transport.deliver(topic, "match.created", #"{"type":"match.created","matchId":"\#(Self.match)"}"#)

        let event = await events.next()
        #expect(event == RealtimeEvent(kind: .matchCreated, matchID: MatchID(rawValue: Self.match)))
    }

    @Test func neverReplaysAnEventToALaterSubscriber() async throws {
        let harness = Self.make(userID: Self.alex)
        let service = harness.service
        let transport = harness.transport
        #expect(await eventually { !transport.joined.isEmpty })
        let topic = try #require(transport.joined.first)
        transport.deliver(topic, "glow.ended", #"{"type":"glow.ended","matchId":"\#(Self.match)"}"#)

        var events = service.events().makeAsyncIterator()
        transport.deliver(topic, "match.ended", #"{"type":"match.ended","matchId":"\#(Self.match)"}"#)
        #expect(await events.next()?.kind == .matchEnded)
    }

    @Test func joinsOneRoomAtATime() async throws {
        let harness = Self.make(userID: Self.alex)
        let service = harness.service
        let transport = harness.transport
        #expect(await eventually { transport.joined.count == 1 })

        try await service.join(room: Self.room)
        try await service.join(room: Self.otherRoom)
        #expect(transport.joined == [
            "room:de000000-0000-4000-8000-000000000002",
            "user:7e570000-0000-4000-8000-00000000000a",
        ])
        #expect(transport.left.contains("room:de000000-0000-4000-8000-000000000001"))

        await service.leaveRoom()
        #expect(transport.joined == ["user:7e570000-0000-4000-8000-00000000000a"])
    }

    @Test func signingOutLeavesEveryChannel() async throws {
        let harness = Self.make(userID: Self.alex)
        let service = harness.service
        let transport = harness.transport
        let session = harness.session
        #expect(await eventually { transport.joined.count == 1 })
        try await service.join(room: Self.room)

        session.endSession()
        #expect(await eventually { transport.joined.isEmpty })
        #expect(transport.disconnects >= 1)
        #expect(await eventually { await service.firstState() == .disconnected })
    }

    @Test func theNextPersonNeverInheritsTheLastPersonsChannels() async throws {
        let harness = Self.make(userID: Self.alex)
        let service = harness.service
        let transport = harness.transport
        let session = harness.session
        #expect(await eventually { transport.joined.count == 1 })
        try await service.join(room: Self.room)

        session.endSession()
        session.signIn(as: Self.blake)
        #expect(await eventually { transport.joined == ["user:7e570000-0000-4000-8000-00000000000b"] })
    }

    @Test func refusedJoinThrowsAndStaysDisconnected() async {
        let harness = Self.make(userID: nil)
        let service = harness.service
        let transport = harness.transport
        transport.refuse("user:")
        await #expect(throws: RealtimeServiceError.notSignedIn) { try await service.connect() }

        let refusingHarness = Self.make(userID: Self.alex, refuse: "user:")
        let refusing = refusingHarness.service
        let refusingTransport = refusingHarness.transport
        await #expect(throws: RealtimeServiceError.joinFailed) { try await refusing.connect() }
        #expect(refusingTransport.joined.isEmpty)
        #expect(await eventually { await refusing.firstState() == .disconnected })
    }

    @Test func comingBackToTheForegroundRejoinsWhatDropped() async throws {
        let harness = Self.make(userID: Self.alex)
        let service = harness.service
        let transport = harness.transport
        let foreground = harness.foreground
        #expect(await eventually { transport.joined.count == 1 })
        try await service.join(room: Self.room)

        transport.dropAll()
        foreground.yield()
        #expect(await eventually { transport.joinCount == 4 })
        #expect(transport.joined.sorted() == [
            "room:de000000-0000-4000-8000-000000000001",
            "user:7e570000-0000-4000-8000-00000000000a",
        ])
        #expect(transport.authRefreshes >= 1)
        #expect(await eventually { await service.firstState() == .connected })
    }

    // MARK: Helpers

    static func make(
        userID: String?,
        refuse prefix: String? = nil,
    ) -> Harness {
        let transport = FakeTransport()
        if let prefix {
            transport.refuse(prefix)
        }
        let session = RealtimeTestSession(userID: userID)
        let (foregrounds, continuation) = AsyncStream<Void>.makeStream()
        let service = LiveRealtimeService(transport: transport, session: session, foregrounds: foregrounds)
        return Harness(service: service, transport: transport, session: session, foreground: continuation)
    }

    struct Harness {
        let service: LiveRealtimeService
        let transport: FakeTransport
        let session: RealtimeTestSession
        let foreground: AsyncStream<Void>.Continuation
    }
}

extension LiveRealtimeService {
    func firstState() async -> RealtimeConnectionState? {
        var iterator = connectionStates().makeAsyncIterator()
        return await iterator.next()
    }
}

/// Records joins and leaves, refuses topics on request, and delivers broadcasts by hand.
final class FakeTransport: RealtimeTransport {
    private struct Member {
        let topic: String
        let deliver: @Sendable (String, Data) -> Void
        var joined = true
    }

    private struct State {
        var members: [UUID: Member] = [:]
        var refused: [String] = []
        var left: [String] = []
        var joinCount = 0
        var disconnects = 0
        var authRefreshes = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let status = AsyncStream<TransportStatus>.makeStream()

    var joined: [String] {
        state.withLock { $0.members.values.filter(\.joined).map(\.topic).sorted() }
    }

    var left: [String] {
        state.withLock { $0.left }
    }

    var joinCount: Int {
        state.withLock { $0.joinCount }
    }

    var disconnects: Int {
        state.withLock { $0.disconnects }
    }

    var authRefreshes: Int {
        state.withLock { $0.authRefreshes }
    }

    func refuse(_ prefix: String) {
        state.withLock { $0.refused.append(prefix) }
    }

    func deliver(_ topic: String, _ event: String, _ json: String) {
        let targets = state.withLock { $0.members.values.filter { $0.topic == topic && $0.joined }.map(\.deliver) }
        for deliver in targets {
            deliver(event, Data(json.utf8))
        }
    }

    /// Every channel drops, as when the socket closes in the background.
    func dropAll() {
        state.withLock { state in
            for key in state.members.keys {
                state.members[key]?.joined = false
            }
        }
    }

    func join(topic: String, onBroadcast: @escaping @Sendable (String, Data) -> Void) async throws -> any RealtimeMembership {
        let id = UUID()
        let refused = state.withLock { state -> Bool in
            if state.refused.contains(where: { topic.hasPrefix($0) }) {
                return true
            }
            state.joinCount += 1
            state.members[id] = Member(topic: topic, deliver: onBroadcast)
            return false
        }
        if refused {
            throw RealtimeServiceError.joinFailed
        }
        return FakeMembership(id: id, topic: topic, transport: self)
    }

    func statuses() -> AsyncStream<TransportStatus> {
        status.stream
    }

    func refreshAuth() async {
        state.withLock { $0.authRefreshes += 1 }
    }

    func disconnect() async {
        state.withLock { $0.disconnects += 1 }
    }

    fileprivate func isJoined(_ id: UUID) -> Bool {
        state.withLock { $0.members[id]?.joined ?? false }
    }

    fileprivate func leave(_ id: UUID) {
        state.withLock { state in
            if let member = state.members.removeValue(forKey: id) {
                state.left.append(member.topic)
            }
        }
    }
}

private struct FakeMembership: RealtimeMembership {
    let id: UUID
    let topic: String
    let transport: FakeTransport

    var isJoined: Bool {
        transport.isJoined(id)
    }

    func leave() async {
        transport.leave(id)
    }
}

/// A session whose signed-in person can change.
final class RealtimeTestSession: SessionService {
    private let state: Broadcaster<SessionState>
    private let user: OSAllocatedUnfairLock<String?>

    init(userID: String?) {
        user = OSAllocatedUnfairLock(initialState: userID)
        state = Broadcaster(userID == nil ? .signedOut : .ready)
    }

    func signIn(as id: String) {
        user.withLock { $0 = id }
        state.send(.ready)
    }

    func endSession() {
        user.withLock { $0 = nil }
        state.send(.signedOut)
    }

    func states() -> AsyncStream<SessionState> {
        state.stream()
    }

    func profiles() -> AsyncStream<Me?> {
        AsyncStream { $0.finish() }
    }

    func currentProfile() async -> Me? {
        nil
    }

    func refreshProfile() async throws -> Me {
        throw APIError.unauthorized
    }

    func apply(_: Me) async {}

    func currentUserID() async -> String? {
        user.withLock { $0 }
    }

    func currentAccessToken() async throws -> String? {
        nil
    }

    func signInWithApple(idToken _: String, nonce _: String) async throws(SessionError) {}
    func sendEmailCode(to _: String) async throws(SessionError) {}
    func verifyEmailCode(_: String, email _: String) async throws(SessionError) {}
    #if DEBUG
        func signInForTesting(email _: String) async throws(SessionError) {}
    #endif
    func signOut() async {
        endSession()
    }
}

func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0 ..< 200 {
        if await condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}
