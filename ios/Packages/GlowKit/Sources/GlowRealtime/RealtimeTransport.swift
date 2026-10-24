import APIClient
import Foundation
import Realtime

/// What the realtime service needs from a socket: join a private topic, hear its broadcasts,
/// and leave. A protocol, so the service's logic is tested without a server.
protocol RealtimeTransport: Sendable {
    /// Joins `topic` as a private channel and calls `onBroadcast(event, payloadJSON)` for each
    /// broadcast on it. Throws if Realtime refuses the join (someone else's channel, say).
    func join(
        topic: String,
        onBroadcast: @escaping @Sendable (_ event: String, _ payload: Data) -> Void,
    ) async throws -> any RealtimeMembership
    /// The socket's status, then every change.
    func statuses() -> AsyncStream<TransportStatus>
    /// Sends a fresh access token to every joined channel.
    func refreshAuth() async
    /// Leaves everything and closes the socket.
    func disconnect() async
}

/// One joined channel.
protocol RealtimeMembership: Sendable {
    var topic: String { get }
    /// Still joined (not closed by the server or by a dropped connection).
    var isJoined: Bool { get }
    func leave() async
}

enum TransportStatus: Hashable, Sendable {
    case disconnected
    case connecting
    case connected
}

// MARK: - Supabase

/// Supabase Realtime over supabase-swift, with the anon key and the person's own access token.
/// supabase-swift refreshes the token from `accessToken` on every heartbeat, and reconnects
/// and rejoins channels by itself when the app returns to the foreground.
final class SupabaseRealtimeTransport: RealtimeTransport {
    private let client: RealtimeClientV2

    init(supabaseURL: URL, anonKey: String, tokens: any AccessTokenProvider) {
        client = RealtimeClientV2(
            url: supabaseURL.appending(path: "realtime/v1"),
            options: RealtimeClientOptions(
                headers: ["apikey": anonKey],
                accessToken: { try await tokens.currentAccessToken() },
            ),
        )
    }

    func join(
        topic: String,
        onBroadcast: @escaping @Sendable (String, Data) -> Void,
    ) async throws -> any RealtimeMembership {
        let channel = client.channel(topic) { config in
            config.isPrivate = true
        }
        let subscription = channel.onBroadcast(event: "*") { message in
            // A broadcast arrives as { type: "broadcast", event, payload }.
            guard let event = message["event"]?.stringValue,
                  let payload = message["payload"],
                  let data = try? JSONEncoder().encode(payload)
            else { return }
            onBroadcast(event, data)
        }
        do {
            try await channel.subscribeWithError()
        } catch {
            subscription.cancel()
            await client.removeChannel(channel)
            throw error
        }
        return SupabaseMembership(topic: topic, channel: channel, subscription: subscription, client: client)
    }

    func statuses() -> AsyncStream<TransportStatus> {
        let upstream = client.statusChange
        return AsyncStream { continuation in
            let task = Task {
                for await status in upstream {
                    switch status {
                    case .disconnected: continuation.yield(.disconnected)
                    case .connecting: continuation.yield(.connecting)
                    case .connected: continuation.yield(.connected)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func refreshAuth() async {
        await client.setAuth()
    }

    func disconnect() async {
        await client.removeAllChannels()
        client.disconnect()
    }
}

private struct SupabaseMembership: RealtimeMembership {
    let topic: String
    let channel: RealtimeChannelV2
    let subscription: RealtimeSubscription
    let client: RealtimeClientV2

    var isJoined: Bool {
        channel.status == .subscribed
    }

    func leave() async {
        subscription.cancel()
        await client.removeChannel(channel)
    }
}
