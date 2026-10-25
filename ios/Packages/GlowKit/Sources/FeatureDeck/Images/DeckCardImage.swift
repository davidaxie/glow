import AppCore
import Imaging
import SwiftUI

// Owner: C1. One card photo, through B3's `PrivateImageView`: fetched fresh from its signed link
// with the bearer token, never cached or saved (P4), and marked privacy sensitive.

struct DeckCardImage: View {
    let url: String
    var contentMode: ContentMode = .fill
    /// The link expired (CARD_URL_TTL) or the card left the deck: the deck refetches.
    let onUnavailable: @MainActor @Sendable () -> Void

    var body: some View {
        PrivateImageView(.card(signedURL: url), label: LocalizedStringKey(DeckCopy.todaysLook), contentMode: contentMode) { error in
            if error == .notFound {
                onUnavailable()
            }
        }
    }
}
