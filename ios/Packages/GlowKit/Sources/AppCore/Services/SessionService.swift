import APIClient
import Foundation

// Owner from Wave 1: B1 (Session). A3 wrote this first shape; B1 may change this file and
// Mocks/PreviewSessionService.swift together.

/// Where someone is in onboarding. The server keeps the source of truth (`profiles.onboarding_step`).
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

/// Supabase sign-in: Sign in with Apple, a 6-digit email code, and session restore.
/// Also supplies the access token the API wrapper sends as `Authorization: Bearer`.
public protocol SessionService: AccessTokenProvider {
    /// Yields the current state at once, then every change.
    func states() -> AsyncStream<SessionState>
    /// The signed-in person's own user ID (for their private `user:{id}` channel), or nil.
    func currentUserID() async -> String?
    func signInWithApple(idToken: String, nonce: String) async throws
    func sendEmailCode(to email: String) async throws
    func verifyEmailCode(_ code: String, email: String) async throws
    func signOut() async
}
