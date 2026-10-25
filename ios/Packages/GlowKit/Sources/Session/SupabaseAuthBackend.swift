import AppCore
import Auth
import Foundation
import os

/// Supabase Auth through supabase-swift. The app holds only the anon key (AGENTS.md: Secrets).
///
/// The session is kept in the Keychain on this phone only (`DeviceKeychainStorage`). Deleting the
/// app signs you out: the first launch after an install removes any session an earlier install
/// left in the Keychain.
final class SupabaseAuthBackend: AuthBackend {
    static let storageKey = "glow.session"
    static let keychainService = "com.davidxie.glow.session"
    private static let installMarkerKey = "glow.session.installed"

    private let client: AuthClient
    private let logger = Logger(subsystem: Log.subsystem, category: "session")

    init(supabaseURL: URL, anonKey: String, storage: any AuthLocalStorage = DeviceKeychainStorage(service: keychainService)) {
        Self.forgetSessionFromEarlierInstall(storage: storage)
        client = AuthClient(
            url: supabaseURL.appending(path: "auth/v1"),
            headers: ["apikey": anonKey],
            // The email code is verified in the app, so there's no redirect and no code verifier
            // to keep around.
            flowType: .implicit,
            storageKey: Self.storageKey,
            localStorage: storage,
            logger: nil,
            fetch: { request in try await URLSession(configuration: .glowAuth).data(for: request) },
            autoRefreshToken: true,
            emitLocalSessionAsInitialSession: true,
        )
    }

    /// The Keychain outlives the app. A session it still holds from before a reinstall is
    /// removed, so a fresh install always starts signed out.
    private static func forgetSessionFromEarlierInstall(storage: any AuthLocalStorage) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: installMarkerKey) else { return }
        try? storage.remove(key: storageKey)
        defaults.set(true, forKey: installMarkerKey)
    }

    func currentUserID() -> String? {
        client.currentSession?.user.id.uuidString.lowercased()
    }

    func accessToken() async -> String? {
        guard client.currentSession != nil else { return nil }
        do {
            return try await client.session.accessToken
        } catch {
            logger.notice("Couldn't refresh the session")
            return nil
        }
    }

    func signInWithApple(idToken: String, nonce: String) async throws(SessionError) {
        do {
            _ = try await client.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
        } catch {
            throw Self.map(error, invalid: .appleSignInFailed)
        }
    }

    func sendEmailCode(to email: String) async throws(SessionError) {
        do {
            try await client.signInWithOTP(email: email, shouldCreateUser: true)
        } catch {
            throw Self.map(error, invalid: .invalidEmail)
        }
    }

    func verifyEmailCode(_ code: String, email: String) async throws(SessionError) {
        do {
            _ = try await client.verifyOTP(email: email, token: code, type: .email)
        } catch {
            throw Self.map(error, invalid: .invalidCode)
        }
    }

    func adopt(accessToken: String, refreshToken: String) async throws(SessionError) {
        do {
            _ = try await client.setSession(accessToken: accessToken, refreshToken: refreshToken)
        } catch {
            throw Self.map(error, invalid: .unexpected)
        }
    }

    func signOut() async {
        // Local scope: this phone only. Revoking the refresh token on the server is best effort;
        // the local session is removed either way.
        try? await client.signOut(scope: .local)
    }

    func sessionEnded() -> AsyncStream<Void> {
        let changes = client.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await change in changes where change.event == .signedOut {
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Maps a supabase-swift error to a `SessionError`, keeping nothing from its message.
    static func map(_ error: any Error, invalid: SessionError) -> SessionError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
                 .dnsLookupFailed, .timedOut, .dataNotAllowed:
                return .offline
            default:
                return .unexpected
            }
        }
        if let authError = error as? AuthError, case let .api(_, code, _, response) = authError {
            if response.statusCode == 429 || code == .overEmailSendRateLimit || code == .overRequestRateLimit {
                return .rateLimited
            }
            if (400 ..< 500).contains(response.statusCode) {
                return invalid
            }
        }
        return .unexpected
    }
}

extension URLSessionConfiguration {
    /// Sign-in traffic: ephemeral, no cache, no cookies.
    static var glowAuth: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        return configuration
    }
}
