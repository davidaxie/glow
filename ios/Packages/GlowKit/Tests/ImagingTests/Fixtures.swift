import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads fixture photos straight from `ios/fixtures/` in the repo (the Simulator can read the
/// Mac's files), so the photos live in one place for the app, `sim.sh photos` and the tests.
enum Fixtures {
    struct Missing: Error {}

    static let iosDirectory: URL = {
        // ios/Packages/GlowKit/Tests/ImagingTests/Fixtures.swift -> ios/
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 5 {
            url.deleteLastPathComponent()
        }
        return url
    }()

    /// Public-domain photos with visible faces (see ios/fixtures/faces/README.md), with how many
    /// faces each has.
    static let faces: [(name: String, faces: Int)] = [
        ("face-portrait-fincke.jpg", 1),
        ("face-portrait-mann.jpg", 1),
        ("faces-group-of-3.jpg", 3),
        ("faces-group-inflight.jpg", 7),
        ("faces-group-large.jpg", 13),
    ]

    static let faceNames = faces.map(\.name)

    /// Real people's outfits from the neck down, no faces (public-domain crops, see
    /// ios/fixtures/photos/README.md).
    static let realOutfits = ["outfit-real-blue-flightsuit.jpg", "outfit-real-white-suit.jpg", "outfit-real-lightblue-suit.jpg"]

    /// A3's synthetic drawings of a faceless figure. Vision doesn't see them as people.
    static let syntheticOutfits = ["outfit-black-jacket.jpg", "outfit-blue-shirt.jpg", "outfit-green-hoodie.jpg", "outfit-red-top.jpg"]

    static func face(_ name: String) throws -> Data {
        try Data(contentsOf: iosDirectory.appending(path: "fixtures/faces/\(name)"))
    }

    static func outfit(_ name: String) throws -> Data {
        try Data(contentsOf: iosDirectory.appending(path: "fixtures/photos/\(name)"))
    }

    static func cgImage(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw Missing() }
        return image
    }

    /// The image's ImageIO properties: EXIF, GPS, TIFF, IPTC dictionaries and so on.
    static func properties(_ data: Data) -> [String: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return [:] }
        return props
    }

    /// The metadata dictionaries that could say where, when or with what a photo was taken.
    static let revealingKeys: [String] = [
        kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyTIFFDictionary,
        kCGImagePropertyIPTCDictionary, kCGImagePropertyExifAuxDictionary, kCGImagePropertyMakerAppleDictionary,
    ].map { $0 as String }

    /// Re-encodes `data` with camera-style metadata: GPS coordinates, a device make and model,
    /// a capture date, a comment and an orientation.
    static func withCameraMetadata(_ data: Data, orientation: Int = 1) throws -> Data {
        let image = try cgImage(data)
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw Missing()
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 37.8029,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.4484,
                kCGImagePropertyGPSLongitudeRef: "W",
            ],
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Apple",
                kCGImagePropertyTIFFModel: "iPhone 17 Pro",
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:10:24 20:15:00",
                kCGImagePropertyExifUserComment: "private note",
            ],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Missing() }
        return out as Data
    }
}
