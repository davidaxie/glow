import Foundation
import Testing
@testable import Imaging

struct JPEGSanitizerTests {
    /// SOI, APP0 JFIF, APP1 EXIF, APP2 ICC, COM, DQT, then SOS and image data, then EOI.
    static let tagged: Data = {
        var bytes: [UInt8] = [0xFF, 0xD8]
        func segment(_ marker: UInt8, _ payload: [UInt8]) {
            let length = payload.count + 2
            bytes += [0xFF, marker, UInt8(length >> 8), UInt8(length & 0xFF)] + payload
        }
        segment(0xE0, Array("JFIF".utf8) + [0, 1, 1, 0, 0, 1, 0, 1, 0, 0])
        segment(0xE1, Array("Exif".utf8) + [0, 0] + Array("GPS 37.8029".utf8))
        segment(0xE2, Array("ICC_PROFILE".utf8) + [0])
        segment(0xFE, Array("a comment".utf8))
        segment(0xDB, [0, 1, 2, 3])
        bytes += [0xFF, 0xDA, 0x00, 0x04, 0x01, 0x02, 0xAB, 0xCD, 0xFF, 0x00, 0xFF, 0xD9]
        return Data(bytes)
    }()

    @Test func stripsEverythingButJFIFAndDecodingSegments() throws {
        #expect(JPEGSanitizer.hasMetadata(Self.tagged))
        let clean = try JPEGSanitizer.strip(Self.tagged)
        #expect(!JPEGSanitizer.hasMetadata(clean))
        let markers = try JPEGSanitizer.segments(in: clean).map(\.marker)
        #expect(markers == [0xE0, 0xDB])
        #expect(clean.range(of: Data("GPS".utf8)) == nil)
        #expect(clean.range(of: Data("comment".utf8)) == nil)
        // The image data after SOS is untouched.
        #expect(clean.suffix(12) == Self.tagged.suffix(12))
    }

    @Test func refusesWhatIsNotAJPEG() {
        #expect(throws: JPEGSanitizer.Failure.notAJPEG) { try JPEGSanitizer.strip(Data([0x89, 0x50, 0x4E, 0x47])) }
        #expect(throws: JPEGSanitizer.Failure.truncated) { try JPEGSanitizer.strip(Data([0xFF, 0xD8, 0xFF, 0xE1, 0x10])) }
        #expect(JPEGSanitizer.hasMetadata(Data("junk".utf8)))
    }

    @Test func aRealExportDecodesAfterStripping() throws {
        let photo = try CardPhotoPipeline(settings: .init(requirePerson: false)).prepare(Upscale.solidJPEG(width: 64, height: 80))
        let image = try Fixtures.cgImage(photo.jpegData)
        #expect(image.width == 64)
        #expect(image.height == 80)
    }
}
