import APIClient
import AppCore
import Foundation
import Observation

/// The profile form's state and rules, shared by onboarding's profile step and Settings'
/// Edit profile: first name, birthday, gender and who you want to see.
///
/// The 18+ check runs on the phone first, so an under-18 birthday never even leaves it. The
/// server checks again and refuses (422 `under_18`), and the database refuses it too (P10).
@MainActor
@Observable
public final class ProfileForm {
    public enum Phase: Hashable, Sendable {
        case editing
        case saving
        /// Under 18. Onboarding shows the kind message and goes no further.
        case underAge
    }

    public static let nameLimit = 40

    public var firstName: String
    /// The date picker's value. Starts at today, which is never an adult's birthday, so nobody
    /// is nudged towards an answer (a neutral age gate).
    public var birthday: Date
    /// Becomes true once the person has picked a date. Until then, Continue stays off.
    public var birthdayChosen: Bool
    public var gender: Components.Schemas.Gender?
    public var showMe: Set<Components.Schemas.Gender>
    public private(set) var phase: Phase = .editing
    public var error: ProfileError?

    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        existing profile: Components.Schemas.MyProfile? = nil,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
    ) {
        self.calendar = calendar
        self.now = now
        firstName = profile?.firstName ?? ""
        gender = profile?.gender
        showMe = Set(profile?.showMe ?? [])
        if let saved = profile?.birthdate.flatMap({ Self.date(fromISO: $0, calendar: calendar) }) {
            birthday = saved
            birthdayChosen = true
        } else {
            birthday = now()
            birthdayChosen = false
        }
    }

    public var trimmedName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every field filled in and within limits.
    public var isComplete: Bool {
        !trimmedName.isEmpty && trimmedName.count <= Self.nameLimit && birthdayChosen && gender != nil && !showMe.isEmpty
    }

    public var canSave: Bool {
        isComplete && phase == .editing
    }

    /// The latest date the picker offers. Later dates can't be anyone's birthday.
    public var latestBirthday: Date {
        now()
    }

    public func pickBirthday(_ date: Date) {
        birthday = date
        birthdayChosen = true
    }

    public func toggleShowMe(_ value: Components.Schemas.Gender) {
        if showMe.contains(value) {
            showMe.remove(value)
        } else {
            showMe.insert(value)
        }
    }

    /// The day the person picked, as `YYYY-MM-DD`.
    public var birthdateISO: String? {
        guard birthdayChosen else { return nil }
        return AgeGate.isoDate(AgeGate.birthday(from: birthday, in: calendar))
    }

    public var isAdult: Bool {
        AgeGate.isAdult(birthday: AgeGate.birthday(from: birthday, in: calendar), now: now())
    }

    /// The request body, in contract order. Show me keeps a stable order: women, men, nonbinary.
    public var update: Components.Schemas.ProfileUpdate? {
        guard isComplete, let gender, let birthdate = birthdateISO else { return nil }
        let order = Components.Schemas.Gender.allCases
        return .init(firstName: trimmedName, birthdate: birthdate, gender: gender, showMe: order.filter(showMe.contains))
    }

    /// Saves through `client`. Returns true when the profile was saved.
    ///
    /// Under 18: nothing is sent, `phase` becomes `.underAge`, and when `closeGate` is set (the
    /// onboarding step) the profile step stays closed on this phone (`AgeGateLock`).
    @discardableResult
    public func save(using client: ProfileClient, closeGate lock: AgeGateLock? = nil) async -> Bool {
        guard canSave, let update else { return false }
        error = nil
        guard isAdult else {
            refuseUnderAge(lock)
            return false
        }
        phase = .saving
        do {
            try await client.save(update)
            phase = .editing
            return true
        } catch .under18 {
            refuseUnderAge(lock)
            return false
        } catch {
            self.error = error
            phase = .editing
            return false
        }
    }

    private func refuseUnderAge(_ lock: AgeGateLock?) {
        lock?.close()
        phase = .underAge
    }

    /// Back to editing after the under-18 message, for Settings (onboarding stays closed).
    public func dismissUnderAge() {
        phase = .editing
    }

    /// A `YYYY-MM-DD` date at noon in `calendar`, or nil.
    public static func date(fromISO value: String, calendar: Calendar = .current) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        // Noon, so the day can't shift in any timezone the phone moves to.
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}
