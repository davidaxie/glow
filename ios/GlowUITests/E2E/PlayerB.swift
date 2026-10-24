import Foundation

/// Person B, as scripts/e2e/player-b.ts reports them. Never anyone's user ID or name.
struct PlayerBState: Decodable {
    struct GlowSummary: Decodable {
        let status: String
        let color: String
        let codeWord: String
        let meetingSpot: String?
    }

    let step: String
    let cardId: String?
    let tappedCardId: String?
    let matchId: String?
    let matchStatus: String?
    let glow: GlowSummary?
    let messages: [String]?
    let violations: [String]
}

/// Tells person B what to do next and waits until they've done it. Each step answers B's state
/// afterwards; a failed step, or anything B saw that it never should (P1), throws.
struct PlayerB {
    let base: URL

    /// Steps player-b.ts takes: tap, match, find, chat, glow, met, metboth, say, read, block,
    /// unmatch, ended, leave (`node scripts/e2e/player-b.ts --help`).
    @discardableResult
    func run(_ step: String, text: String? = nil) async throws -> PlayerBState {
        var url = base.appending(path: "do/\(step)")
        if let text { url.append(queryItems: [URLQueryItem(name: "text", value: text)]) }
        return try await decode(MacHelper.post(url, timeout: 150))
    }

    func state() async throws -> PlayerBState {
        try await decode(MacHelper.get(base.appending(path: "state")))
    }

    private func decode(_ data: Data) throws -> PlayerBState {
        let state = try JSONDecoder().decode(PlayerBState.self, from: data)
        if !state.violations.isEmpty {
            throw MacHelper.Failure(description: "P1: person B saw \(state.violations.joined(separator: "; "))")
        }
        return state
    }
}
