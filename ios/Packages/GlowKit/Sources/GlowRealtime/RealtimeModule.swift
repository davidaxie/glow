import AppCore
import SwiftUI

// Placeholder from A3 so the module graph compiles on day one. Owner: B5.
// The spec calls this module "Realtime"; it is GlowRealtime because supabase-swift already has a
// target named Realtime, and SwiftPM needs unique target names.
// Replace the body of `live` with Supabase Realtime private channels. Keep its signature: the app
// target calls it in AppComposition.

public enum RealtimeModule {
    /// The realtime service the app runs on. For now, the AppCore preview mock.
    public static func live(_: ServiceContext) -> any RealtimeService {
        PreviewRealtimeService()
    }
}

/// Placeholder view for the Realtime module.
public struct RealtimePlaceholderView: View {
    public init() {}

    public var body: some View {
        PlaceholderScreen("Realtime", module: "GlowRealtime", owner: "B5")
    }
}
