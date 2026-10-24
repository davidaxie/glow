import Foundation

/// Hands the photo back untouched, claiming one face was blurred. Never use its output for upload.
public struct PreviewImagingService: ImagingService {
    public init() {}

    public func prepareCardPhoto(from original: Data) async throws -> PreparedCardPhoto {
        PreparedCardPhoto(jpegData: original, facesBlurred: 1)
    }
}
