import APIClient
import AppCore
import Foundation
import HTTPTypes
import OpenAPIRuntime
import UIKit

// Owner: C1. How the deck gets card photos.
//
// Stand-in until B3's `PrivateImageView` and `dependencies.imaging.loadPrivateImage(_:)` merge
// (PR #7): then `DeckCardImage` switches to them and `APICardImageLoader` is deleted. Same rules as
// B3's loader: through `GlowAPI` (bearer token, only to the API's own host, ephemeral session with no
// URL cache, D42), only relative `/api/cards/{id}/image?exp&sig` links, and nothing cached or saved.

enum CardImageFailure: Error, Hashable, Sendable {
    /// 404: the link expired (CARD_URL_TTL), or the card left my deck (P11). Refetch the deck.
    case notFound
    case cancelled
    /// Anything else: offline, unreadable, not one of our links.
    case failed
}

/// Loads one card photo from its signed link.
protocol CardImageLoading: Sendable {
    @MainActor
    func load(_ signedURL: String) async throws(CardImageFailure) -> UIImage
}

/// Through the API. A stand-in for B3's loader (see the top of this file).
struct APICardImageLoader: CardImageLoading {
    /// Larger than any watermarked JPEG the server sends.
    static let maxBytes = 8 * 1024 * 1024

    let api: GlowAPI

    @MainActor
    func load(_ signedURL: String) async throws(CardImageFailure) -> UIImage {
        guard Self.isCardImageLink(signedURL) else { throw .failed }
        var fields = HTTPFields()
        fields[.accept] = "image/jpeg"
        fields[.cacheControl] = "no-store"
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: signedURL, headerFields: fields)
        let response: HTTPResponse
        let body: HTTPBody?
        do {
            (response, body) = try await api.send(request, operationID: "getCardImage")
        } catch {
            switch error {
            case .notFound: throw .notFound
            case .cancelled: throw .cancelled
            default: throw .failed
            }
        }
        guard response.status.code == 200, let body else {
            throw response.status.code == 404 ? .notFound : .failed
        }
        let data: Data
        do {
            data = try await Data(collecting: body, upTo: Self.maxBytes)
        } catch {
            throw .failed
        }
        guard let image = UIImage(data: data) else { throw .failed }
        return image
    }

    /// A relative `/api/cards/{lowercase uuid}/image?exp=…&sig=…` link, and nothing else, so a link
    /// can never send the token anywhere but the card image route.
    static func isCardImageLink(_ link: String) -> Bool {
        guard !link.hasPrefix("//"),
              let components = URLComponents(string: link),
              components.scheme == nil, components.host == nil, components.port == nil,
              components.user == nil, components.password == nil, components.fragment == nil
        else { return false }
        let parts = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0].isEmpty, parts[1] == "api", parts[2] == "cards", parts[4] == "image",
              let id = UUID(uuidString: String(parts[3])), id.uuidString.lowercased() == parts[3]
        else { return false }
        let names = (components.queryItems ?? []).map(\.name).sorted()
        return names == ["exp", "sig"]
    }
}
