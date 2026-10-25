import AppCore
import Foundation

/// Builds the session the app runs on. `ios/Glow/AppComposition.swift` calls `live`.
public enum SessionModule {
    /// Supabase sign-in against `config.supabaseURL` with the anon key.
    ///
    /// Debug builds also read these launch arguments, for Simulator automation and screenshots:
    /// - `-GlowDebugTestLogin alex@glow.test`: start signed in as that test person, whoever was signed
    ///   in before, through `POST /api/dev/test-login` (needs `ALLOW_TEST_LOGIN` on the local server).
    ///   The session's token goes to the API client like any other sign-in, so UI tests can start
    ///   signed in. The launch screen shows until the profile has loaded.
    /// - `-GlowSignOutAtLaunch YES`: start signed out.
    /// - `-GlowResetAgeGate YES`: reopen the profile step after an under-18 answer on this phone.
    /// - `-GlowPreviewSession ready|onboarding|signedOut`: no Supabase at all, the AppCore preview
    ///   session in that state (for other modules' screenshots). `-GlowDebugRoute` or
    ///   `-GlowDebugDeckFixture` without `-GlowDebugTestLogin` means `ready`.
    public static func live(config: AppConfig, analytics: any Analytics) -> any SessionService {
        #if DEBUG
            if UserDefaults.standard.bool(forKey: "GlowResetAgeGate") {
                AgeGateLock().reopen()
            }
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
            default: fixtureSession()
            }
        }

        /// UI tests that open a screen on made-up data (`-GlowDebugRoute`, `-GlowDebugDeckFixture`) have
        /// no backend, so they run on the preview session, signed in. Add `-GlowDebugTestLogin` to
        /// open the same route as a real signed-in person instead.
        private static func fixtureSession() -> PreviewSessionService? {
            let defaults = UserDefaults.standard
            guard defaults.string(forKey: "GlowDebugTestLogin") == nil,
                  defaults.string(forKey: "GlowDebugRoute") != nil || defaults.string(forKey: "GlowDebugDeckFixture") != nil
            else { return nil }
            return PreviewSessionService(state: .ready)
        }

        private static func debugLaunch(_ session: LiveSessionService, backend: SupabaseAuthBackend) async {
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: "GlowSignOutAtLaunch"), backend.currentUserID() != nil {
                await backend.signOut()
            }
            if let email = defaults.string(forKey: "GlowDebugTestLogin") {
                // Always the person asked for: a session left over from an earlier launch is dropped.
                if backend.currentUserID() != nil {
                    await backend.signOut()
                }
                do {
                    try await session.signInForTesting(email: email)
                } catch {
                    // Server without ALLOW_TEST_LOGIN, or nothing listening: show the sign-in screen.
                    await session.restore()
                }
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
