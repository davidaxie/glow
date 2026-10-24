import Foundation

/// A session that never talks to Supabase. Starts in whatever state you give it.
///
/// Until B1's Supabase session lands, the app runs on this one in the `.ready` state.
public final class PreviewSessionService: SessionService {
    private let state: Broadcaster<SessionState>
    private let userID: String?

    public init(state: SessionState = .ready, userID: String? = "00000000-0000-4000-8000-00000000000a") {
        self.state = Broadcaster(state)
        self.userID = userID
    }

    /// Moves to a new state, as if the person signed in, finished a step or signed out.
    public func set(_ newState: SessionState) {
        state.send(newState)
    }

    public var current: SessionState {
        state.value
    }

    public func states() -> AsyncStream<SessionState> {
        state.stream()
    }

    public func currentUserID() async -> String? {
        switch state.value {
        case .onboarding, .ready: userID
        case .restoring, .signedOut: nil
        }
    }

    /// No token: the mock session has nothing the real API would accept.
    public func currentAccessToken() async throws -> String? {
        nil
    }

    public func signInWithApple(idToken _: String, nonce _: String) async throws {
        state.send(.onboarding(.profile))
    }

    public func sendEmailCode(to _: String) async throws {}

    public func verifyEmailCode(_: String, email _: String) async throws {
        state.send(.onboarding(.profile))
    }

    public func signOut() async {
        state.send(.signedOut)
    }
}
