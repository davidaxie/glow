import Foundation
import OpenAPIRuntime

/// The errors every API call can end in, after the wrapper's middlewares have run.
///
/// Never log or report a raw `ClientError` from the generated client: its description includes
/// the full request, headers and all. Turn it into an `APIError` first (`GlowAPI.perform` and
/// `GlowAPI.send` already do).
public enum APIError: Error, Sendable, Hashable {
    /// 404. The thing doesn't exist, or you aren't allowed to see it. The server never says which (P11).
    case notFound
    /// 401. The session is missing or expired. Session decides whether to refresh or sign out.
    case unauthorized
    /// 429. Slow down and try again later.
    case rateLimited
    /// The network dropped and the retries ran out.
    case offline
    /// The caller's task was cancelled.
    case cancelled
    /// Anything else: an undecodable response, an unexpected status, a transport failure.
    /// Carries the status code when there was a response, and nothing that could hold personal data.
    case unexpected(status: Int?)

    /// Maps any error thrown while calling the API onto an `APIError`.
    public init(_ error: any Error) {
        if let apiError = error as? APIError {
            self = apiError
            return
        }
        if let clientError = error as? ClientError {
            let mapped = APIError(clientError.underlyingError)
            if case .unexpected(status: nil) = mapped, let status = clientError.response?.status.code {
                self = .unexpected(status: status)
            } else {
                self = mapped
            }
            return
        }
        if error is CancellationError {
            self = .cancelled
            return
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                self = .cancelled
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
                 .dnsLookupFailed, .timedOut, .dataNotAllowed, .internationalRoamingOff:
                self = .offline
            default:
                self = .unexpected(status: nil)
            }
            return
        }
        self = .unexpected(status: nil)
    }
}

extension APIError {
    /// Digs through `ClientError` wrapping to the error a transport or middleware actually threw.
    static func rootCause(of error: any Error) -> any Error {
        var current = error
        while let clientError = current as? ClientError {
            current = clientError.underlyingError
        }
        return current
    }
}
