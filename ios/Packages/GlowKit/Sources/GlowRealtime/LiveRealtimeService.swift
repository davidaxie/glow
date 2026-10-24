import APIClient
import AppCore
import Foundation
import os
import UIKit

/// The person's private Realtime channels, as one stream of events.
///
/// - Joins `user:{id}` by itself as soon as someone is signed in, and leaves every channel on
///   sign-out. Topics are lowercase, through `GlowEvents.userTopic` and `roomTopic`.
/// - `join(room:)` adds the current room's `room:{id}` (one room at a time).
/// - Each broadcast must be exactly a contract event, and its name must match its type;
///   anything else is dropped (P1).
/// - When the app returns to the foreground it refreshes the token and rejoins whatever
///   dropped, then reports `.connected`, so screens refetch what they missed.
public final class LiveRealtimeService: RealtimeService {
    private let core: RealtimeCore
    private let tasks = OSAllocatedUnfairLock<[Task<Void, Never>]>(initialState: [])

    convenience init(supabaseURL: URL, anonKey: String, session: any SessionService) {
        self.init(
            transport: SupabaseRealtimeTransport(supabaseURL: supabaseURL, anonKey: anonKey, tokens: session),
            session: session,
            foregrounds: Self.foregrounds(),
        )
    }

    init(transport: any RealtimeTransport, session: any SessionService, foregrounds: AsyncStream<Void>) {
        let core = RealtimeCore(transport: transport, session: session)
        self.core = core
        let followSession = Task {
            for await state in session.states() {
                await core.sessionChanged(state)
            }
        }
        let followForeground = Task {
            for await _ in foregrounds {
                await core.cameToForeground()
            }
        }
        let followTransport = Task {
            for await status in transport.statuses() {
                await core.transportChanged(status)
            }
        }
        tasks.withLock { $0 = [followSession, followForeground, followTransport] }
    }

    deinit {
        for task in tasks.withLock({ $0 }) {
            task.cancel()
        }
    }

    public func events() -> AsyncStream<RealtimeEvent> {
        core.hub.stream()
    }

    public func connectionStates() -> AsyncStream<RealtimeConnectionState> {
        core.state.stream()
    }

    public func connect() async throws {
        try await core.connectUser()
    }

    public func join(room: RoomID) async throws {
        try await core.join(room: room)
    }

    public func leaveRoom() async {
        await core.leaveRoom()
    }

    public func disconnect() async {
        await core.disconnect()
    }

    private static func foregrounds() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let observer = ForegroundObserver(NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: nil,
            ) { _ in continuation.yield() })
            continuation.onTermination = { _ in NotificationCenter.default.removeObserver(observer.token) }
        }
    }
}

/// The token is only ever handed back to NotificationCenter, which is thread safe.
private final class ForegroundObserver: @unchecked Sendable {
    let token: any NSObjectProtocol

    init(_ token: any NSObjectProtocol) {
        self.token = token
    }
}

public enum RealtimeServiceError: Error, Hashable, Sendable {
    /// Nobody is signed in, so there's no channel to join.
    case notSignedIn
    /// Realtime refused the join, or the connection failed.
    case joinFailed
}

/// All channel state, in one actor so joins, leaves and reconnects never interleave badly.
actor RealtimeCore {
    let hub = EventHub<RealtimeEvent>()
    let state = Broadcaster<RealtimeConnectionState>(.disconnected)

    private let transport: any RealtimeTransport
    private let session: any SessionService
    private let logger = Logger(subsystem: Log.subsystem, category: "realtime")

    private var user: (any RealtimeMembership)?
    private var userID: String?
    private var room: (any RealtimeMembership)?
    private var roomID: RoomID?
    private var transportStatus: TransportStatus = .disconnected

    init(transport: any RealtimeTransport, session: any SessionService) {
        self.transport = transport
        self.session = session
    }

    // MARK: Session

    func sessionChanged(_ newState: SessionState) async {
        switch newState {
        case .restoring:
            return
        case .signedOut:
            await disconnect()
        case .onboarding, .ready:
            try? await connectUser()
        }
    }

    // MARK: Channels

    func connectUser() async throws {
        guard let id = await session.currentUserID(), let uuid = UUID(uuidString: id) else {
            throw RealtimeServiceError.notSignedIn
        }
        let topic = GlowEvents.userTopic(uuid)
        if let user, user.topic == topic, user.isJoined {
            return
        }
        if let user {
            if user.topic == topic {
                // Same person, but the channel dropped: rejoin it.
                self.user = nil
                await user.leave()
            } else {
                // Someone else signed in: nothing of the last person's may stay joined.
                await leaveAll()
            }
        }
        publish(.connecting)
        do {
            user = try await transport.join(topic: topic, onBroadcast: deliver)
            userID = id
            logger.info("Joined the user channel")
        } catch {
            user = nil
            logger.notice("Couldn't join the user channel")
            publish(.disconnected)
            throw RealtimeServiceError.joinFailed
        }
        if let roomID, room?.isJoined != true {
            try? await join(room: roomID)
        }
        publish(.connected)
    }

    func join(room id: RoomID) async throws {
        guard let uuid = UUID(uuidString: id.rawValue) else { throw RealtimeServiceError.joinFailed }
        let topic = GlowEvents.roomTopic(uuid)
        if let room, room.topic == topic, room.isJoined {
            return
        }
        if let room {
            await room.leave()
            self.room = nil
        }
        roomID = id
        do {
            room = try await transport.join(topic: topic, onBroadcast: deliver)
            logger.info("Joined the room channel")
        } catch {
            logger.notice("Couldn't join the room channel")
            throw RealtimeServiceError.joinFailed
        }
    }

    func leaveRoom() async {
        roomID = nil
        if let room {
            self.room = nil
            await room.leave()
        }
    }

    func disconnect() async {
        await leaveAll()
        await transport.disconnect()
        publish(.disconnected)
    }

    private func leaveAll() async {
        let joined = [user, room].compactMap(\.self)
        user = nil
        userID = nil
        room = nil
        roomID = nil
        for membership in joined {
            await membership.leave()
        }
    }

    // MARK: Connection

    func cameToForeground() async {
        await transport.refreshAuth()
        guard await session.currentUserID() != nil else { return }
        if user?.isJoined != true || (roomID != nil && room?.isJoined != true) {
            try? await connectUser()
        } else {
            // Still joined, but events may have been missed while away: say so, so screens refetch.
            publish(.connected)
        }
    }

    func transportChanged(_ status: TransportStatus) {
        transportStatus = status
        switch status {
        case .disconnected: publish(.disconnected)
        case .connecting: publish(.connecting)
        case .connected:
            if user?.isJoined == true {
                publish(.connected)
            }
        }
    }

    private func publish(_ newState: RealtimeConnectionState) {
        if state.value != newState {
            state.send(newState)
        }
    }

    // MARK: Events

    /// Turns a broadcast into an event, or drops it. Runs on the transport's callback thread.
    private nonisolated var deliver: @Sendable (String, Data) -> Void {
        let hub = hub
        let logger = logger
        return { name, payload in
            guard let event = RealtimeEvent(eventJSON: payload), event.kind.rawValue == name else {
                logger.notice("Dropped a broadcast that isn't a contract event")
                return
            }
            hub.send(event)
        }
    }
}
