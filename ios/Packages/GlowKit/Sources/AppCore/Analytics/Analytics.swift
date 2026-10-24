import Foundation
import os

/// Product analytics (PostHog) and error reports (Sentry), behind one protocol.
///
/// Every feature logs its own key moments through this, and never names, photos, coordinates or
/// message text (AGENTS.md: Analytics and errors). The types make that hard to get wrong:
/// event names, property keys and string values must be string literals, and the only other
/// values are Bool and Int. The live implementation also drops sensitive-looking keys and scrubs
/// error reports with `PrivacyScrubber`.
///
/// ```swift
/// dependencies.analytics.track(AnalyticsEvent("room_joined", ["via": "qr", "retries": .int(1)]))
/// ```
public protocol Analytics: Sendable {
    func track(_ event: AnalyticsEvent)
    /// Reports an unexpected error. `context` is a literal that says where it happened.
    func record(_ error: any Error, context: StaticString)
}

/// One analytics event. Anonymous: the app never identifies the person to PostHog.
public struct AnalyticsEvent: Sendable, Hashable {
    public let name: String
    public let properties: [String: AnalyticsValue]

    public init(_ name: StaticString, _ properties: KeyValuePairs<StaticString, AnalyticsValue> = [:]) {
        self.name = name.description
        var values: [String: AnalyticsValue] = [:]
        for (key, value) in properties {
            values[key.description] = value
        }
        self.properties = values
    }
}

/// A property value: a Bool, an Int, or a string literal. Never a runtime string.
public struct AnalyticsValue: Sendable, Hashable, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByStringLiteral
{
    public enum Storage: Sendable, Hashable {
        case bool(Bool)
        case int(Int)
        case literal(String)
    }

    public let storage: Storage

    private init(_ storage: Storage) {
        self.storage = storage
    }

    public static func bool(_ value: Bool) -> Self {
        Self(.bool(value))
    }

    public static func int(_ value: Int) -> Self {
        Self(.int(value))
    }

    public static func literal(_ value: StaticString) -> Self {
        Self(.literal(value.description))
    }

    public init(booleanLiteral value: Bool) {
        self.init(.bool(value))
    }

    public init(integerLiteral value: Int) {
        self.init(.int(value))
    }

    public init(stringLiteral value: StaticString) {
        self.init(.literal(value.description))
    }

    /// The value as a plain Foundation type, for SDKs that take `[String: Any]`.
    public var foundationValue: any Sendable {
        switch storage {
        case let .bool(value): value
        case let .int(value): value
        case let .literal(value): value
        }
    }
}

// MARK: - Implementations for tests and previews

/// Does nothing. Used when the PostHog and Sentry keys are empty, and in previews.
public struct NoopAnalytics: Analytics {
    public init() {}
    public func track(_: AnalyticsEvent) {}
    public func record(_: any Error, context _: StaticString) {}
}

/// Remembers everything it's given, so tests can check what a feature logged.
public final class RecordingAnalytics: Analytics, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (events: [AnalyticsEvent](), errors: [String]()))

    public init() {}

    public var events: [AnalyticsEvent] {
        state.withLock { $0.events }
    }

    /// The contexts errors were recorded with.
    public var errorContexts: [String] {
        state.withLock { $0.errors }
    }

    public func track(_ event: AnalyticsEvent) {
        state.withLock { $0.events.append(event) }
    }

    public func record(_: any Error, context: StaticString) {
        let context = context.description
        state.withLock { $0.errors.append(context) }
    }
}
