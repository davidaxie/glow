import AppCore
import CoreLocation
import os

/// The real location service: CoreLocation, When In Use, precise, one fresh fix per check.
///
/// - Asks for When In Use only when a room check needs it. If the person allowed only approximate
///   location, asks for temporary full accuracy for this check (purpose key `RoomCheck` in the
///   app's Info.plist), which iOS forgets again when the app leaves the foreground.
/// - `currentFix` turns location updates on, takes one fix that `FixSelector` likes, and turns
///   them straight off again. Nothing is kept: the fix goes to the caller and this object
///   forgets it (P2). Nothing about a fix is ever logged.
@MainActor
public final class LiveLocationService: NSObject, LocationService {
    /// `NSLocationTemporaryUsageDescriptionDictionary` key in ios/Glow/Info.plist.
    public static let purposeKey = "RoomCheck"

    private enum Sample: Sendable {
        case fix(LocationFix)
        case denied
    }

    private var manager: CLLocationManager?
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    private var sampleSink: AsyncStream<Sample>.Continuation?
    private let logger = Logger(subsystem: Log.subsystem, category: "location")

    /// Cheap and safe from anywhere: the CLLocationManager is made on the main actor at first use.
    override public nonisolated init() {
        super.init()
    }

    // MARK: LocationService

    public func authorization() async -> LocationAuthorization {
        currentAuthorization()
    }

    public func requestAuthorization() async -> LocationAuthorization {
        let manager = ensureManager()
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                authorizationWaiters.append(continuation)
                manager.requestWhenInUseAuthorization()
            }
        }
        if currentAuthorization() == .approximate {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: Self.purposeKey) { _ in
                    continuation.resume()
                }
            }
        }
        let result = currentAuthorization()
        logger.info("Location authorization: \(String(describing: result), privacy: .public)")
        return result
    }

    public func currentFix(timeout: Duration) async throws -> LocationFix {
        switch currentAuthorization() {
        case .precise: break
        case .approximate: throw LocationError.approximateOnly
        case .denied, .restricted, .notDetermined: throw LocationError.denied
        }
        let manager = ensureManager()
        stopSampling()

        let clock = ContinuousClock()
        let started = clock.now
        var selector = FixSelector(startedAt: Date())
        let (stream, sink) = AsyncStream<Sample>.makeStream(bufferingPolicy: .bufferingNewest(16))
        sampleSink = sink
        let timer = Task {
            try? await Task.sleep(for: timeout)
            sink.finish()
        }
        defer {
            timer.cancel()
            stopSampling()
        }

        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.startUpdatingLocation()

        for await sample in stream {
            switch sample {
            case let .fix(fix):
                if let chosen = selector.offer(fix, elapsed: clock.now - started) {
                    logger.info("Location fix ready")
                    return chosen
                }
            case .denied:
                throw LocationError.denied
            }
        }
        try Task.checkCancellation()
        if let fix = selector.finalFix() {
            logger.info("Location fix ready at the time limit")
            return fix
        }
        logger.notice("No usable location fix in time")
        throw LocationError.timedOut
    }

    // MARK: Internals

    private func ensureManager() -> CLLocationManager {
        if let manager {
            return manager
        }
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        self.manager = manager
        return manager
    }

    private func currentAuthorization() -> LocationAuthorization {
        let manager = ensureManager()
        switch manager.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorizedAlways, .authorizedWhenInUse:
            return manager.accuracyAuthorization == .fullAccuracy ? .precise : .approximate
        @unknown default: return .denied
        }
    }

    private func stopSampling() {
        manager?.stopUpdatingLocation()
        sampleSink?.finish()
        sampleSink = nil
    }

    fileprivate func authorizationChanged(to status: CLAuthorizationStatus) {
        guard status != .notDetermined else { return }
        let waiters = authorizationWaiters
        authorizationWaiters = []
        waiters.forEach { $0.resume() }
        if status == .denied || status == .restricted {
            sampleSink?.yield(.denied)
        }
    }

    fileprivate func received(_ fixes: [LocationFix]) {
        for fix in fixes {
            sampleSink?.yield(.fix(fix))
        }
    }

    fileprivate func failed(_ code: CLError.Code?) {
        // `locationUnknown` is temporary: CoreLocation keeps trying, and so does the timer.
        if code == .denied {
            sampleSink?.yield(.denied)
        }
    }
}

extension LiveLocationService: CLLocationManagerDelegate {
    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.authorizationChanged(to: status)
        }
    }

    public nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Copied into the redacting LocationFix right away; the CLLocations go no further.
        let fixes = locations.map {
            LocationFix(
                latitude: $0.coordinate.latitude,
                longitude: $0.coordinate.longitude,
                accuracy: $0.horizontalAccuracy,
                timestamp: $0.timestamp,
            )
        }
        Task { @MainActor [weak self] in
            self?.received(fixes)
        }
    }

    public nonisolated func locationManager(_: CLLocationManager, didFailWithError error: any Error) {
        let code = (error as? CLError)?.code
        Task { @MainActor [weak self] in
            self?.failed(code)
        }
    }
}
