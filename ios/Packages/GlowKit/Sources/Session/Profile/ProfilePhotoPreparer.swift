import APIClient
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns a picked photo into what `POST /api/me/photos` takes: cropped to 4:5 around the
/// middle, at most `PHOTO_MAX_DIMENSION` on the long side, sRGB, JPEG at `PHOTO_JPEG_QUALITY`,
/// with every bit of metadata dropped (location, camera, dates, the uncropped thumbnail).
///
/// Only pixels are copied into a fresh image, so nothing from the original file can come along.
/// The original stays in memory and is dropped as soon as this returns. The server strips
/// metadata again before storing (defense in depth).
public enum ProfilePhotoPreparer {
    public enum Failure: Error, Hashable, Sendable {
        /// Not an image ImageIO can read.
        case unreadable
        /// Even at the lowest quality it's over `PHOTO_MAX_BYTES`.
        case tooLarge
    }

    /// Width over height.
    public static let aspect = 4.0 / 5.0
    /// The pixel cap Glow decodes to before cropping, so a huge photo can't exhaust memory.
    static let decodeLimit = 4096

    public static func prepare(_ original: Data) throws(Failure) -> Data {
        guard let source = CGImageSourceCreateWithData(original as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0
        else { throw .unreadable }
        // A thumbnail with the transform applied is the photo the right way up, at most
        // decodeLimit on its long side.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: decodeLimit,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let upright = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let pixels = render(upright) else { throw .unreadable }

        for quality in [Double(GlowConstants.photoJPEGQualityPercent) / 100, 0.7, 0.6, 0.5] {
            if let jpeg = encode(pixels, quality: quality), jpeg.count <= GlowConstants.photoMaxBytes {
                return jpeg
            }
        }
        throw .tooLarge
    }

    /// The 4:5 crop rectangle, centered, in pixel coordinates.
    static func cropRect(width: Int, height: Int) -> CGRect {
        let fullWidth = Double(width)
        let fullHeight = Double(height)
        if fullWidth / fullHeight > aspect {
            let cropWidth = (fullHeight * aspect).rounded(.down)
            return CGRect(x: ((fullWidth - cropWidth) / 2).rounded(.down), y: 0, width: cropWidth, height: fullHeight)
        }
        let cropHeight = (fullWidth / aspect).rounded(.down)
        return CGRect(x: 0, y: ((fullHeight - cropHeight) / 2).rounded(.down), width: fullWidth, height: cropHeight)
    }

    /// The output size: the crop, scaled down so the long side (the height) fits.
    static func outputSize(for crop: CGRect) -> (width: Int, height: Int) {
        let maxHeight = Double(GlowConstants.photoMaxDimensionPixels)
        let scale = min(1, maxHeight / crop.height)
        let height = (crop.height * scale).rounded()
        let width = (height * aspect).rounded()
        return (Int(width), Int(height))
    }

    /// Crops and scales into a fresh sRGB bitmap with no alpha.
    private static func render(_ image: CGImage) -> CGImage? {
        let crop = cropRect(width: image.width, height: image.height)
        let size = outputSize(for: crop)
        guard size.width > 0, size.height > 0,
              let cropped = image.cropping(to: crop),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: size.width,
                  height: size.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
              )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage()
    }

    /// A JPEG of `image` with no properties at all: ImageIO only writes what it must to decode it.
    private static func encode(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
