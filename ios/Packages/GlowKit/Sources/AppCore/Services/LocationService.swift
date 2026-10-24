import Foundation

// Owner: B2 (Location), from Wave 1 (D40). Changes here go with Mocks/PreviewLocationService.swift.

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
    /// Location is off for Glow (denied or restricted). Settings is the only way back.
    case denied
    /// The person kept approximate location and declined precise for this check.
    case approximateOnly
    /// No usable fix arrived in time: weak signal. Try near a window or door.
    case timedOut
    /// Location services are off for the whole phone, or the hardware gave up.
    case unavailable
}

/// One precise When In Use fix for room checks (docs/SPEC.md, Location check).
///
/// The live service (Location module) keeps nothing: each fix goes to one request and is dropped.
public protocol LocationService: Sendable {
    func authorization() async -> LocationAuthorization
    /// Asks for When In Use if it hasn't been asked yet, then, if only approximate location is
    /// allowed, for temporary full accuracy for this check. Returns where that leaves things.
    func requestAuthorization() async -> LocationAuthorization
    /// One fresh fix, waiting up to `timeout` (LOCATION_FIX_TIMEOUT, 10 seconds).
    /// Throws `LocationError`: `.denied`, `.approximateOnly`, `.timedOut` or `.unavailable`.
    func currentFix(timeout: Duration) async throws -> LocationFix
}
