import Foundation

/// Removes every metadata segment from a JPEG: EXIF and GPS (APP1), XMP (APP1), ICC profiles
/// (APP2), Adobe and IPTC (APP13, APP14), maker notes, thumbnails and comments. Only the JFIF
/// header (APP0) and the image data itself survive.
///
/// ImageIO writes no EXIF when it isn't given any, but this makes "no metadata" true by
/// construction, whatever a framework decides to add (P3).
public enum JPEGSanitizer {
    public enum Failure: Error, Equatable {
        case notAJPEG
        case truncated
    }

    /// One marker segment before the image data starts.
    public struct Segment: Equatable, Sendable {
        /// The marker byte after 0xFF, for example 0xE1 for APP1.
        public let marker: UInt8
        /// The segment's payload, without the marker and the length field.
        public let payload: Data

        /// APP0 to APP15.
        public var isApplication: Bool {
            (0xE0 ... 0xEF).contains(marker)
        }

        public var isComment: Bool {
            marker == 0xFE
        }

        /// APP0 that starts with "JFIF\0".
        public var isJFIF: Bool {
            marker == 0xE0 && payload.starts(with: [0x4A, 0x46, 0x49, 0x46, 0x00])
        }
    }

    /// The segments between SOI and the start of the image data (SOS).
    public static func segments(in jpeg: Data) throws(Failure) -> [Segment] {
        try parse(jpeg).segments
    }

    /// The same image with only JFIF and the segments needed to decode it.
    public static func strip(_ jpeg: Data) throws(Failure) -> Data {
        let parsed = try parse(jpeg)
        var out = Data([0xFF, 0xD8])
        for segment in parsed.segments where !(segment.isApplication && !segment.isJFIF) && !segment.isComment {
            let length = segment.payload.count + 2
            out.append(contentsOf: [0xFF, segment.marker, UInt8(length >> 8), UInt8(length & 0xFF)])
            out.append(segment.payload)
        }
        out.append(parsed.imageData)
        return out
    }

    /// True if the JPEG carries anything besides JFIF and decoding segments.
    public static func hasMetadata(_ jpeg: Data) -> Bool {
        guard let segments = try? segments(in: jpeg) else { return true }
        return segments.contains { ($0.isApplication && !$0.isJFIF) || $0.isComment }
    }

    private static func parse(_ jpeg: Data) throws(Failure) -> (segments: [Segment], imageData: Data) {
        let bytes = [UInt8](jpeg)
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { throw .notAJPEG }
        var segments: [Segment] = []
        var index = 2
        while index < bytes.count {
            guard bytes[index] == 0xFF else { throw .notAJPEG }
            // Fill bytes: any number of 0xFF before a marker.
            var markerIndex = index + 1
            while markerIndex < bytes.count, bytes[markerIndex] == 0xFF {
                markerIndex += 1
            }
            guard markerIndex < bytes.count else { throw .truncated }
            let marker = bytes[markerIndex]
            if marker == 0xDA {
                // Start of scan: everything from here (SOS onwards, up to and including EOI)
                // is image data, copied as is.
                return (segments, Data(bytes[index...]))
            }
            if marker == 0xD8 || marker == 0xD9 || (0xD0 ... 0xD7).contains(marker) || marker == 0x01 {
                // Markers without a length don't belong before SOS in a baseline file.
                throw .notAJPEG
            }
            let lengthIndex = markerIndex + 1
            guard lengthIndex + 1 < bytes.count else { throw .truncated }
            let length = Int(bytes[lengthIndex]) << 8 | Int(bytes[lengthIndex + 1])
            guard length >= 2, lengthIndex + length <= bytes.count else { throw .truncated }
            let payload = Data(bytes[(lengthIndex + 2) ..< (lengthIndex + length)])
            segments.append(Segment(marker: marker, payload: payload))
            index = lengthIndex + length
        }
        throw .truncated
    }
}
