import APIClient
import AppCore
import Foundation

// Owner: C3. The glow screen's API, plus a Debug-only stand-in for the session token, the same
// way B2 does it in FeatureRooms (RoomsServices.swift), until B1's Supabase session lands.

extension Dependencies {
    /// The app's API. In Debug builds, with a fallback token while the session has none.
    func glowAPI() -> GlowAPI {
        #if DEBUG
            return GlowAPI(
                serverURL: api.serverURL,
                transport: api.transport,
                middlewares: GlowAPI.standardMiddlewares(
                    baseURL: api.serverURL,
                    tokens: GlowDebugAccessTokenFallback(session: session),
                ),
            )
        #else
            return api
        #endif
    }
}

#if DEBUG
    /// Debug builds only, and only until B1's live session exists.
    ///
    /// AppCore's preview session has no access token, so the Simulator couldn't call the local API.
    /// When the session has none, this reads one from the `GlowDebugAccessToken` user default
    /// (`xcrun simctl spawn <udid> defaults write com.davidxie.glow GlowDebugAccessToken <token>`),
    /// for a local `@glow.test` person. The real session's token always wins. Compiled out of
    /// Release. Delete this when the live session exists (docs/HANDOFFS.md, C3 · Still mocked).
    struct GlowDebugAccessTokenFallback: AccessTokenProvider {
        let session: any SessionService

        func currentAccessToken() async throws -> String? {
            if let token = try await session.currentAccessToken() {
                return token
            }
            let token = UserDefaults.standard.string(forKey: "GlowDebugAccessToken")
            return token?.isEmpty == false ? token : nil
        }
    }
#endif
