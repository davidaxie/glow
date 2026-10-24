import AppCore
import SwiftUI

// Placeholder from A3 so the module graph compiles on day one. Owner: B2.
// Replace the body of `live` with the CoreLocation service. Keep its signature: the app target
// calls it in AppComposition.

public enum LocationModule {
    /// The location service the app runs on. For now, the AppCore preview mock.
    public static func live(_: ServiceContext) -> any LocationService {
        PreviewLocationService()
    }
}

/// Placeholder view for the Location module.
public struct LocationPlaceholderView: View {
    public init() {}

    public var body: some View {
        PlaceholderScreen("Location", module: "Location", owner: "B2")
    }
}
