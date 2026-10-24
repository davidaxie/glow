import AppCore
import Foundation

/// The sign-in calls the session needs from Supabase Auth, behind a protocol so the session's
/// own logic (states, profile, errors) is tested without a network.
///
/// Every error a backend throws is already a `SessionError`: no Supabase error, email, code or
/// token ever leaves this layer.
protocol AuthBackend: Sendable {
    /// The saved session's user ID (lowercase), or nil.
    func currentUserID() -> String?
    /// The current access token, refreshed if it expired, or nil when signed out.
    func accessToken() async -> String?
    func signInWithApple(idToken: String, nonce: String) async throws(SessionError)
    func sendEmailCode(to email: String) async throws(SessionError)
    func verifyEmailCode(_ code: String, email: String) async throws(SessionError)
    /// Adopts a session minted elsewhere (Debug test sign-in).
    func adopt(accessToken: String, refreshToken: String) async throws(SessionError)
    /// Forgets the session on this phone and revokes its refresh token.
    func signOut() async
    /// Fires when Supabase ends the session by itself (a revoked or expired refresh token).
    func sessionEnded() -> AsyncStream<Void>
}

/// The shapes sign-in input must have before anything is sent.
enum SignInInput {
    /// Trims and lowercases an email, or nil if it can't be one.
    static func email(_ raw: String) -> String? {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.count <= 254,
              email.wholeMatch(of: /[a-z0-9._%+\-]+@[a-z0-9\-]+(\.[a-z0-9\-]+)+/) != nil
        else { return nil }
        return email
    }

    /// The 6 digits of a code, ignoring spaces, or nil.
    static func code(_ raw: String) -> String? {
        let digits = raw.filter { !$0.isWhitespace }
        guard digits.count == 6, digits.allSatisfy(\.isASCIIDigit) else { return nil }
        return digits
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
