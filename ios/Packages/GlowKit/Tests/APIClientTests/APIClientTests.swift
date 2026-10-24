import Foundation
import HTTPTypes
import OpenAPIRuntime
import os
import Testing
@testable import APIClient

/// Records every request the transport sees, and answers from a script.
final class ScriptedTransport: ClientTransport, @unchecked Sendable {
    enum Step {
        case fail(URLError.Code)
        case respond(Int)
    }

    private let state: OSAllocatedUnfairLock<(steps: [Step], requests: [HTTPRequest])>

    init(_ steps: [Step]) {
        state = OSAllocatedUnfairLock(uncheckedState: (steps, []))
    }

    var requests: [HTTPRequest] {
        state.withLockUnchecked { $0.requests }
    }

    func send(_ request: HTTPRequest, body _: HTTPBody?, baseURL _: URL, operationID _: String) async throws -> (HTTPResponse, HTTPBody?) {
        let step = state.withLockUnchecked { state -> Step in
            state.requests.append(request)
            return state.steps.isEmpty ? .respond(200) : state.steps.removeFirst()
        }
        switch step {
        case let .fail(code): throw URLError(code)
        case let .respond(status): return (HTTPResponse(status: .init(code: status)), nil)
        }
    }
}

struct APIClientTests {
    let base = URL(string: "http://localhost:3000")!

    func api(_ transport: ScriptedTransport, token: String? = "access-token") -> GlowAPI {
        GlowAPI(
            serverURL: base,
            transport: transport,
            middlewares: [
                StatusErrorMiddleware(),
                RetryMiddleware(policy: .default, sleep: { _ in }),
                AuthMiddleware(tokens: StaticAccessToken(token), apiBaseURL: base),
            ],
        )
    }

    func request(_ method: HTTPRequest.Method, _ path: String = "/api/me") -> HTTPRequest {
        HTTPRequest(method: method, scheme: nil, authority: nil, path: path)
    }

    // MARK: Auth

    @Test func addsTheBearerToken() async throws {
        let transport = ScriptedTransport([])
        _ = try await api(transport).send(request(.get), operationID: "getMe")
        #expect(transport.requests.first?.headerFields[.authorization] == "Bearer access-token")
    }

    @Test func signedOutSendsNoToken() async throws {
        let transport = ScriptedTransport([])
        _ = try await api(transport, token: nil).send(request(.get), operationID: "getMe")
        #expect(transport.requests.first?.headerFields[.authorization] == nil)
    }

    @Test func neverSendsTheTokenToAnotherHost() async throws {
        let transport = ScriptedTransport([])
        let middleware = AuthMiddleware(tokens: StaticAccessToken("access-token"), apiBaseURL: base)
        _ = try await middleware.intercept(
            request(.get),
            body: nil,
            baseURL: #require(URL(string: "https://elsewhere.example")),
            operationID: "x",
        ) { request, body, url in
            try await transport.send(request, body: body, baseURL: url, operationID: "x")
        }
        #expect(transport.requests.first?.headerFields[.authorization] == nil)
    }

    // MARK: Status codes

    @Test(arguments: [(404, APIError.notFound), (401, .unauthorized), (429, .rateLimited)])
    func sharedStatusesBecomeErrors(status: Int, expected: APIError) async {
        let transport = ScriptedTransport([.respond(status)])
        await #expect(throws: expected) {
            try await api(transport).send(request(.get), operationID: "getMe")
        }
    }

    @Test func otherStatusesPassThrough() async throws {
        let transport = ScriptedTransport([.respond(409)])
        let (response, _) = try await api(transport).send(request(.post), operationID: "x")
        #expect(response.status.code == 409)
    }

    @Test func notFoundSurvivesClientErrorWrapping() {
        let wrapped = ClientError(
            operationID: "getMatch",
            operationInput: "input",
            request: nil,
            requestBody: nil,
            baseURL: nil,
            response: HTTPResponse(status: .notFound),
            responseBody: nil,
            causeDescription: "Middleware threw",
            underlyingError: APIError.notFound,
        )
        #expect(APIError(wrapped) == .notFound)
    }

    // MARK: Retries

    @Test func retriesAnyRequestThatNeverLeftThePhone() async throws {
        let transport = ScriptedTransport([.fail(.notConnectedToInternet), .fail(.cannotConnectToHost), .respond(200)])
        _ = try await api(transport).send(request(.post, "/api/rooms/x/taps"), operationID: "tap")
        #expect(transport.requests.count == 3)
    }

    @Test func retriesGetsWhenTheConnectionDrops() async throws {
        let transport = ScriptedTransport([.fail(.networkConnectionLost), .respond(200)])
        _ = try await api(transport).send(request(.get), operationID: "getMe")
        #expect(transport.requests.count == 2)
    }

    @Test func neverResendsAPostThatMightHaveLanded() async {
        let transport = ScriptedTransport([.fail(.networkConnectionLost), .respond(200)])
        await #expect(throws: APIError.offline) {
            try await api(transport).send(request(.post, "/api/matches/x/messages"), operationID: "sendMessage")
        }
        #expect(transport.requests.count == 1)
    }

    @Test func resendsAPostWithAnIdempotencyKey() async throws {
        let transport = ScriptedTransport([.fail(.timedOut), .respond(200)])
        var post = request(.post, "/api/matches/x/messages")
        post.headerFields[RetryMiddleware.idempotencyKey] = "k1"
        _ = try await api(transport).send(post, operationID: "sendMessage")
        #expect(transport.requests.count == 2)
    }

    @Test func givesUpAfterThreeAttempts() async {
        let transport = ScriptedTransport([
            .fail(.notConnectedToInternet),
            .fail(.notConnectedToInternet),
            .fail(.notConnectedToInternet),
            .respond(200),
        ])
        await #expect(throws: APIError.offline) {
            try await api(transport).send(request(.get), operationID: "getMe")
        }
        #expect(transport.requests.count == 3)
    }

    @Test func retriesAGetThatGot503() async throws {
        let transport = ScriptedTransport([.respond(503), .respond(200)])
        let (response, _) = try await api(transport).send(request(.get), operationID: "getMe")
        #expect(response.status == .ok)
        #expect(transport.requests.count == 2)
    }

    @Test func neverResendsAPostThatGot503() async throws {
        let transport = ScriptedTransport([.respond(503), .respond(200)])
        let (response, _) = try await api(transport).send(request(.post, "/api/rooms/x/taps"), operationID: "tap")
        #expect(response.status.code == 503)
        #expect(transport.requests.count == 1)
    }

    @Test func backoffGrowsAndCaps() {
        let policy = RetryPolicy.default
        #expect(policy.delay(afterAttempt: 1) == .milliseconds(400))
        #expect(policy.delay(afterAttempt: 2) == .milliseconds(800))
        #expect(policy.delay(afterAttempt: 10) == .seconds(3))
    }

    // MARK: Dates and mocks

    @Test func datesWithAndWithoutFractions() throws {
        let transcoder = GlowDateTranscoder()
        let whole = try transcoder.decode("2026-10-23T18:00:00Z")
        let fractional = try transcoder.decode("2026-10-23T18:00:00.250Z")
        #expect(fractional.timeIntervalSince(whole) == 0.25)
        #expect(throws: (any Error).self) { try transcoder.decode("yesterday") }
    }

    @Test func mockTransportAnswersByOperation() async throws {
        let api = GlowAPI.mock(.responses(["getMe": .json(#"{"ok":true}"#)]))
        let (response, body) = try await api.send(request(.get), operationID: "getMe")
        #expect(response.status == .ok)
        let data = try await Data(collecting: #require(body), upTo: 1024)
        #expect(String(decoding: data, as: UTF8.self) == #"{"ok":true}"#)
        let (unknown, _) = try await api.send(request(.get), operationID: "unknown")
        #expect(unknown.status == .notImplemented)
    }
}
