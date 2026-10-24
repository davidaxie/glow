import SwiftUI

// Placeholder from A3 so the module graph compiles on day one. Owner: B6.
// Replace with the real tokens, components and Gallery. Keep `GalleryView` public: the app
// opens it for `Route.gallery` in Debug builds.

/// Every component in every state. Debug builds only.
public struct GalleryView: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView(
            "Gallery",
            systemImage: "paintpalette",
            description: Text("DesignSystem · B6"),
        )
        .accessibilityIdentifier("screen.DesignSystem")
        .navigationTitle("Gallery")
    }
}

#Preview {
    GalleryView()
}
