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

/// A softly glowing icon, a title, a message and optional actions, centered.
public struct GlowEmptyState<Actions: View>: View {
    private let systemImage: String
    private let title: Text
    private let message: Text?
    private let actions: Actions
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 40

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
                Circle()
                    .fill(RadialGradient(
                        colors: [.glowAccent.opacity(0.35), .glowAccent.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: iconSize * 1.4,
                    ))
                    .frame(width: iconSize * 2.8, height: iconSize * 2.8)
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundStyle(.glowAccent)
            }
            .accessibilityHidden(true)

            VStack(spacing: GlowSpacing.xs) {
                title
                    .glowFont(.headline)
                    .foregroundStyle(.glowTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    message
                        .glowFont(.body)
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
