import SwiftUI

// Owner: B6. Bottom sheets that fit their content.
//
//     .glowSheet(isPresented: $confirming) {
//         GlowSheetContent(
//             title: "Tap this card?",
//             message: "They won't know unless they tap you too.",
//         ) {
//             Button("Tap") { … }.buttonStyle(.glowPrimary)
//             Button("Not now") { … }.buttonStyle(.glowQuiet)
//         }
//     }

extension View {
    /// Presents a Glow bottom sheet: surface background, 20-point corners, a grabber, and a height
    /// that fits the content (scrolling if the content is taller than the screen).
    public func glowSheet(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> some View,
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            GlowSheetContainer(content: content())
        }
    }

    /// Presents a Glow bottom sheet for `item`, like `sheet(item:)`.
    public func glowSheet<Item: Identifiable>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> some View,
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { item in
            GlowSheetContainer(content: content(item))
        }
    }

    /// The sheet chrome on its own, for a sheet the app presents through a Route: fits the content
    /// and sets the background, corners and grabber.
    public func glowSheetPresentation() -> some View {
        GlowSheetContainer(content: self)
    }
}

/// Fits a sheet to its content.
struct GlowSheetContainer<Content: View>: View {
    let content: Content
    @State private var contentHeight: CGFloat = 320

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, GlowSpacing.screenMargin)
                .padding(.top, GlowSpacing.xl)
                .padding(.bottom, GlowSpacing.md)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    contentHeight = height
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(GlowRadius.card)
        .presentationBackground(.glowSurface)
    }
}

/// The inside of a sheet: an optional icon, a title, a message, any extra content, then the actions
/// stacked full width.
public struct GlowSheetContent<Extra: View, Actions: View>: View {
    private let title: Text
    private let message: Text?
    private let systemImage: String?
    private let tint: GlowRGB
    private let extra: Extra
    private let actions: Actions

    /// - Parameter tint: the icon's color. Use `GlowPalette.danger` for block, report and delete.
    public init(
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        tint: GlowRGB = GlowPalette.accent,
        @ViewBuilder content: () -> Extra = { EmptyView() },
        @ViewBuilder actions: () -> Actions,
    ) {
        self.title = Text(title)
        self.message = message.map { Text($0) }
        self.systemImage = systemImage
        self.tint = tint
        extra = content()
        self.actions = actions()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.lg) {
            VStack(alignment: .leading, spacing: GlowSpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.glow(.title))
                        .foregroundStyle(tint.color)
                        .padding(.bottom, GlowSpacing.xxs)
                        .accessibilityHidden(true)
                }
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            extra

            VStack(spacing: GlowSpacing.xs) {
                actions
            }
        }
    }
}

/// A sheet drawn in place, for the Gallery and snapshot tests: the same surface, corners and grabber
/// as a presented sheet.
struct GlowSheetPreviewFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.glowLine)
                .frame(width: 36, height: 5)
                .padding(.top, GlowSpacing.xs)
                .accessibilityHidden(true)
            content
                .padding(.horizontal, GlowSpacing.screenMargin)
                .padding(.top, GlowSpacing.lg)
                .padding(.bottom, GlowSpacing.lg)
        }
        .background(.glowSurface, in: UnevenRoundedRectangle(topLeadingRadius: GlowRadius.card, topTrailingRadius: GlowRadius.card))
    }
}
