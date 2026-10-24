import Foundation

/// Never connects. Send events through `emit(_:)` to drive a preview or test.
public final class PreviewRealtimeService: RealtimeService {
    private let broadcaster = Broadcaster<RealtimeEvent?>(nil)

    public init() {}

    public func emit(_ event: RealtimeEvent) {
        broadcaster.send(event)
    }

    public func events() -> AsyncStream<RealtimeEvent> {
        let upstream = broadcaster.stream()
        return AsyncStream { continuation in
            let task = Task {
                for await event in upstream {
                    if let event {
                        continuation.yield(event)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func connect() async throws {}
    public func join(room _: RoomID) async throws {}
    public func leaveRoom() async {}
    public func disconnect() async {}
}
