import APIClient
import Foundation

// Owner: B1 (Session). Change this file and Mocks/PreviewSessionService.swift together.
//
// How other modules get the signed-in person and their profile:
//
//     @Environment(\.dependencies) private var dependencies
//     …
//     // The current profile, then every change (nil while signed out):
//     for await me in dependencies.session.profiles() { … me?.profile.firstName … }
//     // Or once:
//     let me = await dependencies.session.currentProfile()
//     // After an API call that changed your own profile (pause, say), refetch it:
//     try await dependencies.session.refreshProfile()
//
// `Me` is only ever the signed-in person's own profile. The app never holds anyone else's
// user ID or profile before a match (P1), and the API never returns another user ID at all.

/// The signed-in person's own profile, exactly as `GET /api/me` returns it.
public typealias Me = Components.Schemas.Me

/// Where someone is in onboarding. The server keeps the source of truth (`profiles.onboarding_step`);
/// `welcome` and `signIn` are the app's own steps before there is a session.
public enum OnboardingStep: String, Hashable, Sendable, CaseIterable {
    case welcome
    case signIn
    case profile
    case photos
    case notifications
}

/// The signed-in state the root navigation follows.
public enum SessionState: Hashable, Sendable {
    /// Reading the saved session at launch.
    case restoring
    case signedOut
    /// Signed in, profile not finished. Rooms can't be opened yet.
    case onboarding(OnboardingStep)
    /// Signed in with a finished, 18+ profile.
    case ready
}

extension SessionState {
    /// The state for a signed-in person whose server-side onboarding step is `step`.
    /// Only `complete` opens the app; every other step stays in onboarding.
    public init(serverStep step: Components.Schemas.OnboardingStep) {
        switch step {
        case .profile: self = .onboarding(.profile)
        case .photos: self = .onboarding(.photos)
        case .notifications: self = .onboarding(.notifications)
        case .complete: self = .ready
        }
    }

    /// True once onboarding is finished. Rooms only open in this state.
    public var isReady: Bool {
        self == .ready
    }
}

/// Why signing in didn't work. Every case is safe to log: none carries an email, a code or a token.
public enum SessionError: Error, Hashable, Sendable {
    /// That doesn't look like an email address.
    case invalidEmail
    /// The 6-digit code is wrong or has expired.
    case invalidCode
    /// Too many tries. Wait a little.
    case rateLimited
    /// No connection.
    case offline
    /// Sign in with Apple didn't finish (cancelled, or the build can't use it).
    case appleSignInFailed
    /// Sign-in isn't configured in this build (no Supabase URL or key).
    case notConfigured
    /// Anything else.
    case unexpected
}

/// Supabase sign-in: Sign in with Apple, a 6-digit email code, and session restore.
/// Also supplies the access token the API wrapper sends as `Authorization: Bearer`, and holds the
/// signed-in person's own profile (`GET /api/me`) for every module that needs it.
public protocol SessionService: AccessTokenProvider {
    /// Yields the current state at once, then every change.
    func states() -> AsyncStream<SessionState>

    /// Yields the signed-in person's own profile at once (nil while signed out or not yet fetched),
    /// then every change.
    func profiles() -> AsyncStream<Me?>

    /// The signed-in person's own profile as last fetched, or nil.
    func currentProfile() async -> Me?

    /// Fetches `GET /api/me` again, updates `profiles()` and moves `states()` to the server's
    /// onboarding step. Throws `APIError`; a 401 signs the person out.
    @discardableResult
    func refreshProfile() async throws -> Me

    /// Hands the session a newer profile that an API call returned (for example `PUT /api/me/profile`),
    /// so `profiles()` and `states()` follow it without another fetch.
    func apply(_ me: Me) async

    /// The signed-in person's own user ID (for their private `user:{id}` channel), or nil.
    /// Never send it anywhere but Supabase Realtime: the API already knows who you are.
    func currentUserID() async -> String?

    /// Signs in with an Apple ID token and the raw nonce whose SHA-256 was sent to Apple.
    func signInWithApple(idToken: String, nonce: String) async throws(SessionError)

    /// Emails a 6-digit code. Creates the account if it's new.
    func sendEmailCode(to email: String) async throws(SessionError)

    /// Signs in with the 6-digit code from the email.
    func verifyEmailCode(_ code: String, email: String) async throws(SessionError)

    #if DEBUG
        /// Debug builds only: signs in a `@glow.test` person through `POST /api/dev/test-login`,
        /// for Simulator automation. Compiled out of Release, and the server refuses it unless
        /// `ALLOW_TEST_LOGIN` is set on a local server.
        func signInForTesting(email: String) async throws(SessionError)
    #endif

    /// Signs out and forgets the profile.
    func signOut() async
}
