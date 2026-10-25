import AppCore
import DesignSystem
import Imaging
import SwiftUI

/// The other person's profile photos, one page each. Rendered only once the match has loaded, so
/// photos are never asked for before a match exists (P1). Each image lives only in its page's
/// state: no cache, no saving, no sharing, and the system hides it where it redacts.
struct MatchPhotoCarousel: View {
    let model: MatchModel
    let snapshot: MatchSnapshot

    @State private var page = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Tall enough to see someone properly; shorter at accessibility text sizes, so the choices
    /// stay close.
    private var height: CGFloat {
        typeSize.isAccessibilitySize ? 300 : 400
    }

    var body: some View {
        Group {
            if snapshot.photoCount == 0 {
                Monogram(firstName: snapshot.firstName)
            } else {
                TabView(selection: $page) {
                    ForEach(Array(model.photoSources.enumerated()), id: \.offset) { index, source in
                        MatchPhotoPage(source: source, index: index, of: snapshot.photoCount, firstName: snapshot.firstName)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: snapshot.photoCount > 1 ? .always : .never))
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: MomentSurface.radius, style: .continuous))
        .overlay { MomentSurface.highlight }
        .shadow(color: GlowPalette.background.color.opacity(0.7), radius: 24, y: 12)
    }
}

/// One photo, loaded by B3's `PrivateImageView` when its page first shows: a checked, watermarked,
/// never-cached request (P4).
struct MatchPhotoPage: View {
    let source: PrivateImageSource
    let index: Int
    let of: Int
    let firstName: String

    var body: some View {
        PrivateImageView(source, label: "Photo \(index + 1) of \(of) of \(firstName)")
            .background(.glowSurface)
    }
}

/// When someone has no photo to show (they're held for review), their initial instead.
struct Monogram: View {
    let firstName: String
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 120

    var body: some View {
        ZStack {
            Rectangle().fill(.glowSurface)
            Text(verbatim: String(firstName.prefix(1)).uppercased())
                .glowFont(.display)
                .foregroundStyle(.glowAccent)
                .frame(width: size, height: size)
                .background(.glowSurfaceRaised, in: .circle)
        }
        .accessibilityHidden(true)
    }
}
