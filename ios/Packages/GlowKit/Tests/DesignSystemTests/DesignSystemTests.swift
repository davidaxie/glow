import SwiftUI
import Testing
@testable import DesignSystem

// Placeholder test from A3. Owner: B6.
@MainActor
struct DesignSystemTests {
    @Test func galleryBuilds() {
        _ = GalleryView().body
    }
}
