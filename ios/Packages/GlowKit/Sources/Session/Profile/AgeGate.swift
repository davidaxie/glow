import APIClient
import Foundation

/// The 18+ rule, exactly as the server and the database apply it (P10): someone can use Glow once
/// they're `MIN_AGE` on the calendar date in UTC-12, the last timezone on Earth, so nobody counts
/// as 18 anywhere before it's their birthday everywhere.
public enum AgeGate {
    /// The minimum age, from contracts/constants.json.
    public static var minimumAge: Int {
        GlowConstants.minAgeYears
    }

    private static var lastTimezone: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -12 * 3600)!
        return calendar
    }

    /// The person's birthday as the calendar date they picked. A date picker hands back a moment in
    /// the phone's own timezone, so read the day there.
    public static func birthday(from picked: Date, in calendar: Calendar = .current) -> DateComponents {
        calendar.dateComponents([.year, .month, .day], from: picked)
    }

    /// `YYYY-MM-DD`, as the API takes it.
    public static func isoDate(_ day: DateComponents) -> String? {
        guard let year = day.year, let month = day.month, let date = day.day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, date)
    }

    /// Whether someone born on `birthday` is at least `minimumAge` at `now`.
    public static func isAdult(birthday: DateComponents, now: Date = .now) -> Bool {
        guard let year = birthday.year, let month = birthday.month, let day = birthday.day else { return false }
        let today = lastTimezone.dateComponents([.year, .month, .day], from: now)
        guard let todayYear = today.year, let todayMonth = today.month, let todayDay = today.day else { return false }
        // Today minus minimumAge years, with Feb 29 becoming Feb 28 in a year without one,
        // like Postgres's `date - interval 'N years'`.
        let cutoffYear = todayYear - minimumAge
        let cutoffDay = min(todayDay, daysIn(year: cutoffYear, month: todayMonth))
        return (year, month, day) <= (cutoffYear, todayMonth, cutoffDay)
    }

    private static func daysIn(year: Int, month: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date)
        else { return 28 }
        return range.count
    }
}

/// Remembers, on this phone, that someone answered the birthday question with an age under 18,
/// so the profile step stays closed instead of inviting a second try with a different date.
///
/// Only a yes or no is kept: never the date. It survives signing out but not deleting the app,
/// so an adult who mistyped can still start over. The server never stores the attempt at all.
public struct AgeGateLock: Sendable {
    public let key: String

    public init(key: String = "glow.ageGate.closed") {
        self.key = key
    }

    public var isClosed: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    public func close() {
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Debug builds and tests only reopen it (`-GlowResetAgeGate YES` at launch).
    public func reopen() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
