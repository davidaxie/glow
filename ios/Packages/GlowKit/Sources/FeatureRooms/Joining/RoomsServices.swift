import APIClient
import AppCore
import Foundation
import SwiftUI

/// Where FeatureRooms gets its server calls. Tests and previews swap in a mock through
/// `.environment(\.roomJoining, ...)`; the app uses the live API from `Dependencies`.
extension EnvironmentValues {
    @Entry public var roomJoining: (any RoomJoining)?
}

@MainActor
extension Dependencies {
    /// The live join service on the app's API.
    func roomJoiningService() -> any RoomJoining {
        APIRoomJoining(api: roomsAPI())
    }

    /// The app's API, plus a Debug-only stand-in for the session token (see below).
    func roomsAPI() -> GlowAPI {
        #if DEBUG
            return GlowAPI(
                serverURL: api.serverURL,
                transport: api.transport,
                middlewares: GlowAPI.standardMiddlewares(
                    baseURL: api.serverURL,
                    tokens: DebugAccessTokenFallback(session: session),
                ),
            )
        #else
            return api
        #endif
    }
}

#if DEBUG
    /// Debug builds only, and only until B1's Supabase session lands (it merges after B2).
    ///
    /// AppCore's preview session has no access token, so the Simulator couldn't call the local API at
    /// all. When the session has none, this reads one from the `GlowDebugAccessToken` user default
    /// (`xcrun simctl spawn <udid> defaults write com.davidxie.glow GlowDebugAccessToken <token>`),
    /// for a local `@glow.test` person. The real session's token always wins. Compiled out of
    /// Release. Delete this when the live session exists (docs/HANDOFFS.md, B2 · Still mocked).
    struct DebugAccessTokenFallback: AccessTokenProvider {
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
