import Foundation
import HTTPTypes
import OpenAPIRuntime

/// A transport for tests and previews that answers from a closure instead of the network.
///
/// ```swift
/// let api = GlowAPI.mock(.responses(["getMe": .json(#"{"first_name":"Robin"}"#)]))
/// ```
public struct MockTransport: ClientTransport {
    public typealias Handler = @Sendable (
        _ request: HTTPRequest,
        _ body: HTTPBody?,
        _ baseURL: URL,
        _ operationID: String,
    ) async throws -> (HTTPResponse, HTTPBody?)

    private let handler: Handler

    public init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    public func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
    ) async throws -> (HTTPResponse, HTTPBody?) {
        try await handler(request, body, baseURL, operationID)
    }

    /// One canned response.
    public struct Response: Sendable {
        public var status: HTTPResponse.Status
        public var body: Data?
        public var contentType: String?

        public init(status: HTTPResponse.Status, body: Data? = nil, contentType: String? = nil) {
            self.status = status
            self.body = body
            self.contentType = contentType
        }

        public static func json(_ json: String, status: HTTPResponse.Status = .ok) -> Response {
            Response(status: status, body: Data(json.utf8), contentType: "application/json")
        }

        public static func status(_ status: HTTPResponse.Status) -> Response {
            Response(status: status)
        }
    }

    /// Answers each operation ID with a canned response, and anything else with `fallback`.
    public static func responses(
        _ responses: [String: Response],
        fallback: Response = .status(.notImplemented),
    ) -> MockTransport {
        MockTransport { _, _, _, operationID in
            let response = responses[operationID] ?? fallback
            var fields = HTTPFields()
            if let contentType = response.contentType {
                fields[.contentType] = contentType
            }
            return (HTTPResponse(status: response.status, headerFields: fields), response.body.map { HTTPBody($0) })
        }
    }

    /// Answers every request with 501, like the server stubs before their owners fill them in.
    public static let notImplemented = MockTransport.responses([:])
}
