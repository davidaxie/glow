import Foundation

/// Always precise, always answers with the same made-up fix.
public struct PreviewLocationService: LocationService {
    public var authorizationResult: LocationAuthorization
    public var fix: LocationFix

    public init(
        authorization: LocationAuthorization = .precise,
        fix: LocationFix = LocationFix(latitude: 0, longitude: 0, accuracy: 10, timestamp: .distantPast),
    ) {
        authorizationResult = authorization
        self.fix = fix
    }

    public func authorization() async -> LocationAuthorization {
        authorizationResult
    }

    public func requestAuthorization() async -> LocationAuthorization {
        authorizationResult
    }

    public func currentFix(timeout _: Duration) async throws -> LocationFix {
        guard authorizationResult == .precise || authorizationResult == .approximate else { throw LocationError.denied }
        return fix
    }
}
