import APIClient
import AppCore
import Foundation

// Owner: C3. The three glow calls, behind a protocol so the screen can be tested and previewed.

/// How a glow can end from this phone.
public enum GlowEnding: String, Sendable {
    /// End glow: the glow ends for both, and the chat opens.
    case cancel
    /// Switch to chat: the same ending, said as "let's just talk".
    case switchToChat = "switch_to_chat"
}

/// `GET /api/matches/{id}/glow`, `POST …/glow/met` and `POST …/glow/cancel`.
///
/// Every failure is an `APIError`. `.notFound` means the glow is gone or was never mine (P11).
public protocol GlowClient: Sendable {
    func glow(for match: MatchID) async throws(APIError) -> GlowSession
    func markMet(_ match: MatchID) async throws(APIError) -> GlowSession
    func end(_ match: MatchID, as ending: GlowEnding) async throws(APIError) -> GlowSession
}

/// The real API, through the generated client and A3's wrapper (token, retries, 404 mapping).
public struct LiveGlowClient: GlowClient {
    private let api: GlowAPI

    public init(api: GlowAPI) {
        self.api = api
    }

    public func glow(for match: MatchID) async throws(APIError) -> GlowSession {
        try await api.perform { client in
            try await GlowSession(client.getGlow(path: .init(id: match.rawValue)).ok.body.json)
        }
    }

    public func markMet(_ match: MatchID) async throws(APIError) -> GlowSession {
        try await api.perform { client in
            try await GlowSession(client.markGlowMet(path: .init(id: match.rawValue)).ok.body.json)
        }
    }

    public func end(_ match: MatchID, as ending: GlowEnding) async throws(APIError) -> GlowSession {
        let reason: Components.Schemas.GlowCancelRequest.ReasonPayload = switch ending {
        case .cancel: .cancel
        case .switchToChat: .switchToChat
        }
        return try await api.perform { client in
            try await GlowSession(
                client.cancelGlow(path: .init(id: match.rawValue), body: .json(.init(reason: reason))).ok.body.json,
            )
        }
    }
}
