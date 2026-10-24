import SwiftUI

// Owner: B6. The header of a step in a flow, like onboarding or check-in.
//
//     GlowStepHeader(step: 2, of: 4, title: "Add your photos", subtitle: "1 to 3. Only your matches see them.")

/// A row of progress segments, then a title and an optional subtitle. VoiceOver reads
/// "Step 2 of 4" and then the title as a header.
public struct GlowStepHeader: View {
    private let step: Int
    private let total: Int
    private let title: Text
    private let subtitle: Text?

    /// - Parameters:
    ///   - step: the current step, counting from 1.
    ///   - total: how many steps there are.
    public init(step: Int, of total: Int, title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil) {
        self.init(step: step, of: total, title: Text(title), subtitle: subtitle.map { Text($0) })
    }

    public init(step: Int, of total: Int, title: Text, subtitle: Text? = nil) {
        self.total = max(total, 1)
        self.step = min(max(step, 1), self.total)
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.md) {
            HStack(spacing: GlowSpacing.xxs) {
                ForEach(1 ... total, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? AnyShapeStyle(.glowAccent) : AnyShapeStyle(.glowLine))
                        .frame(height: 4)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Step \(step) of \(total)"))

            VStack(alignment: .leading, spacing: GlowSpacing.xs) {
                title
                    .glowFont(.title)
                    .foregroundStyle(.glowTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    subtitle
                        .glowFont(.callout)
                        .foregroundStyle(.glowTextSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
