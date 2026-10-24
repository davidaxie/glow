import APIClient
import AppCore
import Foundation

/// Decides which of the fixes CoreLocation streams in is the one to send.
///
/// The goal is one fresh, good-enough fix fast, inside LOCATION_FIX_TIMEOUT. A fix this precise
/// is taken at once; as time passes the bar drops, and when time runs out the best fix seen so
/// far is used. Stale fixes (cached from before the check started) and invalid ones are ignored,
/// so an old position can never vouch for where someone is now.
///
/// Pure value logic, so it's tested without CoreLocation.
public struct FixSelector: Sendable {
    /// After `elapsed`, take a fix at least this accurate.
    public struct Step: Sendable, Hashable {
        public let after: Duration
        public let accuracy: Double

        public init(after: Duration, accuracy: Double) {
            self.after = after
            self.accuracy = accuracy
        }
    }

    /// Immediately at 25 m, from 3 s at 65 m, from 6 s at 100 m (the most the server credits).
    public static let defaultSteps: [Step] = [
        Step(after: .zero, accuracy: 25),
        Step(after: .seconds(3), accuracy: 65),
        Step(after: .seconds(6), accuracy: GlowConstants.geoAccuracyCreditMeters),
    ]

    /// Fixes older than this before the check started are cached positions, not fresh ones.
    public static let staleness: TimeInterval = 2

    public let startedAt: Date
    public let steps: [Step]
    public private(set) var best: LocationFix?

    public init(startedAt: Date, steps: [Step] = FixSelector.defaultSteps) {
        self.startedAt = startedAt
        self.steps = steps
    }

    /// Whether a fix is fresh and usable at all.
    public func isUsable(_ fix: LocationFix) -> Bool {
        fix.accuracy > 0
            && fix.accuracy.isFinite
            && fix.latitude.isFinite
            && fix.longitude.isFinite
            && (-90 ... 90).contains(fix.latitude)
            && (-180 ... 180).contains(fix.longitude)
            && fix.timestamp >= startedAt.addingTimeInterval(-Self.staleness)
    }

    /// The accuracy that's good enough after `elapsed`.
    public func threshold(after elapsed: Duration) -> Double {
        steps.last(where: { $0.after <= elapsed })?.accuracy ?? 0
    }

    /// Offers one fix. Returns the fix to send now, or nil to keep waiting.
    public mutating func offer(_ fix: LocationFix, elapsed: Duration) -> LocationFix? {
        guard isUsable(fix) else { return nil }
        if fix.accuracy < (best?.accuracy ?? .infinity) {
            best = fix
        }
        guard let best, best.accuracy <= threshold(after: elapsed) else { return nil }
        return best
    }

    /// When time runs out: the best fix seen, if it's one the server could ever accept.
    public func finalFix() -> LocationFix? {
        guard let best, best.accuracy <= GlowConstants.geoMaxAccuracyMeters else { return nil }
        return best
    }
}
