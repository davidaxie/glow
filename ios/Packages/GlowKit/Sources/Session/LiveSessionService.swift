import APIClient
import AppCore
import Foundation
import os

/// The session the app runs on: Supabase sign-in plus the signed-in person's own `GET /api/me`.
///
/// - At launch it restores the saved session, fetches the profile and moves to the server's
///   onboarding step. Offline, it falls back to the last step it saw (only the step is remembered,
///   never anything about the person).
/// - A 401 from `GET /api/me` (a deleted, banned or signed-out account) signs out at once.
/// - Signing out forgets the session, the profile and the remembered step.
final class LiveSessionService: SessionService {
    private let backend: any AuthBackend
    private let api: GlowAPI
    private let config: AppConfig
    private let analytics: any Analytics
    private let memory: StepMemory
    private let state = Broadcaster<SessionState>(.restoring)
    private let profile = Broadcaster<Me?>(nil)
    private let logger = Logger(subsystem: Log.subsystem, category: "session")

    /// - Parameters:
    ///   - api: The API to read `GET /api/me` from. Built from `config` with this session's
    ///     tokens when nil; tests pass a mock.
    init(
        backend: any AuthBackend,
        config: AppConfig,
        analytics: any Analytics,
        api: GlowAPI? = nil,
        memory: StepMemory = StepMemory(),
        restore: Bool = true,
    ) {
        self.backend = backend
        self.config = config
        self.analytics = analytics
        self.memory = memory
        self.api = api ?? GlowAPI.live(baseURL: config.apiBaseURL, tokens: BackendTokens(backend: backend))
        let ended = backend.sessionEnded()
        Task { [weak self] in
            for await _ in ended {
                await self?.sessionEndedElsewhere()
            }
        }
        if restore {
            Task { await self.restore() }
        }
    }

    // MARK: State

    func states() -> AsyncStream<SessionState> {
        state.stream()
    }

    func profiles() -> AsyncStream<Me?> {
        profile.stream()
    }

    func currentProfile() async -> Me? {
        profile.value
    }

    func currentUserID() async -> String? {
        backend.currentUserID()
    }

    func currentAccessToken() async throws -> String? {
        await backend.accessToken()
    }

    /// Reads the saved session at launch.
    func restore() async {
        guard backend.currentUserID() != nil else {
            state.send(.signedOut)
            return
        }
        await loadProfile(fallback: memory.lastState ?? .onboarding(.profile))
    }

    // MARK: Profile

    @discardableResult
    func refreshProfile() async throws -> Me {
        let output: Operations.GetMe.Output
        do {
            output = try await api.perform { try await $0.getMe() }
        } catch .unauthorized {
            logger.notice("The API no longer accepts this session; signing out")
            await signOut()
            throw APIError.unauthorized
        }
        guard case let .ok(ok) = output, case let .json(me) = ok.body else {
            throw APIError.unexpected(status: nil)
        }
        await apply(me)
        return me
    }

    func apply(_ me: Me) async {
        // A profile for anyone but the person signed in right now is dropped (a reply that
        // arrived after signing out, say).
        guard me.id.lowercased() == backend.currentUserID() else { return }
        profile.send(me)
        let next = SessionState(serverStep: me.onboardingStep)
        memory.remember(me.onboardingStep)
        if state.value != next {
            state.send(next)
        }
    }

    /// Fetches the profile after signing in or at launch, retrying a couple of times before
    /// falling back to `fallback` (the app retries again when a screen appears).
    private func loadProfile(fallback: SessionState) async {
        for attempt in 0 ..< 3 {
            do {
                try await refreshProfile()
                return
            } catch APIError.unauthorized {
                return
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(for: .milliseconds(400 << attempt))
                }
            }
        }
        guard backend.currentUserID() != nil else { return }
        logger.notice("Couldn't load the profile; using the last known step")
        if state.value == .restoring || state.value == .signedOut {
            state.send(fallback)
        }
    }

    // MARK: Signing in

    func signInWithApple(idToken: String, nonce: String) async throws(SessionError) {
        try await backend.signInWithApple(idToken: idToken, nonce: nonce)
        analytics.track(AnalyticsEvent("signed_in", ["method": "apple"]))
        await loadProfile(fallback: .onboarding(.profile))
    }

    func sendEmailCode(to email: String) async throws(SessionError) {
        guard let email = SignInInput.email(email) else { throw .invalidEmail }
        try await backend.sendEmailCode(to: email)
        analytics.track(AnalyticsEvent("sign_in_code_sent"))
    }

    func verifyEmailCode(_ code: String, email: String) async throws(SessionError) {
        guard let email = SignInInput.email(email) else { throw .invalidEmail }
        guard let code = SignInInput.code(code) else { throw .invalidCode }
        try await backend.verifyEmailCode(code, email: email)
        analytics.track(AnalyticsEvent("signed_in", ["method": "email"]))
        await loadProfile(fallback: .onboarding(.profile))
    }

    #if DEBUG
        func signInForTesting(email: String) async throws(SessionError) {
            let session = try await TestSignIn(apiBaseURL: config.apiBaseURL).session(for: email)
            try await backend.adopt(accessToken: session.accessToken, refreshToken: session.refreshToken)
            analytics.track(AnalyticsEvent("signed_in", ["method": "test"]))
            await loadProfile(fallback: .onboarding(.profile))
        }
    #endif

    func signOut() async {
        await backend.signOut()
        forget()
        analytics.track(AnalyticsEvent("signed_out"))
    }

    private func sessionEndedElsewhere() async {
        guard state.value != .signedOut else { return }
        logger.notice("Supabase ended the session")
        forget()
    }

    private func forget() {
        profile.send(nil)
        memory.forget()
        state.send(.signedOut)
    }
}

/// Hands the API wrapper the backend's access token.
struct BackendTokens: AccessTokenProvider {
    let backend: any AuthBackend

    func currentAccessToken() async throws -> String? {
        await backend.accessToken()
    }
}

/// The last onboarding step the server reported, so an offline launch resumes in the right place.
/// Only the step: never a name, an email or an ID.
struct StepMemory: Sendable {
    let key: String

    init(key: String = "glow.session.lastStep") {
        self.key = key
    }

    var lastState: SessionState? {
        UserDefaults.standard.string(forKey: key)
            .flatMap(Components.Schemas.OnboardingStep.init(rawValue:))
            .map(SessionState.init(serverStep:))
    }

    func remember(_ step: Components.Schemas.OnboardingStep) {
        UserDefaults.standard.set(step.rawValue, forKey: key)
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
