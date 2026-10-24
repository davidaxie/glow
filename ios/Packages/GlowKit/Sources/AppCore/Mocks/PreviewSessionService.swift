import APIClient
import Foundation

// Owner: B1 (Session). Change this file and Services/SessionService.swift together.

/// A session that never talks to Supabase or the API. Starts in whatever state you give it.
///
/// Previews, tests and other modules' mocks use this one. Signing in moves to the profile step;
/// `apply(_:)` follows the profile's onboarding step, like the real session.
public final class PreviewSessionService: SessionService {
    private let state: Broadcaster<SessionState>
    private let profile: Broadcaster<Me?>
    private let userID: String?

    public init(
        state: SessionState = .ready,
        userID: String? = "00000000-0000-4000-8000-00000000000a",
        profile: Me? = nil,
    ) {
        self.state = Broadcaster(state)
        self.userID = userID
        let signedIn = switch state {
        case .onboarding, .ready: true
        case .restoring, .signedOut: false
        }
        let start = profile ?? (signedIn ? Me.preview(step: Self.serverStep(for: state)) : nil)
        self.profile = Broadcaster(start)
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

    public func profiles() -> AsyncStream<Me?> {
        profile.stream()
    }

    public func currentProfile() async -> Me? {
        profile.value
    }

    public func refreshProfile() async throws -> Me {
        guard let me = profile.value else { throw APIError.unauthorized }
        return me
    }

    public func apply(_ me: Me) async {
        profile.send(me)
        state.send(SessionState(serverStep: me.onboardingStep))
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

    public func signInWithApple(idToken _: String, nonce _: String) async throws(SessionError) {
        signIn()
    }

    public func sendEmailCode(to _: String) async throws(SessionError) {}

    public func verifyEmailCode(_: String, email _: String) async throws(SessionError) {
        signIn()
    }

    #if DEBUG
        public func signInForTesting(email _: String) async throws(SessionError) {
            signIn()
        }
    #endif

    public func signOut() async {
        profile.send(nil)
        state.send(.signedOut)
    }

    private func signIn() {
        profile.send(.preview(step: .profile))
        state.send(.onboarding(.profile))
    }

    private static func serverStep(for state: SessionState) -> Components.Schemas.OnboardingStep {
        switch state {
        case .ready: .complete
        case .onboarding(.photos): .photos
        case .onboarding(.notifications): .notifications
        case .onboarding, .restoring, .signedOut: .profile
        }
    }
}

extension Me {
    /// A made-up profile for previews and tests. Not a real person.
    public static func preview(
        step: Components.Schemas.OnboardingStep = .complete,
        firstName: String? = "Robin",
        photos: [Components.Schemas.MyPhoto]? = nil,
        isAdmin: Bool = false,
        paused: Bool = false,
    ) -> Me {
        let filled = step != .profile
        let photoList = photos ?? (step == .complete || step == .notifications
            ? [
                Components.Schemas.MyPhoto(
                    id: "0f0f0f0f-0000-4000-8000-000000000001",
                    position: 0,
                    moderationStatus: .approved,
                    url: "/api/me/photos/0f0f0f0f-0000-4000-8000-000000000001",
                ),
            ]
            : [])
        return Me(
            id: "00000000-0000-4000-8000-00000000000a",
            profile: .init(
                firstName: filled ? firstName : nil,
                birthdate: filled ? "1999-04-12" : nil,
                gender: filled ? .nonbinary : nil,
                showMe: filled ? [.woman, .man, .nonbinary] : [],
                paused: paused,
                viewerCode: "YTVFCREQ",
            ),
            photos: photoList,
            onboardingStep: step,
            isAdmin: isAdmin,
        )
    }
}
