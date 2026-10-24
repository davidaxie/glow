import Foundation
import UIKit

// Owner: B3 (Imaging). This file and Mocks/PreviewImagingService.swift change together.

// MARK: - Card photos (check-in)

/// A card photo that is safe to upload: faces blurred on the phone, at most PHOTO_MAX_DIMENSION on
/// the long side, JPEG at PHOTO_JPEG_QUALITY, and no metadata at all (no location, no device, no
/// time). The only image type check-in uploads (P3).
public struct PreparedCardPhoto: Hashable, Sendable {
    /// The JPEG to upload. Its pixels are what other people see.
    public let jpegData: Data
    /// How many face boxes were blurred.
    public let facesBlurred: Int
    /// The exported size in pixels.
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(jpegData: Data, facesBlurred: Int, pixelWidth: Int = 0, pixelHeight: Int = 0) {
        self.jpegData = jpegData
        self.facesBlurred = facesBlurred
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public enum ImagingError: Error, Hashable, Sendable {
    /// Vision found nobody in the photo. Ask for a retake.
    case noPersonFound
    /// The data isn't an image the phone can read.
    case unreadableImage
    /// Face detection or blurring failed, so nothing may be uploaded. Ask for a retake.
    case processingFailed
}

// MARK: - Private images (cards and match photos)

/// Where a private image comes from. Every one is fetched through the API with the bearer token,
/// checked by the server on every request (P4), and never cached or saved on the phone.
public enum PrivateImageSource: Hashable, Sendable, CustomStringConvertible {
    /// A card photo: the `image.url` of a deck card or my check-in, exactly as the server sent it.
    /// The link lasts CARD_URL_TTL (60 seconds) and only works for the person it was made for.
    case card(signedURL: String)
    /// The other person's profile photo `index` (0-based, below `photoCount`) in an active match.
    case matchPhoto(MatchID, index: Int)

    /// Never prints the signed link.
    public var description: String {
        switch self {
        case .card: "PrivateImageSource.card(redacted)"
        case let .matchPhoto(match, index): "PrivateImageSource.matchPhoto(\(match), \(index))"
        }
    }
}

/// A decoded private image. Held in memory only, for as long as a view shows it.
public struct PrivateImage: Sendable, Equatable {
    public let image: UIImage

    public init(image: UIImage) {
        self.image = image
    }

    public static func == (lhs: PrivateImage, rhs: PrivateImage) -> Bool {
        lhs.image === rhs.image
    }
}

public enum PrivateImageError: Error, Hashable, Sendable {
    /// 404: the link expired, it was made for someone else, the card left the deck, the match ended,
    /// or the photo doesn't exist. The server never says which (P11). For cards, refetch the deck to
    /// get fresh links.
    case notFound
    /// Signed out or the session expired.
    case unauthorized
    case rateLimited
    case offline
    case cancelled
    /// The link isn't one of ours (it would leave the API, or isn't a card image path).
    case invalidSource
    /// The response wasn't a JPEG the phone could decode.
    case unreadable
    /// Anything else.
    case failed
}

// MARK: - Service

/// The on-device private image pipeline (spec: Private images on device), plus the loader every
/// feature uses to show card photos and match photos.
///
/// The original photo never leaves the phone; only a `PreparedCardPhoto` is uploaded (P3).
public protocol ImagingService: Sendable {
    /// Finds faces, blurs them, checks there's a person, and exports a metadata-free JPEG.
    /// The original is only read, never stored, and the caller should drop it right after.
    func prepareCardPhoto(from original: Data) async throws -> PreparedCardPhoto

    /// Fetches a card photo or a match photo through the API, with caching turned off.
    ///
    /// ```swift
    /// let photo = try await dependencies.imaging.loadPrivateImage(.card(signedURL: card.image.url))
    /// ```
    ///
    /// Or let `PrivateImageView` from the Imaging module do it.
    func loadPrivateImage(_ source: PrivateImageSource) async throws(PrivateImageError) -> PrivateImage
}
