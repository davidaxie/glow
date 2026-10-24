import AppCore
import DesignSystem
import SwiftUI
import UIKit

// Owner: C1. One card photo, loaded fresh from its signed link (no caching, P4). Swaps to B3's
// `PrivateImageView(.card(signedURL:))` once PR #7 merges.

struct DeckCardImage: View {
    enum Phase: Equatable {
        case loading
        case loaded(UIImage)
        case failed

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.failed, .failed): true
            case let (.loaded(left), .loaded(right)): left === right
            default: false
            }
        }
    }

    let url: String
    let contentMode: ContentMode
    /// Called when the link has expired or the card left the deck, so the deck can refetch.
    let onUnavailable: @MainActor () -> Void

    @Environment(\.dependencies) private var dependencies
    @Environment(\.deckImageLoader) private var injectedLoader
    @Environment(\.isSceneCaptured) private var isCaptured
    @State private var phase: Phase = .loading

    init(url: String, contentMode: ContentMode = .fill, onUnavailable: @escaping @MainActor () -> Void = {}) {
        self.url = url
        self.contentMode = contentMode
        self.onUnavailable = onUnavailable
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.glowSurfaceRaised)
            switch phase {
            case .loading:
                ProgressView()
                    .tint(.glowTextSecondary)
                    .accessibilityLabel(Text(DeckCopy.loadingLook))
            case let .loaded(image):
                // Never drawn while the screen is captured (P12), even under the deck's cover.
                if !isCaptured {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .accessibilityHidden(true)
                }
            case .failed:
                VStack(spacing: GlowSpacing.xs) {
                    Image(systemName: "photo")
                        .font(.glow(.title))
                        .accessibilityHidden(true)
                    Text(DeckCopy.imageFailed)
                        .glowFont(.footnote)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.glowTextSecondary)
                .padding(GlowSpacing.sm)
            }
        }
        .clipped()
        .privacySensitive()
        .accessibilityIgnoresInvertColors()
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        if case .loaded = phase {
            // Keep showing the old photo until the new one is in; no flash on a link refresh.
        } else {
            phase = .loading
        }
        let loader = dependencies.deckImageLoader(override: injectedLoader)
        do {
            phase = try await .loaded(loader.load(url))
        } catch {
            switch error {
            case .cancelled:
                return
            case .notFound:
                phase = .failed
                onUnavailable()
            case .failed:
                phase = .failed
            }
        }
    }
}
