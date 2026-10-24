import APIClient
import AppCore
import Foundation
import HTTPTypes
import OpenAPIRuntime
import os
@testable import Session

/// A Supabase stand-in: signs in whoever asks, and records what it was asked.
final class FakeAuthBackend: AuthBackend {
    struct State {
        var userID: String?
        var calls: [String] = []
        var failNext: SessionError?
    }

    private let state: OSAllocatedUnfairLock<State>
    private let ended = AsyncStream<Void>.makeStream()

    init(signedInAs userID: String? = nil) {
        state = OSAllocatedUnfairLock(initialState: State(userID: userID))
    }

    var calls: [String] {
        state.withLock { $0.calls }
    }

    func failNext(_ error: SessionError) {
        state.withLock { $0.failNext = error }
    }

    func endSessionRemotely() {
        state.withLock { $0.userID = nil }
        ended.continuation.yield()
    }

    private func record(_ call: String, signIn userID: String? = nil) throws(SessionError) {
        let failure: SessionError? = state.withLock { state in
            state.calls.append(call)
            if let failure = state.failNext {
                state.failNext = nil
                return failure
            }
            if let userID {
                state.userID = userID
            }
            return nil
        }
        if let failure {
            throw failure
        }
    }

    func currentUserID() -> String? {
        state.withLock { $0.userID }
    }

    func accessToken() async -> String? {
        currentUserID().map { "token-for-\($0)" }
    }

    func signInWithApple(idToken _: String, nonce _: String) async throws(SessionError) {
        try record("apple", signIn: TestData.userID)
    }

    func sendEmailCode(to email: String) async throws(SessionError) {
        try record("send:\(email)")
    }

    func verifyEmailCode(_ code: String, email: String) async throws(SessionError) {
        try record("verify:\(code):\(email)", signIn: TestData.userID)
    }

    func adopt(accessToken _: String, refreshToken _: String) async throws(SessionError) {
        try record("adopt", signIn: TestData.userID)
    }

    func signOut() async {
        state.withLock {
            $0.calls.append("signOut")
            $0.userID = nil
        }
    }

    func sessionEnded() -> AsyncStream<Void> {
        ended.stream
    }
}

/// Records which operations an API mock was asked for, and answers from a table.
final class APIRecorder: Sendable {
    private let log = OSAllocatedUnfairLock<[String]>(initialState: [])
    private let answers: OSAllocatedUnfairLock<[String: MockTransport.Response]>

    init(_ answers: [String: MockTransport.Response] = [:]) {
        self.answers = OSAllocatedUnfairLock(initialState: answers)
    }

    var operations: [String] {
        log.withLock { $0 }
    }

    func set(_ operationID: String, _ response: MockTransport.Response) {
        answers.withLock { $0[operationID] = response }
    }

    var api: GlowAPI {
        GlowAPI.mock(MockTransport { [self] _, _, _, operationID in
            log.withLock { $0.append(operationID) }
            let response = answers.withLock { $0[operationID] } ?? .status(.notImplemented)
            var fields = HTTPFields()
            if let contentType = response.contentType {
                fields[.contentType] = contentType
            }
            return (HTTPResponse(status: response.status, headerFields: fields), response.body.map { HTTPBody($0) })
        })
    }
}

enum TestData {
    static let userID = "7e570000-0000-4000-8000-0000000000b1"

    static func me(_ step: Components.Schemas.OnboardingStep, id: String = userID) -> Me {
        var me = Me.preview(step: step)
        me.id = id
        return me
    }

    static func json(_ me: Me) -> MockTransport.Response {
        let data = try! JSONEncoder().encode(me) // swiftlint:disable:this force_try
        return MockTransport.Response(status: .ok, body: data, contentType: "application/json")
    }

    static func error(_ status: HTTPResponse.Status, _ code: String, reason: String? = nil) -> MockTransport.Response {
        let reasonJSON = reason.map { #","reason":"\#($0)""# } ?? ""
        return .json(#"{"error":{"code":"\#(code)","message":"x"\#(reasonJSON)}}"#, status: status)
    }

    static let photo = MockTransport.Response.json(
        #"{"id":"0f0f0f0f-0000-4000-8000-0000000000b1","position":0,"moderationStatus":"approved","url":"/api/me/photos/0f0f0f0f-0000-4000-8000-0000000000b1"}"#,
        status: .created,
    )

    static let heldPhoto = MockTransport.Response.json(
        #"{"id":"0f0f0f0f-0000-4000-8000-0000000000b2","position":1,"moderationStatus":"held","url":"/api/me/photos/0f0f0f0f-0000-4000-8000-0000000000b2"}"#,
        status: .created,
    )

    /// A step memory no other test touches.
    static func memory() -> StepMemory {
        StepMemory(key: "test.lastStep.\(UUID().uuidString)")
    }
}

/// Waits until `condition` holds, for state that settles on another task.
func eventually(_ condition: @escaping @Sendable () async -> Bool) async -> Bool {
    for _ in 0 ..< 200 {
        if await condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}
