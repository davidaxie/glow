import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Supplies the Supabase access token for the `Authorization: Bearer` header.
/// Session (B1) implements this through AppCore's `SessionService`.
public protocol AccessTokenProvider: Sendable {
    /// The current access token, refreshed if needed, or nil when signed out.
    func currentAccessToken() async throws -> String?
}

// MARK: - Auth

/// Adds `Authorization: Bearer <token>` to requests bound for the Glow API, and to nothing else.
public struct AuthMiddleware: ClientMiddleware {
    private let tokens: any AccessTokenProvider
    private let apiOrigin: Origin

    public init(tokens: any AccessTokenProvider, apiBaseURL: URL) {
        self.tokens = tokens
        apiOrigin = Origin(apiBaseURL)
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?),
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        // Never send someone's token to a host that isn't our API.
        if Origin(baseURL) == apiOrigin, let token = try await tokens.currentAccessToken(), !token.isEmpty {
            request.headerFields[.authorization] = "Bearer \(token)"
        } else {
            request.headerFields[.authorization] = nil
        }
        return try await next(request, body, baseURL)
    }

    struct Origin: Equatable {
        let scheme: String?
        let host: String?
        let port: Int?

        init(_ url: URL) {
            scheme = url.scheme?.lowercased()
            host = url.host()?.lowercased()
            port = url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
        }
    }
}

// MARK: - Status codes

/// Turns the statuses every endpoint shares into thrown `APIError`s, so features handle them once:
/// 404 is `.notFound` (P11), 401 is `.unauthorized`, 429 is `.rateLimited`.
public struct StatusErrorMiddleware: ClientMiddleware {
    public init() {}

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?),
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        switch response.status.code {
        case 401: throw APIError.unauthorized
        case 404: throw APIError.notFound
        case 429: throw APIError.rateLimited
        default: return (response, responseBody)
        }
    }
}

// MARK: - Retries

/// How many times to retry when the network drops, and how long to wait in between.
public struct RetryPolicy: Sendable, Hashable {
    /// Total attempts, including the first one.
    public var maxAttempts: Int
    public var initialDelay: Duration
    public var maxDelay: Duration

    public init(maxAttempts: Int, initialDelay: Duration, maxDelay: Duration) {
        self.maxAttempts = max(1, maxAttempts)
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
    }

    public static let `default` = RetryPolicy(maxAttempts: 3, initialDelay: .milliseconds(400), maxDelay: .seconds(3))
    public static let none = RetryPolicy(maxAttempts: 1, initialDelay: .zero, maxDelay: .zero)

    /// Exponential backoff: initialDelay, 2x, 4x, … capped at maxDelay.
    public func delay(afterAttempt attempt: Int) -> Duration {
        let factor = 1 << min(max(attempt - 1, 0), 16)
        return min(initialDelay * factor, maxDelay)
    }
}

/// Retries a request when the network drops, without ever sending a non-idempotent request twice
/// if it might already have reached the server.
///
/// - Errors that mean the request never left the phone (offline, host not found, can't connect)
///   are retried for every method.
/// - Errors that leave it unclear (connection lost mid-request, timed out) are retried only for
///   GET, HEAD, PUT, DELETE and OPTIONS, or when the request carries an `Idempotency-Key` header.
/// - A 503 (the server says try again) is retried under the same idempotency rule, waiting for its
///   `Retry-After` (capped at `maxDelay`). No other status is retried.
/// - Bodies that can only be read once (streams) are never retried.
public struct RetryMiddleware: ClientMiddleware {
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    private let policy: RetryPolicy
    private let sleep: Sleep

    public init(policy: RetryPolicy = .default, sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.policy = policy
        self.sleep = sleep
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?),
    ) async throws -> (HTTPResponse, HTTPBody?) {
        if let body, body.iterationBehavior == .single {
            return try await next(request, body, baseURL)
        }
        var attempt = 1
        while true {
            let response: HTTPResponse
            let responseBody: HTTPBody?
            do {
                (response, responseBody) = try await next(request, body, baseURL)
            } catch {
                guard attempt < policy.maxAttempts, Self.shouldRetry(error, request: request) else { throw error }
                try await sleep(policy.delay(afterAttempt: attempt))
                attempt += 1
                continue
            }
            guard response.status.code == 503, attempt < policy.maxAttempts, Self.isSafeToResend(request) else {
                return (response, responseBody)
            }
            try await sleep(retryAfter(response) ?? policy.delay(afterAttempt: attempt))
            attempt += 1
        }
    }

    static let idempotencyKey = HTTPField.Name("Idempotency-Key")!

    static func isSafeToResend(_ request: HTTPRequest) -> Bool {
        request.method.isIdempotent || request.headerFields[idempotencyKey] != nil
    }

    /// `Retry-After` in seconds, capped at the policy's longest wait.
    private func retryAfter(_ response: HTTPResponse) -> Duration? {
        guard let value = response.headerFields[.retryAfter], let seconds = Int(value), seconds >= 0 else { return nil }
        return min(.seconds(seconds), policy.maxDelay)
    }

    static func shouldRetry(_ error: any Error, request: HTTPRequest) -> Bool {
        guard let urlError = APIError.rootCause(of: error) as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .dataNotAllowed, .internationalRoamingOff:
            return true
        case .networkConnectionLost, .timedOut:
            return isSafeToResend(request)
        default:
            return false
        }
    }
}

extension HTTPRequest.Method {
    var isIdempotent: Bool {
        switch self {
        case .get, .head, .put, .delete, .options, .trace: true
        default: false
        }
    }
}
