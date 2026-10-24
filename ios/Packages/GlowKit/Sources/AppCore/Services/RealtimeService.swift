import APIClient
import Foundation

// Owner: B5 (Realtime). This file and Mocks/PreviewRealtimeService.swift change together.
// The event shapes come from contracts/events.json, through the generated `GlowEvents` and
// `Components.Schemas.GlowEvent`, so a contract change shows up here at compile time.

/// Every event the server sends (spec: Events and push). The generated list, so it never drifts.
public typealias RealtimeEventKind = GlowEvents.EventType

/// An event from the person's private channels or a push. Only ever an event type plus a match or
/// room ID, never a user ID or name (P1). Refetch details from the API.
public struct RealtimeEvent: Hashable, Sendable {
    public let kind: RealtimeEventKind
    public let matchID: MatchID?
    public let roomID: RoomID?

    public init(kind: RealtimeEventKind, matchID: MatchID? = nil, roomID: RoomID? = nil) {
        self.kind = kind
        self.matchID = matchID
        self.roomID = roomID
    }
}

extension RealtimeEvent {
    /// An event from the generated contract type. Nil if an ID isn't a UUID.
    public init?(_ event: Components.Schemas.GlowEvent) {
        switch event {
        case let .match_created(value): self.init(.matchCreated, match: value.matchId)
        case let .match_choice(value): self.init(.matchChoice, match: value.matchId)
        case let .match_recheck(value): self.init(.matchRecheck, match: value.matchId)
        case let .match_ended(value): self.init(.matchEnded, match: value.matchId)
        case let .glow_started(value): self.init(.glowStarted, match: value.matchId)
        case let .glow_ended(value): self.init(.glowEnded, match: value.matchId)
        case let .message_created(value): self.init(.messageCreated, match: value.matchId)
        case let .checkin_expiring(value): self.init(.checkinExpiring, room: value.roomId)
        case let .deck_changed(value): self.init(.deckChanged, room: value.roomId)
        }
    }

    /// Decodes a Realtime broadcast payload: exactly `{ type, matchId }` or `{ type, roomId }`.
    /// Anything else, including extra fields, is refused rather than guessed at.
    public init?(eventJSON data: Data) {
        guard let event = try? JSONDecoder().decode(Components.Schemas.GlowEvent.self, from: data) else {
            return nil
        }
        self.init(event)
    }

    /// Decodes the custom keys of a push (`type` plus `matchId` or `roomId`) and ignores `aps`
    /// and anything else in the notification's userInfo.
    public init?(notificationPayload data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let eventKeys: Set = ["type", "matchId", "roomId"]
        let event = object.filter { eventKeys.contains($0.key) && $0.value is String }
        guard JSONSerialization.isValidJSONObject(event),
              let json = try? JSONSerialization.data(withJSONObject: event)
        else { return nil }
        self.init(eventJSON: json)
    }

    private init?(_ kind: RealtimeEventKind, match raw: String) {
        guard let id = MatchID(validating: raw) else { return nil }
        self.init(kind: kind, matchID: id)
    }

    private init?(_ kind: RealtimeEventKind, room raw: String) {
        guard let id = RoomID(validating: raw) else { return nil }
        self.init(kind: kind, roomID: id)
    }
}

extension RealtimeEvent {
    /// The screen that shows this event, for a tapped notification.
    ///
    /// Realtime events don't navigate by themselves: each feature decides what to do with its own
    /// events. Only a tap on a notification (or a takeover the app root chooses) uses this.
    public var destination: Route? {
        switch kind {
        case .matchCreated: matchID.map(Route.mutual)
        case .matchChoice: matchID.map(Route.match)
        // A tap on the stale-Find push opens the match, which sends Find again with a fresh fix.
        case .matchRecheck: matchID.map(Route.match)
        case .matchEnded: .matches
        case .glowStarted: matchID.map(Route.glow)
        case .glowEnded: matchID.map(Route.chat)
        case .messageCreated: matchID.map(Route.chat)
        case .checkinExpiring: roomID.map(Route.roomHome)
        case .deckChanged: roomID.map(Route.deck)
        }
    }
}

/// The connection to Supabase Realtime.
public enum RealtimeConnectionState: Hashable, Sendable {
    /// Signed out, or not connected yet.
    case disconnected
    case connecting
    /// Joined `user:{id}` (and the current room, if any). After a reconnect, events sent while
    /// the app was away are gone: refetch what your screen shows.
    case connected
}

/// Supabase Realtime private channels: `user:{id}` and the current `room:{id}`.
///
/// The live service joins `user:{id}` by itself once someone is signed in, leaves everything on
/// sign-out, and reconnects when the app comes back to the foreground. Features only subscribe:
///
/// ```swift
/// .task {
///     for await event in dependencies.realtime.events(.matchCreated, .matchEnded) {
///         await model.refresh(event.matchID)
///     }
/// }
/// ```
public protocol RealtimeService: Sendable {
    /// Every event from every joined channel, from now until the stream is cancelled.
    func events() -> AsyncStream<RealtimeEvent>
    /// The current connection state, then every change.
    func connectionStates() -> AsyncStream<RealtimeConnectionState>
    /// Joins the signed-in person's own `user:{id}` channel. The live service also does this by
    /// itself when the session becomes ready, so calling it is only needed to retry sooner.
    func connect() async throws
    /// Joins `room:{id}`, leaving any other room. Only works with an open check-in there.
    func join(room: RoomID) async throws
    /// Leaves the current room's channel, if any.
    func leaveRoom() async
    /// Leaves every channel and closes the connection.
    func disconnect() async
}

extension RealtimeService {
    /// Only events of these kinds.
    public func events(_ kinds: RealtimeEventKind...) -> AsyncStream<RealtimeEvent> {
        events(Set(kinds))
    }

    /// Only events of these kinds.
    public func events(_ kinds: Set<RealtimeEventKind>) -> AsyncStream<RealtimeEvent> {
        filtered { kinds.contains($0.kind) }
    }

    /// Only events about this match.
    public func events(for match: MatchID) -> AsyncStream<RealtimeEvent> {
        filtered { $0.matchID == match }
    }

    /// Only events about this room.
    public func events(for room: RoomID) -> AsyncStream<RealtimeEvent> {
        filtered { $0.roomID == room }
    }

    private func filtered(_ isIncluded: @escaping @Sendable (RealtimeEvent) -> Bool) -> AsyncStream<RealtimeEvent> {
        let upstream = events()
        return AsyncStream { continuation in
            let task = Task {
                for await event in upstream where isIncluded(event) {
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
