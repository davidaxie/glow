import APIClient
import AppCore
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreML
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// The on-device private image pipeline (spec: Private images on device, steps 2 to 6).
///
/// 1. Decode, apply the camera's orientation, and scale to at most PHOTO_MAX_DIMENSION.
/// 2. Find faces with Vision's face rectangle request, and grow each box by FACE_BOX_GROWTH on
///    every side.
/// 3. Blur inside each box with Core Image: a strong Gaussian blur, then coarse pixelation.
/// 4. Check again: if Vision still finds a face, blur that too, and give up rather than upload if
///    one survives a second pass.
/// 5. Check there's a person (Vision's human rectangle request). If nobody is there, retake.
/// 6. Export a JPEG at PHOTO_JPEG_QUALITY in sRGB, then strip every metadata segment.
///
/// The original is only read. Nothing here writes to disk.
public struct CardPhotoPipeline: Sendable {
    public struct Settings: Sendable, Equatable {
        public var maxDimension: Int
        public var jpegQuality: Double
        /// Fraction of the box's width (or height) added on each side.
        public var faceBoxGrowth: Double
        /// Blocks across a blurred face box. Fewer blocks, less left to recover.
        public var pixelBlocksAcross: Double
        public var requirePerson: Bool

        public init(
            maxDimension: Int = GlowConstants.photoMaxDimensionPixels,
            jpegQuality: Double = Double(GlowConstants.photoJPEGQualityPercent) / 100,
            faceBoxGrowth: Double = Double(GlowConstants.faceBoxGrowthPercent) / 100,
            pixelBlocksAcross: Double = 6,
            requirePerson: Bool = true,
        ) {
            self.maxDimension = maxDimension
            self.jpegQuality = jpegQuality
            self.faceBoxGrowth = faceBoxGrowth
            self.pixelBlocksAcross = pixelBlocksAcross
            self.requirePerson = requirePerson
        }

        public static let standard = Settings()
    }

    public let settings: Settings

    public init(settings: Settings = .standard) {
        self.settings = settings
    }

    /// Runs the whole pipeline. Throws `ImagingError`.
    public func prepare(_ original: Data) throws -> PreparedCardPhoto {
        let image = try Self.decode(original, maxDimension: settings.maxDimension)
        let detector = VisionDetector()

        let faces = try detector.faceBoxes(in: image)
        if settings.requirePerson, faces.isEmpty, try !detector.containsPerson(image) {
            throw ImagingError.noPersonFound
        }

        var output = image
        var blurred = 0
        var pending = faces
        // A face that survives one pass gets a second; one that survives two stops the upload.
        for _ in 0 ..< 2 where !pending.isEmpty {
            output = try blur(boxes: pending, in: output)
            blurred += pending.count
            pending = try detector.faceBoxes(in: output)
        }
        guard pending.isEmpty else { throw ImagingError.processingFailed }

        let jpeg = try Self.exportJPEG(output, quality: settings.jpegQuality)
        return PreparedCardPhoto(jpegData: jpeg, facesBlurred: blurred, pixelWidth: output.width, pixelHeight: output.height)
    }

    // MARK: - Steps

    /// Decodes with the orientation applied, at most `maxDimension` on the long side.
    static func decode(_ data: Data, maxDimension: Int) throws -> CGImage {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              CGImageSourceGetCount(source) > 0
        else { throw ImagingError.unreadableImage }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            throw ImagingError.unreadableImage
        }
        // Redraw into plain 8-bit sRGB, so nothing about the source's format carries over.
        return try redraw(decoded)
    }

    static func redraw(_ image: CGImage) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: image.width,
                  height: image.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
              )
        else { throw ImagingError.processingFailed }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let redrawn = context.makeImage() else { throw ImagingError.processingFailed }
        return redrawn
    }

    /// Grows a normalized Vision box (origin bottom left) by `growth` on every side, in pixels,
    /// clamped to the image.
    static func grow(_ normalized: CGRect, growth: Double, width: Int, height: Int) -> CGRect {
        let box = VNImageRectForNormalizedRect(normalized, width, height)
        let grown = box.insetBy(dx: -box.width * growth, dy: -box.height * growth)
        return grown.intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
    }

    func blur(boxes: [CGRect], in image: CGImage) throws -> CGImage {
        let context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
            .cacheIntermediates: false,
            .useSoftwareRenderer: false,
        ])
        let source = CIImage(cgImage: image)
        var output = source
        for normalized in boxes {
            let box = Self.grow(normalized, growth: settings.faceBoxGrowth, width: image.width, height: image.height)
            guard box.width >= 1, box.height >= 1 else { continue }
            let side = max(box.width, box.height)

            // Strong blur first (sampled from beyond the box, so edges don't leak sharp pixels)...
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = source.cropped(to: box).clampedToExtent()
            blur.radius = Float(max(24, side * 0.2))

            // ...then coarse blocks, so whatever the blur left is averaged away.
            let pixellate = CIFilter.pixellate()
            pixellate.inputImage = blur.outputImage
            pixellate.scale = Float(max(12, side / settings.pixelBlocksAcross))
            pixellate.center = CGPoint(x: box.minX, y: box.minY)

            guard let covered = pixellate.outputImage?.cropped(to: box) else { throw ImagingError.processingFailed }
            output = covered.composited(over: output)
        }
        guard let rendered = context.createCGImage(
            output,
            from: source.extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB),
        ) else { throw ImagingError.processingFailed }
        return try Self.redraw(rendered)
    }

    /// JPEG at `quality` with no properties, then every metadata segment stripped.
    static func exportJPEG(_ image: CGImage, quality: Double) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImagingError.processingFailed
        }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw ImagingError.processingFailed }
        do {
            return try JPEGSanitizer.strip(data as Data)
        } catch {
            throw ImagingError.processingFailed
        }
    }
}

/// Vision requests, run synchronously on the calling thread.
struct VisionDetector {
    /// Normalized face boxes (origin bottom left).
    func faceBoxes(in image: CGImage) throws -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        Self.preferCPUInSimulator(request)
        try perform(request, on: image)
        return (request.results ?? []).map(\.boundingBox)
    }

    /// True if Vision sees at least one person, whole body or upper body.
    func containsPerson(_ image: CGImage) throws -> Bool {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        Self.preferCPUInSimulator(request)
        try perform(request, on: image)
        return !(request.results ?? []).isEmpty
    }

    private func perform(_ request: VNRequest, on image: CGImage) throws {
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw ImagingError.processingFailed
        }
    }

    /// The Simulator has no Neural Engine; some Vision revisions fail there unless they run on the CPU.
    private static func preferCPUInSimulator(_ request: VNRequest) {
        #if targetEnvironment(simulator)
            if let devices = try? request.supportedComputeStageDevices,
               let cpu = devices[.main]?.first(where: {
                   if case .cpu = $0 {
                       true
                   } else {
                       false
                   }
               })
            {
                request.setComputeDevice(cpu, for: .main)
            }
        #endif
    }
}
