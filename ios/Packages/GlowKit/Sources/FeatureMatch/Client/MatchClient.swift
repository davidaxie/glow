import APIClient
import AppCore
import Foundation
import SwiftUI

/// What FeatureMatch needs from the server. `APIMatchClient` is the real one; previews, tests and
/// the Debug fixtures (`-GlowMatchFixtures <scenario>`) use `FixtureMatchClient`.
public protocol MatchClient: Sendable {
    /// One match from my side. Throws `.notFound` once it has ended.
    func match(_ id: MatchID) async throws(MatchError) -> MatchSnapshot
    /// Find (with a fresh fix) or Chat.
    func choose(_ choice: MatchSnapshot.Choice, for id: MatchID, fix: LocationFix?) async throws(MatchError) -> ChoiceOutcome
    /// My matches that haven't ended, newest first.
    func matches() async throws(MatchError) -> [MatchSummary]
    /// Events this client makes up itself. Only the Debug fixtures have any; the live client's
    /// events come from Realtime.
    func events() -> AsyncStream<MatchEvent>
}

/// A match event, from Realtime, a push, or the Debug fixtures. Only ever a kind and a match ID.
public struct MatchEvent: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case created = "match.created"
        case choice = "match.choice"
        case recheck = "match.recheck"
        case ended = "match.ended"
        case glowStarted = "glow.started"
        case glowEnded = "glow.ended"
        case messageCreated = "message.created"
    }

    public let kind: Kind
    public let matchID: MatchID

    public init(_ kind: Kind, _ matchID: MatchID) {
        self.kind = kind
        self.matchID = matchID
    }

    /// The match events among Realtime's. Read by the event's type string, so it works with any
    /// shape of `RealtimeEventKind` that keeps the contract's names.
    init?(_ event: RealtimeEvent) {
        guard let kind = Kind(rawValue: event.kind.rawValue), let matchID = event.matchID else { return nil }
        self.init(kind, matchID)
    }
}

extension Dependencies {
    /// Match events from Realtime and from the match client, merged, until cancelled.
    func matchEvents(_ client: any MatchClient) -> AsyncStream<MatchEvent> {
        let realtime = realtime.events()
        let own = client.events()
        return AsyncStream { continuation in
            let fromRealtime = Task {
                for await event in realtime {
                    if let match = MatchEvent(event) {
                        continuation.yield(match)
                    }
                }
            }
            let fromClient = Task {
                for await event in own {
                    continuation.yield(event)
                }
            }
            continuation.onTermination = { _ in
                fromRealtime.cancel()
                fromClient.cancel()
            }
        }
    }
}

// MARK: - Choosing the client

extension EnvironmentValues {
    /// Set to use a particular `MatchClient` (tests and previews). Nil means the app's own: the
    /// API, or the Debug fixtures when launched with `-GlowMatchFixtures <scenario>`.
    @Entry public var matchClient: (any MatchClient)?
}

enum MatchClients {
    /// The client FeatureMatch's screens use.
    static func resolve(_ override: (any MatchClient)?, _ dependencies: Dependencies) -> any MatchClient {
        if let override {
            return override
        }
        #if DEBUG
            if dependencies.config.environment == .debug, let fixtures = FixtureMatchClient.launchFixtures {
                return fixtures
            }
        #endif
        return APIMatchClient(api: dependencies.api)
    }

    /// The services the match screens see. The Debug fixtures never touch the network, so their
    /// photos come from the preview imaging service's placeholders, not B3's API loader (C2-D9).
    static func environment(_ override: (any MatchClient)?, _ dependencies: Dependencies) -> Dependencies {
        #if DEBUG
            if override == nil, dependencies.config.environment == .debug, FixtureMatchClient.launchFixtures != nil {
                var preview = dependencies
                preview.imaging = PreviewImagingService()
                return preview
            }
        #endif
        return dependencies
    }

    /// The location service for Find. The Debug fixtures never touch the network, so they never
    /// ask for a real location either (C2-D9).
    static func location(_ override: (any MatchClient)?, _ dependencies: Dependencies) -> any LocationService {
        #if DEBUG
            if override == nil, dependencies.config.environment == .debug, FixtureMatchClient.launchFixtures != nil {
                return PreviewLocationService()
            }
        #endif
        return dependencies.location
    }
}

// MARK: - The API

/// FeatureMatch over the Glow API: `getMatch`, `setChoice`, `listMatches` and `getMatchPhoto`.
public struct APIMatchClient: MatchClient {
    private let api: GlowAPI

    public init(api: GlowAPI) {
        self.api = api
    }

    public func match(_ id: MatchID) async throws(MatchError) -> MatchSnapshot {
        let output: Operations.GetMatch.Output
        do {
            output = try await api.perform { try await $0.getMatch(path: .init(id: id.rawValue)) }
        } catch {
            throw MatchError(error)
        }
        switch output {
        case let .ok(ok):
            guard case let .json(detail) = ok.body, let snapshot = MatchSnapshot(detail) else { throw .failed }
            return snapshot
        case .notFound: throw .notFound
        case .unauthorized: throw .unauthorized
        case .default: throw .failed
        }
    }

    public func choose(
        _ choice: MatchSnapshot.Choice,
        for id: MatchID,
        fix: LocationFix?,
    ) async throws(MatchError) -> ChoiceOutcome {
        let request = Components.Schemas.ChoiceRequest(
            choice: choice == .find ? .find : .chat,
            location: fix.map { Components.Schemas.LocationFix(latitude: $0.latitude, longitude: $0.longitude, accuracy: $0.accuracy) },
        )
        let output: Operations.SetChoice.Output
        do {
            output = try await api.perform { try await $0.setChoice(path: .init(id: id.rawValue), body: .json(request)) }
        } catch {
            throw MatchError(error)
        }
        switch output {
        case let .ok(ok):
            guard case let .json(result) = ok.body, let outcome = ChoiceOutcome(result) else { throw .failed }
            return outcome
        case let .unprocessableContent(response):
            guard case let .json(body) = response.body else { throw .failed }
            throw Self.locationRefusal(body.error.code)
        case .notFound: throw .notFound
        case .unauthorized: throw .unauthorized
        case .tooManyRequests: throw .rateLimited
        case .badRequest, .default: throw .failed
        }
    }

    /// A 422 from Find: outside the room, or a fix too rough (or a check gone stale) to use.
    static func locationRefusal(_ code: Components.Schemas.ErrorCode) -> MatchError {
        switch code {
        case .notInRoom: .notInRoom
        // The server refused a fix that was too rough, or a stale check: try a fresh fix.
        case .locationInaccurate, .locationRequired: .locationInaccurate
        default: .failed
        }
    }

    public func matches() async throws(MatchError) -> [MatchSummary] {
        let output: Operations.ListMatches.Output
        do {
            output = try await api.perform { try await $0.listMatches() }
        } catch {
            throw MatchError(error)
        }
        switch output {
        case let .ok(ok):
            guard case let .json(list) = ok.body else { throw .failed }
            return list.matches.compactMap(MatchSummary.init)
        case .unauthorized: throw .unauthorized
        case .tooManyRequests: throw .rateLimited
        case .default: throw .failed
        }
    }

    public func events() -> AsyncStream<MatchEvent> {
        AsyncStream { $0.finish() }
    }
}
