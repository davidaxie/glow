import APIClient
import AppCore
import Foundation
import HTTPTypes
import OpenAPIRuntime
import UIKit

/// Fetches card photos and match photos through the API (P4).
///
/// - The request goes through `GlowAPI`, so it carries the bearer token, and only to the API's own
///   host. The API's URLSession is ephemeral with no URL cache, so nothing reaches the disk (D42).
/// - Nothing is cached in memory either: every call is a fresh, checked request, and the decoded
///   image lives only as long as whoever holds it.
/// - Card links are used exactly as the server sent them, and refused unless they're a relative
///   `/api/cards/{id}/image` path, so a link can never send the token anywhere else.
public struct PrivateImageLoader: Sendable {
    /// Larger than any watermarked JPEG the server sends (uploads are at most 3 MB).
    public static let maxBytes = 8 * 1024 * 1024

    private let api: GlowAPI

    public init(api: GlowAPI) {
        self.api = api
    }

    public func load(_ source: PrivateImageSource) async throws(PrivateImageError) -> PrivateImage {
        let (path, operationID) = try Self.requestPath(for: source)
        var fields = HTTPFields()
        fields[.accept] = "image/jpeg"
        fields[.cacheControl] = "no-store"
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: path, headerFields: fields)

        let response: HTTPResponse
        let body: HTTPBody?
        do {
            (response, body) = try await api.send(request, operationID: operationID)
        } catch {
            throw Self.map(error)
        }
        guard response.status.code == 200 else {
            throw response.status.code == 404 ? .notFound : .failed
        }
        guard let contentType = response.headerFields[.contentType]?.lowercased(),
              contentType.hasPrefix("image/jpeg"),
              let body
        else { throw .unreadable }

        let data: Data
        do {
            data = try await Data(collecting: body, upTo: Self.maxBytes)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .unreadable
        }
        guard let image = UIImage(data: data) else { throw .unreadable }
        return PrivateImage(image: image)
    }

    // MARK: - Paths

    /// A lowercase UUID, as the server writes them.
    static func isLowercaseUUID(_ text: some StringProtocol) -> Bool {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count == 36 else { return false }
        for (index, scalar) in scalars.enumerated() {
            if [8, 13, 18, 23].contains(index) {
                guard scalar == "-" else { return false }
            } else {
                guard ("0" ... "9").contains(scalar) || ("a" ... "f").contains(scalar) else { return false }
            }
        }
        return true
    }

    /// The request path (with query) and operation ID for a source, or `.invalidSource`.
    static func requestPath(for source: PrivateImageSource) throws(PrivateImageError) -> (String, String) {
        switch source {
        case let .card(signedURL):
            guard let components = URLComponents(string: signedURL),
                  components.scheme == nil, components.host == nil, components.port == nil,
                  components.user == nil, components.password == nil, components.fragment == nil,
                  !signedURL.hasPrefix("//")
            else { throw .invalidSource }
            let parts = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 5, parts[0].isEmpty, parts[1] == "api", parts[2] == "cards",
                  isLowercaseUUID(parts[3]), parts[4] == "image"
            else { throw .invalidSource }
            let names = (components.queryItems ?? []).map(\.name).sorted()
            guard names == ["exp", "sig"] else { throw .invalidSource }
            return (signedURL, "getCardImage")

        case let .matchPhoto(match, index):
            guard (0 ..< GlowConstants.profilePhotosMax).contains(index),
                  isLowercaseUUID(match.rawValue)
            else { throw .invalidSource }
            return ("/api/matches/\(match.rawValue)/photos/\(index)", "getMatchPhoto")
        }
    }

    static func map(_ error: APIError) -> PrivateImageError {
        switch error {
        case .notFound: .notFound
        case .unauthorized: .unauthorized
        case .rateLimited: .rateLimited
        case .offline: .offline
        case .cancelled: .cancelled
        case .unexpected: .failed
        }
    }
}
