import SwiftUI

// Owner: B6. Every component in every state. The app opens it for `Route.gallery`, which the
// Router allows in Debug builds only (Settings > Debug > Gallery). Release builds compile the
// samples out.

/// The design system Gallery. Debug builds only.
public struct GalleryView: View {
    public init() {}

    public var body: some View {
        #if DEBUG
            GalleryContent()
        #else
            EmptyView()
        #endif
    }
}

#if DEBUG

    /// One section of the Gallery. Each one is also a snapshot test, at the default and the largest
    /// text size.
    enum GallerySection: String, CaseIterable, Identifiable {
        case colors, type, spacing, buttons, chips, sheets, toasts, stepHeader, emptyStates

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .colors: "Colors"
            case .type: "Type"
            case .spacing: "Spacing and corners"
            case .buttons: "Buttons"
            case .chips: "Chips"
            case .sheets: "Sheets"
            case .toasts: "Toasts"
            case .stepHeader: "Step header"
            case .emptyStates: "Empty states"
            }
        }

        @MainActor @ViewBuilder
        var content: some View {
            switch self {
            case .colors: GalleryColors()
            case .type: GalleryType()
            case .spacing: GallerySpacing()
            case .buttons: GalleryButtons()
            case .chips: GalleryChips()
            case .sheets: GallerySheets()
            case .toasts: GalleryToasts()
            case .stepHeader: GalleryStepHeaders()
            case .emptyStates: GalleryEmptyStates()
            }
        }
    }

    struct GalleryContent: View {
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: GlowSpacing.xxl) {
                    ForEach(GallerySection.allCases) { section in
                        GallerySectionView(section: section)
                    }
                }
                .padding(.vertical, GlowSpacing.lg)
            }
            .background(.glowBackground)
            .accessibilityIdentifier("screen.DesignSystem")
            .navigationTitle("Gallery")
        }
    }

    /// A section with its title, as the Gallery and the snapshot tests draw it.
    struct GallerySectionView: View {
        let section: GallerySection

        var body: some View {
            VStack(alignment: .leading, spacing: GlowSpacing.md) {
                Text(verbatim: section.title)
                    .glowFont(.title)
                    .foregroundStyle(.glowTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                section.content
            }
            .padding(.horizontal, GlowSpacing.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A small caption naming the state shown below it.
    struct GalleryLabel: View {
        let text: String

        init(_ text: String) {
            self.text = text
        }

        var body: some View {
            Text(verbatim: text)
                .glowFont(.caption)
                .foregroundStyle(.glowTextSecondary)
                .textCase(.uppercase)
        }
    }

    #Preview {
        NavigationStack { GalleryView() }
            .preferredColorScheme(.dark)
    }

#endif
