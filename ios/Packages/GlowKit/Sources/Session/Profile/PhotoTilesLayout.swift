import SwiftUI

/// Lays photo tiles out in rows of `columns`, each tile 4:5 and as wide as its share of the row.
/// Shared by onboarding's photos step and Settings' Edit photos, so both size tiles the same way
/// inside a scroll view (which proposes no height) and in snapshots.
public struct PhotoTilesLayout: Layout {
    public var columns: Int
    public var spacing: CGFloat

    /// Width over height.
    public static let aspect: CGFloat = 4.0 / 5.0
    /// The width used when nothing is proposed.
    static let fallbackWidth: CGFloat = 353

    public init(columns: Int, spacing: CGFloat) {
        self.columns = max(1, columns)
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? Self.fallbackWidth
        let tile = tileSize(width: width)
        let rows = (subviews.count + columns - 1) / columns
        let height = CGFloat(rows) * tile.height + CGFloat(max(0, rows - 1)) * spacing
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let tile = tileSize(width: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let row = index / columns
            let column = index % columns
            let origin = CGPoint(
                x: bounds.minX + CGFloat(column) * (tile.width + spacing),
                y: bounds.minY + CGFloat(row) * (tile.height + spacing),
            )
            subview.place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(tile))
        }
    }

    func tileSize(width: CGFloat) -> CGSize {
        let tileWidth = max(0, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        return CGSize(width: tileWidth, height: tileWidth / Self.aspect)
    }
}
