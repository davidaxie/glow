import Foundation

// Owner: B2, from Wave 1 (D40). Changes here go with Services/LocationService.swift.

/// A location service that never touches CoreLocation. Answers with a made-up fix, or with
/// whatever authorization, error and delay a preview or test asks for.
public struct PreviewLocationService: LocationService {
    public var authorizationResult: LocationAuthorization
    /// What `requestAuthorization()` moves to. Defaults to `authorizationResult`.
    public var requestedAuthorization: LocationAuthorization?
    public var fix: LocationFix
    /// Thrown by `currentFix` instead of answering, when set.
    public var error: LocationError?
    /// How long `currentFix` takes, so previews can show the "checking" state.
    public var delay: Duration

    public init(
        authorization: LocationAuthorization = .precise,
        requestedAuthorization: LocationAuthorization? = nil,
        fix: LocationFix = LocationFix(latitude: 0, longitude: 0, accuracy: 10, timestamp: .distantPast),
        error: LocationError? = nil,
        delay: Duration = .zero,
    ) {
        authorizationResult = authorization
        self.requestedAuthorization = requestedAuthorization
        self.fix = fix
        self.error = error
        self.delay = delay
    }

    public func authorization() async -> LocationAuthorization {
        authorizationResult
    }

    public func requestAuthorization() async -> LocationAuthorization {
        requestedAuthorization ?? authorizationResult
    }

    public func currentFix(timeout _: Duration) async throws -> LocationFix {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        if let error {
            throw error
        }
        switch requestedAuthorization ?? authorizationResult {
        case .precise: return fix
        case .approximate: throw LocationError.approximateOnly
        case .denied, .restricted, .notDetermined: throw LocationError.denied
        }
    }
}
