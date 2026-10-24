import AppCore
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Imaging

/// The blur pipeline on real faces (P3): every fixture face comes out blurred, and nothing about
/// the original photo survives in the upload.
struct BlurPipelineTests {
    let pipeline = CardPhotoPipeline()
    let detector = VisionDetector()

    @Test(arguments: Fixtures.faceNames)
    func everyFaceFixtureComesOutBlurred(_ name: String) throws {
        let expectedFaces = try #require(Fixtures.faces.first { $0.name == name }?.faces)
        let original = try Fixtures.face(name)
        let originalImage = try CardPhotoPipeline.decode(original, maxDimension: 1920)

        // Vision really does see the faces in the original...
        let before = try detector.faceBoxes(in: originalImage)
        #expect(before.count >= max(1, expectedFaces - 1), "Vision should find the faces in \(name)")

        let photo = try pipeline.prepare(original)

        // ...blurred every one of them...
        #expect(photo.facesBlurred >= before.count)
        // ...and can't find a single face afterwards.
        let after = try detector.faceBoxes(in: Fixtures.cgImage(photo.jpegData))
        #expect(after.isEmpty, "\(after.count) face(s) still visible in \(name)")

        // The detail inside each face box is gone, not just shifted.
        let output = try Fixtures.cgImage(photo.jpegData)
        for box in before {
            let rect = CardPhotoPipeline.grow(box, growth: 0, width: output.width, height: output.height)
            let was = try Detail.edgeEnergy(originalImage, in: rect)
            let now = try Detail.edgeEnergy(output, in: rect)
            #expect(now < was * 0.2, "A face in \(name) kept \(Int(now / max(was, 1) * 100))% of its detail")
        }
    }

    @Test(arguments: Fixtures.faceNames)
    func theUploadCarriesNoMetadata(_ name: String) throws {
        // Fixtures already carry some EXIF; add GPS, device and date on top, as a camera would.
        let original = try Fixtures.withCameraMetadata(Fixtures.face(name))
        let props = Fixtures.properties(original)
        #expect(props[kCGImagePropertyGPSDictionary as String] != nil)

        let photo = try pipeline.prepare(original)

        #expect(!JPEGSanitizer.hasMetadata(photo.jpegData))
        let segments = try JPEGSanitizer.segments(in: photo.jpegData)
        #expect(segments.allSatisfy { !$0.isApplication || $0.isJFIF })
        #expect(!segments.contains { $0.isComment })
        let out = Fixtures.properties(photo.jpegData)
        for key in Fixtures.revealingKeys {
            #expect(out[key] == nil, "\(key) survived in \(name)")
        }
        // Nothing of the original's text is anywhere in the bytes.
        for needle in ["iPhone 17 Pro", "private note", "2026:10:24", "NASA", "Portrait"] {
            #expect(photo.jpegData.range(of: Data(needle.utf8)) == nil, "\"\(needle)\" leaked from \(name)")
        }
    }

    @Test func theOrientationIsAppliedThenForgotten() throws {
        let upright = try Fixtures.face("face-portrait-fincke.jpg")
        let uprightImage = try Fixtures.cgImage(upright)
        // Orientation 6: stored sideways, shown rotated 90 degrees clockwise.
        let sideways = try Fixtures.withCameraMetadata(upright, orientation: 6)
        let photo = try pipeline.prepare(sideways)
        #expect(photo.pixelWidth == uprightImage.height)
        #expect(photo.pixelHeight == uprightImage.width)
        #expect(Fixtures.properties(photo.jpegData)[kCGImagePropertyOrientation as String] == nil)
    }

    @Test func outputIsAtMostPhotoMaxDimension() throws {
        let big = try Upscale.jpeg(Fixtures.face("faces-group-of-3.jpg"), longSide: 3000)
        let photo = try pipeline.prepare(big)
        #expect(max(photo.pixelWidth, photo.pixelHeight) == 1920)
        #expect(photo.jpegData.count < 3_000_000)
    }

    @Test func aPhotoWithNobodyInItAsksForARetake() throws {
        let empty = try Upscale.solidJPEG(width: 600, height: 800)
        #expect(throws: ImagingError.noPersonFound) {
            try pipeline.prepare(empty)
        }
    }

    @Test(arguments: Fixtures.realOutfits)
    func neckDownOutfitPhotosGoThroughUntouched(_ name: String) throws {
        let original = try Fixtures.outfit(name)
        let photo = try pipeline.prepare(original)
        #expect(photo.facesBlurred == 0)
        #expect(!JPEGSanitizer.hasMetadata(photo.jpegData))
        let image = try Fixtures.cgImage(original)
        #expect(photo.pixelWidth == image.width)
        #expect(photo.pixelHeight == image.height)
    }

    /// Spec step 4: nobody in the photo means a retake. Vision doesn't see drawings as people.
    @Test(arguments: Fixtures.syntheticOutfits)
    func drawingsOfPeopleAskForARetake(_ name: String) throws {
        let original = try Fixtures.outfit(name)
        #expect(throws: ImagingError.noPersonFound) {
            try pipeline.prepare(original)
        }
    }

    @Test func somethingThatIsNotAnImageIsUnreadable() {
        #expect(throws: ImagingError.unreadableImage) {
            try pipeline.prepare(Data("not an image".utf8))
        }
    }

    @Test func faceBoxesGrowThirtyPercentOnEverySide() {
        let box = CardPhotoPipeline.grow(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), growth: 0.3, width: 1000, height: 1000)
        #expect(box == CGRect(x: 340, y: 340, width: 320, height: 320))
        // Clamped to the photo at the edges.
        let edge = CardPhotoPipeline.grow(CGRect(x: 0, y: 0, width: 0.2, height: 0.2), growth: 0.3, width: 1000, height: 1000)
        #expect(edge == CGRect(x: 0, y: 0, width: 260, height: 260))
    }

    @Test func theLiveServiceRunsThePipeline() async throws {
        let context = ServiceContext(config: .preview, api: .mock(), session: PreviewSessionService(), analytics: NoopAnalytics())
        let service = ImagingModule.live(context)
        let photo = try await service.prepareCardPhoto(from: Fixtures.face("face-portrait-mann.jpg"))
        #expect(photo.facesBlurred >= 1)
        #expect(!JPEGSanitizer.hasMetadata(photo.jpegData))
    }
}

/// How much fine detail (edges) an image region has: the mean absolute difference between
/// neighboring pixels' brightness. A face has plenty; a blurred, pixelated box has almost none.
enum Detail {
    static func edgeEnergy(_ image: CGImage, in rect: CGRect) throws -> Double {
        // Vision and Core Image use a bottom-left origin; CGImage cropping uses top-left.
        let flipped = CGRect(x: rect.minX, y: CGFloat(image.height) - rect.maxY, width: rect.width, height: rect.height).integral
        guard let crop = image.cropping(to: flipped) else { throw Fixtures.Missing() }
        let width = crop.width
        let height = crop.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue,
        ) else { throw Fixtures.Missing() }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        var total = 0
        var count = 0
        for y in 0 ..< height {
            for x in 1 ..< width {
                total += abs(Int(pixels[y * width + x]) - Int(pixels[y * width + x - 1]))
                count += 1
            }
        }
        return count == 0 ? 0 : Double(total) / Double(count)
    }
}

enum Upscale {
    static func jpeg(_ data: Data, longSide: Int) throws -> Data {
        let image = try Fixtures.cgImage(data)
        let scale = Double(longSide) / Double(max(image.width, image.height))
        let width = Int(Double(image.width) * scale)
        let height = Int(Double(image.height) * scale)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
        ) else { throw Fixtures.Missing() }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let big = context.makeImage() else { throw Fixtures.Missing() }
        return try CardPhotoPipeline.exportJPEG(big, quality: 0.9)
    }

    static func solidJPEG(width: Int, height: Int) throws -> Data {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
        ) else { throw Fixtures.Missing() }
        context.setFillColor(CGColor(red: 0.3, green: 0.4, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw Fixtures.Missing() }
        return try CardPhotoPipeline.exportJPEG(image, quality: 0.9)
    }
}
