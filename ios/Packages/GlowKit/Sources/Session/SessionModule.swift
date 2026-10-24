import AppCore
import Foundation
import SwiftUI

// Placeholder from A3 so the module graph compiles on day one. Owner: B1.
// Replace the body of `live` with the Supabase session (sign in with Apple, email code, restore).
// Keep its signature: the app target calls it in AppComposition.

public enum SessionModule {
    /// The session the app runs on.
    ///
    /// For now: the AppCore preview session, signed in and onboarded, so the tabs show.
    /// Debug builds can start elsewhere with a launch argument, for example
    /// `-GlowPreviewSession onboarding` or `-GlowPreviewSession signedOut`.
    public static func live(config _: AppConfig, analytics _: any Analytics) -> any SessionService {
        let start: SessionState = switch UserDefaults.standard.string(forKey: "GlowPreviewSession") {
        case "signedOut": .signedOut
        case "onboarding": .onboarding(.profile)
        default: .ready
        }
        return PreviewSessionService(state: start)
    }
}

/// Placeholder view for the Session module.
public struct SessionPlaceholderView: View {
    public init() {}

    public var body: some View {
        PlaceholderScreen("Session", module: "Session", owner: "B1")
    }
}
