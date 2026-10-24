import AppCore
import SwiftUI

/// Shows a card photo or a match photo, loaded with `dependencies.imaging` (no caching, P4).
///
/// ```swift
/// PrivateImageView(.card(signedURL: card.image.url), label: "Today's look") { error in
///     if error == .notFound { await model.refreshDeck() }   // links last 60 seconds
/// }
/// ```
///
/// The image is held only in this view's state. There is no save, share, copy or drag, and the
/// view is marked privacy sensitive so system redaction (lock screen, widgets) hides it.
public struct PrivateImageView: View {
    public enum Phase: Equatable {
        case loading
        case loaded(PrivateImage)
        case failed(PrivateImageError)
    }

    private let source: PrivateImageSource
    private let label: LocalizedStringKey
    private let contentMode: ContentMode
    private let onFailure: (@MainActor @Sendable (PrivateImageError) async -> Void)?

    @Environment(\.dependencies) private var dependencies
    @State private var phase: Phase = .loading

    /// - Parameters:
    ///   - source: Where the image comes from.
    ///   - label: What VoiceOver reads, for example "Today's look" or "Photo 1 of 3".
    ///   - contentMode: `.fill` crops to the frame, `.fit` letterboxes.
    ///   - onFailure: Called once per failed load. For `.notFound` on a card, refetch the deck.
    public init(
        _ source: PrivateImageSource,
        label: LocalizedStringKey = "Photo",
        contentMode: ContentMode = .fill,
        onFailure: (@MainActor @Sendable (PrivateImageError) async -> Void)? = nil,
    ) {
        self.source = source
        self.label = label
        self.contentMode = contentMode
        self.onFailure = onFailure
    }

    public var body: some View {
        ZStack {
            switch phase {
            case .loading:
                Rectangle().fill(.quaternary)
                    .overlay { ProgressView() }
                    .accessibilityLabel(Text("Loading photo"))
            case let .loaded(photo):
                Image(uiImage: photo.image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .accessibilityLabel(Text(label))
                    .accessibilityAddTraits(.isImage)
            case .failed:
                Rectangle().fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(Text("Photo unavailable"))
            }
        }
        .clipped()
        .privacySensitive()
        .accessibilityIgnoresInvertColors()
        .task(id: source) {
            await load()
        }
    }

    private func load() async {
        phase = .loading
        do {
            let photo = try await dependencies.imaging.loadPrivateImage(source)
            phase = .loaded(photo)
        } catch {
            if error == .cancelled {
                return
            }
            phase = .failed(error)
            await onFailure?(error)
        }
    }
}

#Preview("Card") {
    PrivateImageView(.card(signedURL: "/api/cards/aaaaaaaa-0000-4000-8000-000000000001/image?exp=1&sig=x"), label: "Today's look")
        .frame(width: 240, height: 300)
}
