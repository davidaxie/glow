import Foundation

// Owner from Wave 1: B3 (Imaging). A3 wrote this first shape; B3 may change this file and
// Mocks/PreviewImagingService.swift together.

/// A card photo that is safe to upload: faces blurred on the phone, JPEG at quality 0.8, no metadata.
public struct PreparedCardPhoto: Hashable, Sendable {
    public let jpegData: Data
    public let facesBlurred: Int

    public init(jpegData: Data, facesBlurred: Int) {
        self.jpegData = jpegData
        self.facesBlurred = facesBlurred
    }
}

public enum ImagingError: Error, Hashable, Sendable {
    /// Vision found nobody in the photo. Ask for a retake.
    case noPersonFound
    case unreadableImage
}

/// The on-device private image pipeline (spec: Private images on device).
/// The original photo never leaves the phone; only `PreparedCardPhoto` is uploaded (P3).
public protocol ImagingService: Sendable {
    /// Finds faces, blurs them, checks there's a person, and exports a metadata-free JPEG.
    func prepareCardPhoto(from original: Data) async throws -> PreparedCardPhoto
}
