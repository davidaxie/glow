import Foundation

// Owner from Wave 1: B2 (Location). A3 wrote this first shape; B2 may change this file and
// Mocks/PreviewLocationService.swift together.

public enum LocationAuthorization: Hashable, Sendable {
    case notDetermined
    case denied
    case restricted
    /// When In Use, but only approximate. Ask for temporary full accuracy before a room check.
    case approximate
    /// When In Use, precise.
    case precise
}

/// One location fix, used for a single room check and then dropped.
///
/// Coordinates are never stored or logged (P2). `description`, `debugDescription` and the mirror
/// are redacted, so `print`, string interpolation and `dump` can't leak them by accident.
public struct LocationFix: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let latitude: Double
    public let longitude: Double
    /// Horizontal accuracy in meters.
    public let accuracy: Double
    public let timestamp: Date

    public init(latitude: Double, longitude: Double, accuracy: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.timestamp = timestamp
    }

    public var description: String {
        "LocationFix(redacted)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}

public enum LocationError: Error, Hashable, Sendable {
    case denied
    case timedOut
    case unavailable
}

/// One precise When In Use fix for room checks.
public protocol LocationService: Sendable {
    func authorization() async -> LocationAuthorization
    /// Asks for When In Use (and temporary full accuracy if needed). Returns the result.
    func requestAuthorization() async -> LocationAuthorization
    /// One fresh fix, waiting up to `timeout` (the spec says 10 seconds).
    func currentFix(timeout: Duration) async throws -> LocationFix
}
