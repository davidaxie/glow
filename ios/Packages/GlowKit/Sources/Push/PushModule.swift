import AppCore
import SwiftUI

// Placeholder from A3 so the module graph compiles on day one. Owner: B5.
// Replace the body of `live` with APNs registration, categories and payload-to-Route mapping.
// Keep its signature: the app target calls it in AppComposition.

public enum PushModule {
    /// The push service the app runs on. For now, the AppCore preview mock.
    public static func live(_: ServiceContext) -> any PushService {
        PreviewPushService()
    }
}

/// Placeholder view for the Push module.
public struct PushPlaceholderView: View {
    public init() {}

    public var body: some View {
        PlaceholderScreen("Push", module: "Push", owner: "B5")
    }
}
