import CoreGraphics

// Owner: B6. Spacing, corners and sizes from docs/SPEC.md: a 4-point grid, 12 for controls,
// 20 for cards and sheets, capsules for chips.

/// Spacing on the 4-point grid.
public enum GlowSpacing {
    /// One grid step.
    public static let unit: CGFloat = 4

    /// 4
    public static let xxs: CGFloat = 4
    /// 8
    public static let xs: CGFloat = 8
    /// 12
    public static let sm: CGFloat = 12
    /// 16
    public static let md: CGFloat = 16
    /// 24
    public static let lg: CGFloat = 24
    /// 32
    public static let xl: CGFloat = 32
    /// 48
    public static let xxl: CGFloat = 48

    /// Leading and trailing margin of a screen's content.
    public static let screenMargin: CGFloat = 20

    /// `steps` grid steps: `GlowSpacing.grid(5)` is 20.
    public static func grid(_ steps: Int) -> CGFloat {
        CGFloat(steps) * unit
    }

    /// Every named step, smallest first.
    public static let scale: [(name: String, value: CGFloat)] = [
        ("xxs", xxs), ("xs", xs), ("sm", sm), ("md", md), ("lg", lg), ("xl", xl), ("xxl", xxl),
    ]
}

/// Corner radii. Chips and tags are capsules (`Capsule()`), not a radius.
public enum GlowRadius {
    /// Buttons, fields, code boxes and other controls.
    public static let control: CGFloat = 12
    /// Cards, sheets, toasts and takeovers.
    public static let card: CGFloat = 20
}

/// Minimum sizes. Each one is a starting point that grows with Dynamic Type.
public enum GlowSize {
    /// Apple's minimum hit target.
    public static let minimumTapTarget: CGFloat = 44
    /// Height of a large button at the default text size.
    public static let buttonHeight: CGFloat = 52
    /// Height of a compact button at the default text size.
    public static let compactButtonHeight: CGFloat = 44
    /// Visible height of a chip at the default text size. Its hit area is still 44.
    public static let chipHeight: CGFloat = 36
}
