import SwiftUI

// Owner: B6. Empty states, in the spec's voice: warm, calm, never pushy.
//
//     GlowEmptyState(
//         systemImage: "sparkles",
//         title: "Nobody fits that yet.",
//         message: "Try fewer details.",
//     ) {
//         Button("Change what you noticed") { … }.buttonStyle(.glowSecondary)
//     }

/// A breathing light around a thin icon, one honest sentence in New York, a message and optional
/// actions, centered (U1: waiting and empty states feel intentional and warm).
public struct GlowEmptyState<Actions: View>: View {
    private let systemImage: String
    private let title: Text
    private let message: Text?
    private let actions: Actions
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 34

    public init(
        systemImage: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        @ViewBuilder actions: () -> Actions = { EmptyView() },
    ) {
        self.systemImage = systemImage
        self.title = Text(title)
        self.message = message.map { Text($0) }
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: GlowSpacing.lg) {
            ZStack {
                GlowBreathingLight()
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .light))
                    .foregroundStyle(.glowTextPrimary)
            }
            .accessibilityHidden(true)

            VStack(spacing: GlowSpacing.sm) {
                title
                    .glowFont(.titleSerif)
                    .foregroundStyle(.glowTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    message
                        .glowFont(.callout)
                        .foregroundStyle(.glowTextSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: GlowSpacing.xs) {
                actions
            }
        }
        .padding(GlowSpacing.lg)
        .frame(maxWidth: .infinity)
    }
}
