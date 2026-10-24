import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// The configured Glow API: base URL from config, the Bearer token from Session, retries when the
/// network drops, and 401/404/429 turned into `APIError`s.
///
/// Features get it from `Dependencies.api`. Once A2's generated client is in `Generated/`, call it
/// through `perform`, which hands you the generated `Client` and maps every failure to `APIError`:
///
/// ```swift
/// let me = try await dependencies.api.perform { try await $0.getMe() }
/// ```
///
/// In tests and previews, build one with `GlowAPI.mock(_:)` and a `MockTransport`.
public struct GlowAPI: Sendable {
    /// The API's base URL (`API_BASE_URL`): `http://localhost:3000` in Debug, `https://{DOMAIN}` in Release.
    public let serverURL: URL
    public let transport: any ClientTransport
    /// Outermost first: status mapping, then retries, then auth (so each retry gets a fresh token).
    public let middlewares: [any ClientMiddleware]

    public init(serverURL: URL, transport: any ClientTransport, middlewares: [any ClientMiddleware]) {
        self.serverURL = serverURL
        self.transport = transport
        self.middlewares = middlewares
    }

    /// The standard middleware stack, in order.
    public static func standardMiddlewares(
        baseURL: URL,
        tokens: any AccessTokenProvider,
        retry: RetryPolicy = .default,
    ) -> [any ClientMiddleware] {
        [
            StatusErrorMiddleware(),
            RetryMiddleware(policy: retry),
            AuthMiddleware(tokens: tokens, apiBaseURL: baseURL),
        ]
    }

    /// The real API over URLSession, with no response caching and no cookies.
    public static func live(baseURL: URL, tokens: any AccessTokenProvider, retry: RetryPolicy = .default) -> GlowAPI {
        let session = URLSession(configuration: .glowAPI)
        return GlowAPI(
            serverURL: baseURL,
            transport: URLSessionTransport(configuration: .init(session: session)),
            middlewares: standardMiddlewares(baseURL: baseURL, tokens: tokens, retry: retry),
        )
    }

    /// An API backed by a mock transport, with the same middlewares as the real one (minus retry delays).
    public static func mock(
        _ transport: MockTransport = .notImplemented,
        baseURL: URL = URL(string: "http://localhost:3000")!,
        tokens: any AccessTokenProvider = StaticAccessToken(nil),
    ) -> GlowAPI {
        GlowAPI(
            serverURL: baseURL,
            transport: transport,
            middlewares: standardMiddlewares(baseURL: baseURL, tokens: tokens, retry: .none),
        )
    }

    /// The generated client's configuration: ISO 8601 dates with or without fractional seconds.
    public static let configuration = Configuration(dateTranscoder: GlowDateTranscoder())

    /// Sends one raw request through the middlewares and the transport.
    ///
    /// An escape hatch for tests and for calls the generated client doesn't cover. Prefer `perform`.
    public func send(
        _ request: HTTPRequest,
        body: HTTPBody? = nil,
        operationID: String,
    ) async throws(APIError) -> (HTTPResponse, HTTPBody?) {
        let transport = transport
        var next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?) = { request, body, url in
            try await transport.send(request, body: body, baseURL: url, operationID: operationID)
        }
        for middleware in middlewares.reversed() {
            let inner = next
            next = { request, body, url in
                try await middleware.intercept(request, body: body, baseURL: url, operationID: operationID, next: inner)
            }
        }
        do {
            return try await next(request, body, serverURL)
        } catch {
            throw APIError(error)
        }
    }
}

/// A token provider that always returns the same token. For tests, previews and signed-out calls.
public struct StaticAccessToken: AccessTokenProvider {
    private let token: String?

    public init(_ token: String?) {
        self.token = token
    }

    public func currentAccessToken() async throws -> String? {
        token
    }
}

extension URLSessionConfiguration {
    /// Ephemeral, with no URL cache and no cookies: API responses and signed image links never
    /// touch the disk (spec: "Display with caching turned off").
    public static var glowAPI: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        return configuration
    }
}

#if GLOW_GENERATED_CLIENT
    extension GlowAPI {
        /// The generated OpenAPI client, wired to this API's transport and middlewares.
        public var client: Client {
            Client(serverURL: serverURL, configuration: Self.configuration, transport: transport, middlewares: middlewares)
        }

        /// Calls the generated client and maps every failure to an `APIError`.
        public func perform<Output: Sendable>(
            _ operation: (Client) async throws -> Output,
        ) async throws(APIError) -> Output {
            do {
                return try await operation(client)
            } catch {
                throw APIError(error)
            }
        }
    }
#endif
