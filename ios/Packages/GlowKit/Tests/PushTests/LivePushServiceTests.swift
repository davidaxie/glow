import APIClient
import AppCore
import Foundation
import HTTPTypes
import OpenAPIRuntime
import os
import Testing
@testable import Push

@Suite(.timeLimit(.minutes(1)))
struct LivePushServiceTests {
    static let tokenBytes = Data([0xAB, 0x01, 0xFF] + Array(repeating: 0x5C, count: 29))
    static let tokenHex = "ab01ff" + String(repeating: "5c", count: 29)

    @Test func uploadsTheTokenOnceForTheSignedInPerson() async throws {
        let server = FakeDeviceServer()
        let session = SwitchableSession(userID: "7e570000-0000-4000-8000-00000000000a")
        let push = LivePushService.test(server: server, session: session, system: FakePushSystem(.authorized))

        await push.didRegister(deviceToken: Self.tokenBytes)
        await push.didRegister(deviceToken: Self.tokenBytes)

        let registrations = server.registrations
        try #require(registrations.count == 1)
        #expect(registrations[0] == [
            "apnsToken": Self.tokenHex,
            "environment": "sandbox",
            "appVersion": "1.0 (7)",
        ])
    }

    @Test func waitsForSignInBeforeUploading() async {
        let server = FakeDeviceServer()
        let session = SwitchableSession(userID: nil)
        let push = LivePushService.test(server: server, session: session, system: FakePushSystem(.authorized))

        await push.didRegister(deviceToken: Self.tokenBytes)
        #expect(server.registrations.isEmpty)

        session.signIn(as: "7e570000-0000-4000-8000-00000000000a")
        #expect(await eventually { server.registrations.count == 1 })
    }

    @Test func uploadsAgainForTheNextPersonAfterSignOut() async {
        let server = FakeDeviceServer()
        let session = SwitchableSession(userID: "7e570000-0000-4000-8000-00000000000a")
        let push = LivePushService.test(server: server, session: session, system: FakePushSystem(.authorized))
        await push.didRegister(deviceToken: Self.tokenBytes)

        await push.unregister()
        session.endSession()
        session.signIn(as: "7e570000-0000-4000-8000-00000000000b")

        #expect(await eventually { server.registrations.count == 2 })
        #expect(server.deletions == ["d0000000-0000-4000-8000-000000000001"])
    }

    @Test func unregisterDeletesOnlyWhatItRegistered() async {
        let server = FakeDeviceServer()
        let session = SwitchableSession(userID: "7e570000-0000-4000-8000-00000000000a")
        let push = LivePushService.test(server: server, session: session, system: FakePushSystem(.authorized))

        await push.unregister()
        #expect(server.deletions.isEmpty)

        await push.didRegister(deviceToken: Self.tokenBytes)
        await push.unregister()
        await push.unregister()
        #expect(server.deletions == ["d0000000-0000-4000-8000-000000000001"])
    }

    @Test func retriesAFailedUploadWhenTheAppIsNextActive() async {
        let server = FakeDeviceServer(failFirst: true)
        let session = SwitchableSession(userID: "7e570000-0000-4000-8000-00000000000a")
        let system = FakePushSystem(.authorized)
        let push = LivePushService.test(server: server, session: session, system: system)

        await push.didRegister(deviceToken: Self.tokenBytes)
        system.becomeActive()
        #expect(await eventually { server.registrations.count == 1 })
        #expect(server.attempts >= 2)
    }

    @Test func asksAppleForATokenAtLaunchOnlyWhenAllowed() async {
        let allowed = FakePushSystem(.authorized)
        let denied = FakePushSystem(.denied)
        let session = SwitchableSession(userID: nil)
        let first = LivePushService.test(server: FakeDeviceServer(), session: session, system: allowed)
        let second = LivePushService.test(server: FakeDeviceServer(), session: session, system: denied)

        #expect(await eventually { allowed.tokenRequests == 1 })
        #expect(allowed.categoriesRegistered)
        #expect(denied.categoriesRegistered)
        #expect(denied.tokenRequests == 0)
        _ = (first, second)
    }

    @Test func requestingPermissionRegistersWhenAllowed() async throws {
        let system = FakePushSystem(.notDetermined, answer: .authorized)
        let push = LivePushService.test(server: FakeDeviceServer(), session: SwitchableSession(userID: nil), system: system)

        #expect(try await push.requestAuthorization() == .authorized)
        #expect(system.prompts == 1)
        #expect(await eventually { system.tokenRequests >= 1 })
    }

    @Test func requestingPermissionDoesNothingMoreWhenDenied() async throws {
        let system = FakePushSystem(.notDetermined, answer: .denied)
        let push = LivePushService.test(server: FakeDeviceServer(), session: SwitchableSession(userID: nil), system: system)

        #expect(try await push.requestAuthorization() == .denied)
        try await Task.sleep(for: .milliseconds(50))
        #expect(system.tokenRequests == 0)
    }

    @Test func xcodeBuildsAreSandboxAndTestFlightIsProduction() {
        var config = AppConfig.preview
        #expect(PushModule.apnsEnvironment(for: config) == .sandbox)
        config.environment = .release
        #expect(PushModule.apnsEnvironment(for: config) == .production)
    }

    @Test func foregroundNotificationsOfOursShowAsBanners() throws {
        let push = LivePushService.test(
            server: FakeDeviceServer(),
            session: SwitchableSession(userID: nil),
            system: FakePushSystem(.denied),
        )
        let ours = try PushFixtures.notification("message_created")
        let other = PushNotification(categoryIdentifier: "", payload: Data(#"{"aps":{"alert":"hi"}}"#.utf8))
        #expect(push.foregroundPresentation(for: ours) == [.banner, .list, .sound])
        #expect(push.foregroundPresentation(for: other) == [.list])
        #expect(push.route(for: ours) == .chat(PushRoutingTests.match))
    }
}

// MARK: - Fakes

extension LivePushService {
    static func test(server: FakeDeviceServer, session: any SessionService, system: FakePushSystem) -> LivePushService {
        LivePushService(
            api: .mock(server.transport),
            session: session,
            environment: .sandbox,
            appVersion: "1.0 (7)",
            analytics: NoopAnalytics(),
            system: system,
        )
    }
}

/// Answers `registerDevice` and `deleteDevice` like the server, and records what it was sent.
final class FakeDeviceServer: Sendable {
    private struct State {
        var registrations: [[String: String]] = []
        var deletions: [String] = []
        var attempts = 0
        var failNext: Bool
    }

    private let state: OSAllocatedUnfairLock<State>

    init(failFirst: Bool = false) {
        state = OSAllocatedUnfairLock(initialState: State(failNext: failFirst))
    }

    var registrations: [[String: String]] {
        state.withLock { $0.registrations }
    }

    var deletions: [String] {
        state.withLock { $0.deletions }
    }

    var attempts: Int {
        state.withLock { $0.attempts }
    }

    var transport: MockTransport {
        MockTransport { [self] request, body, _, operationID in
            switch operationID {
            case "registerDevice":
                var data = Data()
                if let body {
                    data = try await Data(collecting: body, upTo: 4096)
                }
                let json = try JSONSerialization.jsonObject(with: data) as? [String: String] ?? [:]
                let fail = state.withLock { state in
                    state.attempts += 1
                    defer { state.failNext = false }
                    if !state.failNext {
                        state.registrations.append(json)
                    }
                    return state.failNext
                }
                if fail {
                    return (HTTPResponse(status: .serviceUnavailable), nil)
                }
                var fields = HTTPFields()
                fields[.contentType] = "application/json"
                let reply = Data(#"{"id":"d0000000-0000-4000-8000-000000000001"}"#.utf8)
                return (HTTPResponse(status: .created, headerFields: fields), HTTPBody(reply))
            case "deleteDevice":
                let id = String(request.path?.split(separator: "/").last ?? "")
                state.withLock { $0.deletions.append(id) }
                return (HTTPResponse(status: .noContent), nil)
            default:
                return (HTTPResponse(status: .notImplemented), nil)
            }
        }
    }
}

final class FakePushSystem: PushSystem {
    private struct State {
        var status: PushAuthorization
        var answer: PushAuthorization
        var tokenRequests = 0
        var prompts = 0
        var categoriesRegistered = false
    }

    private let state: OSAllocatedUnfairLock<State>
    private let active = AsyncStream<Void>.makeStream()

    init(_ status: PushAuthorization, answer: PushAuthorization = .authorized) {
        state = OSAllocatedUnfairLock(initialState: State(status: status, answer: answer))
    }

    var tokenRequests: Int {
        state.withLock { $0.tokenRequests }
    }

    var prompts: Int {
        state.withLock { $0.prompts }
    }

    var categoriesRegistered: Bool {
        state.withLock { $0.categoriesRegistered }
    }

    func becomeActive() {
        active.continuation.yield()
    }

    func authorizationStatus() async -> PushAuthorization {
        state.withLock { $0.status }
    }

    func requestAuthorization() async throws -> Bool {
        state.withLock { state in
            state.prompts += 1
            state.status = state.answer
            return state.answer == .authorized
        }
    }

    func registerCategories() {
        state.withLock { $0.categoriesRegistered = true }
    }

    @MainActor func registerForRemoteNotifications() {
        state.withLock { $0.tokenRequests += 1 }
    }

    func becameActive() -> AsyncStream<Void> {
        active.stream
    }
}

/// A session whose signed-in person can change, for sign-out and sign-in tests.
final class SwitchableSession: SessionService {
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
        user.withLock { $0 }.map { _ in "test-access-token" }
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

/// Waits up to two seconds for `condition`.
func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0 ..< 200 {
        if await condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}
