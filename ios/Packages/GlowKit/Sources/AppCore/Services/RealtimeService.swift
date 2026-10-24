import Foundation

// Owner from Wave 1: B5 (Realtime). A3 wrote this first shape; B5 may change this file and
// Mocks/PreviewRealtimeService.swift together. The event shapes come from contracts/events.json.

/// Every event the server sends (spec: Events and push).
public enum RealtimeEventKind: String, Hashable, Sendable, CaseIterable {
    case matchCreated = "match.created"
    case matchChoice = "match.choice"
    case glowStarted = "glow.started"
    case glowEnded = "glow.ended"
    case messageCreated = "message.created"
    case checkinExpiring = "checkin.expiring"
    case deckChanged = "deck.changed"
}

/// An event from the person's private channels. Only ever an event type plus a match or room ID,
/// never a user ID or name (P1). Refetch details from the API.
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

/// Supabase Realtime private channels: `user:{id}` and the current `room:{id}`.
public protocol RealtimeService: Sendable {
    /// Every event from every joined channel, until the stream is cancelled.
    func events() -> AsyncStream<RealtimeEvent>
    /// Joins the signed-in person's own `user:{id}` channel.
    func connect() async throws
    /// Joins `room:{id}`. Only works with an active check-in there.
    func join(room: RoomID) async throws
    func leaveRoom() async
    func disconnect() async
}
