import AppCore
import Foundation

/// Builds the session the app runs on. `ios/Glow/AppComposition.swift` calls `live`.
public enum SessionModule {
    /// Supabase sign-in against `config.supabaseURL` with the anon key.
    ///
    /// Debug builds also read these launch arguments, for Simulator automation and screenshots:
    /// - `-GlowTestSignIn new@glow.test`: if nobody is signed in, sign in that test person through
    ///   `POST /api/dev/test-login` (needs `ALLOW_TEST_LOGIN` on the local server).
    /// - `-GlowSignOutAtLaunch YES`: start signed out.
    /// - `-GlowPreviewSession ready|onboarding|signedOut`: no Supabase at all, the AppCore preview
    ///   session in that state (for other modules' screenshots).
    public static func live(config: AppConfig, analytics: any Analytics) -> any SessionService {
        #if DEBUG
            if let preview = previewSession() {
                return preview
            }
        #endif
        guard let url = config.supabaseURL, !config.supabaseAnonKey.isEmpty else {
            return LiveSessionService(backend: UnconfiguredBackend(), config: config, analytics: analytics)
        }
        let backend = SupabaseAuthBackend(supabaseURL: url, anonKey: config.supabaseAnonKey)
        #if DEBUG
            let session = LiveSessionService(backend: backend, config: config, analytics: analytics, restore: false)
            Task { await debugLaunch(session, backend: backend) }
            return session
        #else
            return LiveSessionService(backend: backend, config: config, analytics: analytics)
        #endif
    }

    #if DEBUG
        private static func previewSession() -> PreviewSessionService? {
            switch UserDefaults.standard.string(forKey: "GlowPreviewSession") {
            case "ready": PreviewSessionService(state: .ready)
            case "onboarding": PreviewSessionService(state: .onboarding(.profile))
            case "signedOut": PreviewSessionService(state: .signedOut)
            default: nil
            }
        }

        private static func debugLaunch(_ session: LiveSessionService, backend: SupabaseAuthBackend) async {
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: "GlowSignOutAtLaunch"), backend.currentUserID() != nil {
                await backend.signOut()
            }
            if let email = defaults.string(forKey: "GlowTestSignIn"), backend.currentUserID() == nil {
                await session.restore()
                try? await session.signInForTesting(email: email)
                return
            }
            await session.restore()
        }
    #endif
}

/// A build without a Supabase URL or key: always signed out, and sign-in says so.
struct UnconfiguredBackend: AuthBackend {
    func currentUserID() -> String? {
        nil
    }

    func accessToken() async -> String? {
        nil
    }

    func signInWithApple(idToken _: String, nonce _: String) async throws(SessionError) {
        throw .notConfigured
    }

    func sendEmailCode(to _: String) async throws(SessionError) {
        throw .notConfigured
    }

    func verifyEmailCode(_: String, email _: String) async throws(SessionError) {
        throw .notConfigured
    }

    func adopt(accessToken _: String, refreshToken _: String) async throws(SessionError) {
        throw .notConfigured
    }

    func signOut() async {}

    func sessionEnded() -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}
