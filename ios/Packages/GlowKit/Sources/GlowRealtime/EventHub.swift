import Foundation
import os

/// Fans each value out to every current subscriber. Unlike AppCore's `Broadcaster`, a new
/// subscriber gets only values sent after it subscribed: an event that already happened is
/// never replayed to a screen that opened later.
final class EventHub<Value: Sendable>: Sendable {
    private let continuations = OSAllocatedUnfairLock<[UUID: AsyncStream<Value>.Continuation]>(initialState: [:])

    func stream() -> AsyncStream<Value> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(32))
        continuations.withLock { $0[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.continuations.withLock { _ = $0.removeValue(forKey: id) }
        }
        return stream
    }

    func send(_ value: Value) {
        for continuation in continuations.withLock({ Array($0.values) }) {
            continuation.yield(value)
        }
    }

    var subscriberCount: Int {
        continuations.withLock { $0.count }
    }
}
