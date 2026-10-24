import AppCore
import SwiftUI

// Placeholder from A3 so the module graph compiles on day one. Owner: B3.
// Replace the body of `live` with the Vision blur pipeline. Keep its signature: the app target
// calls it in AppComposition.

public enum ImagingModule {
    /// The imaging service the app runs on. For now, the AppCore preview mock.
    public static func live(_: ServiceContext) -> any ImagingService {
        PreviewImagingService()
    }
}

/// Placeholder view for the Imaging module.
public struct ImagingPlaceholderView: View {
    public init() {}

    public var body: some View {
        PlaceholderScreen("Imaging", module: "Imaging", owner: "B3")
    }
}
