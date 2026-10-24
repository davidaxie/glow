import Foundation
import OpenAPIRuntime

/// ISO 8601 dates, with or without fractional seconds.
///
/// The server sends JavaScript `toISOString()` dates (`2026-10-23T18:00:00.000Z`) and Postgres can
/// send whole seconds; the runtime's default transcoder only accepts the second form.
public struct GlowDateTranscoder: DateTranscoder {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle()

    public init() {}

    public func encode(_ date: Date) throws -> String {
        date.formatted(Self.fractional)
    }

    public func decode(_ string: String) throws -> Date {
        if let date = try? Self.fractional.parse(string) {
            return date
        }
        do {
            return try Self.whole.parse(string)
        } catch {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected an ISO 8601 date."))
        }
    }
}
