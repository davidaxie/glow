import APIClient
import AppCore
import Foundation
import Testing
@testable import Location

/// FixSelector: which of CoreLocation's fixes gets sent for a room check.
struct FixSelectorTests {
    let start = Date(timeIntervalSince1970: 1_793_000_000)

    func fix(accuracy: Double, age: TimeInterval = 0, latitude: Double = 37.8029) -> LocationFix {
        LocationFix(latitude: latitude, longitude: -122.4484, accuracy: accuracy, timestamp: start.addingTimeInterval(-age))
    }

    @Test func takesAPreciseFixAtOnce() {
        var selector = FixSelector(startedAt: start)
        let good = fix(accuracy: 8)
        #expect(selector.offer(good, elapsed: .milliseconds(200)) == good)
    }

    @Test func waitsForBetterThenLowersTheBar() {
        var selector = FixSelector(startedAt: start)
        #expect(selector.offer(fix(accuracy: 60), elapsed: .seconds(1)) == nil)
        // From 3 s, 65 m is good enough, and the best so far is sent.
        #expect(selector.offer(fix(accuracy: 64), elapsed: .seconds(3)) == fix(accuracy: 60))
    }

    @Test func acceptsUpToTheServerCreditAfterSixSeconds() {
        var selector = FixSelector(startedAt: start)
        #expect(selector.offer(fix(accuracy: 99), elapsed: .seconds(5)) == nil)
        #expect(selector.offer(fix(accuracy: 99), elapsed: .seconds(6)) == fix(accuracy: 99))
    }

    @Test func atTheTimeLimitSendsTheBestFixTheServerCouldAccept() {
        var selector = FixSelector(startedAt: start)
        _ = selector.offer(fix(accuracy: 300), elapsed: .seconds(1))
        _ = selector.offer(fix(accuracy: 180), elapsed: .seconds(2))
        _ = selector.offer(fix(accuracy: 250), elapsed: .seconds(9))
        #expect(selector.finalFix() == fix(accuracy: 180))
    }

    @Test func atTheTimeLimitSendsNothingTooRough() {
        var selector = FixSelector(startedAt: start)
        _ = selector.offer(fix(accuracy: GlowConstants.geoMaxAccuracyMeters + 1), elapsed: .seconds(1))
        #expect(selector.finalFix() == nil)
    }

    @Test func ignoresCachedFixesFromBeforeTheCheck() {
        var selector = FixSelector(startedAt: start)
        #expect(selector.offer(fix(accuracy: 5, age: 30), elapsed: .zero) == nil)
        #expect(selector.best == nil)
        #expect(selector.offer(fix(accuracy: 5, age: 1), elapsed: .zero) != nil)
    }

    @Test func ignoresInvalidFixes() {
        var selector = FixSelector(startedAt: start)
        #expect(selector.offer(fix(accuracy: -1), elapsed: .seconds(9)) == nil)
        #expect(selector.offer(fix(accuracy: .nan), elapsed: .seconds(9)) == nil)
        #expect(selector.offer(fix(accuracy: 5, latitude: 91), elapsed: .seconds(9)) == nil)
        #expect(selector.finalFix() == nil)
    }

    @Test func thresholdsFollowTheSteps() {
        let selector = FixSelector(startedAt: start)
        #expect(selector.threshold(after: .zero) == 25)
        #expect(selector.threshold(after: .milliseconds(2999)) == 25)
        #expect(selector.threshold(after: .seconds(3)) == 65)
        #expect(selector.threshold(after: .seconds(10)) == GlowConstants.geoAccuracyCreditMeters)
    }
}

struct LocationModuleTests {
    @Test func liveFactoryReturnsTheCoreLocationService() {
        let context = ServiceContext(config: .preview, api: .mock(), session: PreviewSessionService(), analytics: NoopAnalytics())
        #expect(LocationModule.live(context) is LiveLocationService)
    }

    @Test func fixesNeverPrintTheirCoordinates() {
        let fix = LocationFix(latitude: 37.80291357, longitude: -122.44842468, accuracy: 7.31, timestamp: .now)
        let printed = "\(fix) \(String(reflecting: fix)) \(Mirror(reflecting: fix).children.count)"
        #expect(!printed.contains("37.8"))
        #expect(!printed.contains("122.4"))
        #expect(!printed.contains("7.31"))
    }
}

/// The AppCore mock, which every feature's previews and tests use.
struct PreviewLocationServiceTests {
    @Test func approximateThrowsApproximateOnly() async {
        let service = PreviewLocationService(authorization: .approximate)
        await #expect(throws: LocationError.approximateOnly) { try await service.currentFix(timeout: .seconds(1)) }
    }

    @Test func requestingCanGrantPrecise() async throws {
        let service = PreviewLocationService(authorization: .notDetermined, requestedAuthorization: .precise)
        #expect(await service.requestAuthorization() == .precise)
        _ = try await service.currentFix(timeout: .seconds(1))
    }

    @Test func throwsTheErrorItIsGiven() async {
        let service = PreviewLocationService(error: .timedOut)
        await #expect(throws: LocationError.timedOut) { try await service.currentFix(timeout: .seconds(1)) }
    }
}
