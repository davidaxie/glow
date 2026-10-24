import APIClient
import AppCore
import Foundation

/// Every way joining a room can stop, each with its own friendly screen.
public enum JoinFailure: Error, Hashable, Sendable {
    /// The location check said outside the room (422 `not_in_room`).
    case notInRoom
    /// No good fix in time, or a fix too rough to use: try near a window or door.
    case weakSignal
    case roomEnded
    case roomPaused
    /// The room closed between looking it up and the check (409 `room_not_live`). The join flow
    /// looks the room up again to say whether it ended or paused.
    case roomClosed
    case roomNotOpenYet(Date)
    /// A wrong or old code or token (404).
    case roomNotFound
    /// A rotating screen code went stale between scanning and the check (404 on join).
    case codeChanged
    case locationDenied
    /// Only approximate location, and precise was declined for this check.
    case preciseLocationOff
    /// Location Services are off for the whole phone.
    case locationUnavailable
    case onboardingIncomplete
    case offline
    case rateLimited
    case unexpected

    init(_ error: LocationError) {
        switch error {
        case .denied: self = .locationDenied
        case .approximateOnly: self = .preciseLocationOff
        case .timedOut: self = .weakSignal
        case .unavailable: self = .locationUnavailable
        }
    }

    init(_ error: APIError) {
        switch error {
        case .notFound: self = .roomNotFound
        case .rateLimited: self = .rateLimited
        case .offline: self = .offline
        case .unauthorized, .cancelled, .unexpected: self = .unexpected
        }
    }

    /// For analytics and logs: a fixed literal per case, never a date or any text.
    var analyticsName: AnalyticsValue {
        .literal(name)
    }

    var name: StaticString {
        switch self {
        case .notInRoom: "not_in_room"
        case .weakSignal: "weak_signal"
        case .roomEnded: "room_ended"
        case .roomPaused: "room_paused"
        case .roomClosed: "room_closed"
        case .roomNotOpenYet: "room_not_open_yet"
        case .roomNotFound: "room_not_found"
        case .codeChanged: "code_changed"
        case .locationDenied: "location_denied"
        case .preciseLocationOff: "precise_location_off"
        case .locationUnavailable: "location_unavailable"
        case .onboardingIncomplete: "onboarding_incomplete"
        case .offline: "offline"
        case .rateLimited: "rate_limited"
        case .unexpected: "unexpected"
        }
    }

    /// What the failure screen offers first.
    enum Action: Hashable, Sendable {
        case tryAgain
        case openSettings
        case scanAgain
        case typeCode
        case backToRooms
    }

    var primaryAction: Action {
        switch self {
        case .notInRoom, .weakSignal, .roomPaused, .offline, .rateLimited, .unexpected, .preciseLocationOff: .tryAgain
        case .locationDenied, .locationUnavailable: .openSettings
        case .codeChanged: .scanAgain
        case .roomNotFound: .typeCode
        case .roomEnded, .roomClosed, .roomNotOpenYet, .onboardingIncomplete: .backToRooms
        }
    }

    /// Whether the location check runs again on "Try again", or the room lookup too.
    var retriesLookup: Bool {
        switch self {
        case .roomPaused, .offline, .rateLimited, .unexpected: true
        default: false
        }
    }
}
