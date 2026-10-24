import Foundation
import UIKit

/// For previews and tests. `prepareCardPhoto` hands the photo back untouched, claiming one face
/// was blurred, so never use its output for an upload. `loadPrivateImage` draws a plain
/// placeholder (or fails, if asked to) and never touches the network.
public struct PreviewImagingService: ImagingService {
    public enum LoadBehavior: Sendable {
        case placeholder
        case fail(PrivateImageError)
    }

    private let loadBehavior: LoadBehavior

    public init(load: LoadBehavior = .placeholder) {
        loadBehavior = load
    }

    public func prepareCardPhoto(from original: Data) async throws -> PreparedCardPhoto {
        PreparedCardPhoto(jpegData: original, facesBlurred: 1)
    }

    public func loadPrivateImage(_ source: PrivateImageSource) async throws(PrivateImageError) -> PrivateImage {
        switch loadBehavior {
        case let .fail(error):
            throw error
        case .placeholder:
            return PrivateImage(image: Self.placeholder(for: source))
        }
    }

    private static func placeholder(for source: PrivateImageSource) -> UIImage {
        let size = CGSize(width: 400, height: 500)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let shade: CGFloat = switch source {
            case .card: 0.22
            case let .matchPhoto(_, index): 0.28 + CGFloat(index) * 0.06
            }
            UIColor(white: shade, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
