import AppCore
import DesignSystem
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
                    ForEach(0 ..< snapshot.photoCount, id: \.self) { index in
                        MatchPhotoPage(model: model, index: index, of: snapshot.photoCount, firstName: snapshot.firstName)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: snapshot.photoCount > 1 ? .always : .never))
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: GlowRadius.card, style: .continuous))
    }
}

/// One photo, loaded when its page first shows.
struct MatchPhotoPage: View {
    let model: MatchModel
    let index: Int
    let of: Int
    let firstName: String

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Rectangle().fill(.glowSurface)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel(Text("Photo \(index + 1) of \(of) of \(Text(verbatim: firstName))"))
                    .accessibilityAddTraits(.isImage)
            } else if failed {
                Image(systemName: "photo")
                    .glowFont(.title)
                    .foregroundStyle(.glowTextSecondary)
                    .accessibilityLabel(Text("Photo unavailable"))
            } else {
                ProgressView()
                    .tint(.glowAccent)
                    .accessibilityLabel(Text("Loading photo"))
            }
        }
        .clipped()
        .privacySensitive()
        .accessibilityIgnoresInvertColors()
        .task {
            guard image == nil else { return }
            if let loaded = await model.photo(index) {
                image = loaded
            } else {
                failed = true
            }
        }
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
