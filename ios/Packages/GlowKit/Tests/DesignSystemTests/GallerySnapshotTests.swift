import SnapshotTesting
import SwiftUI
import Testing
@testable import DesignSystem

/// Every Gallery section at the default text size and the largest accessibility size.
///
/// To re-record after an intended change, delete the PNGs in `__Snapshots__/GallerySnapshotTests`
/// and run `scripts/sim.sh test DesignSystem` twice (the first run records and fails).
@MainActor
struct GallerySnapshotTests {
    @Test(arguments: GallerySection.allCases, [DynamicTypeSize.large, .accessibility5])
    func section(_ section: GallerySection, size: DynamicTypeSize) {
        let view = GallerySectionView(section: section)
            .padding(.vertical, GlowSpacing.lg)
            .frame(width: 393)
            .background(.glowBackground)
            .environment(\.dynamicTypeSize, size)
            .environment(\.colorScheme, .dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.99,
                perceptualPrecision: 0.98,
                layout: .sizeThatFits,
                traits: UITraitCollection { traits in
                    traits.displayScale = 2
                    traits.userInterfaceStyle = .dark
                    traits.preferredContentSizeCategory = size == .large ? .large : .accessibilityExtraExtraExtraLarge
                },
            ),
            named: "\(section.rawValue)-\(size == .large ? "default" : "ax5")",
        )
    }

    @Test func galleryBuilds() {
        _ = GalleryView().body
    }
}
