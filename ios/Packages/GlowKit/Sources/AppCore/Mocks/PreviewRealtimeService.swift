import Foundation

/// Never connects. Send events through `emit(_:)` to drive a preview or test, and connection
/// states through `setState(_:)`.
public final class PreviewRealtimeService: RealtimeService {
    private let broadcaster = Broadcaster<RealtimeEvent?>(nil)
    private let state: Broadcaster<RealtimeConnectionState>

    public init(state: RealtimeConnectionState = .connected) {
        self.state = Broadcaster(state)
    }

    public func emit(_ event: RealtimeEvent) {
        broadcaster.send(event)
    }

    public func setState(_ newState: RealtimeConnectionState) {
        state.send(newState)
    }

    /// Only events emitted after the call, like the live service.
    public func events() -> AsyncStream<RealtimeEvent> {
        let upstream = broadcaster.stream()
        return AsyncStream { continuation in
            let task = Task {
                var isFirst = true
                for await event in upstream {
                    // The broadcaster replays its last value first; that one happened before.
                    defer { isFirst = false }
                    if isFirst {
                        continue
                    }
                    if let event {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func connectionStates() -> AsyncStream<RealtimeConnectionState> {
        state.stream()
    }

    public func connect() async throws {}
    public func join(room _: RoomID) async throws {}
    public func leaveRoom() async {}
    public func disconnect() async {}
}
