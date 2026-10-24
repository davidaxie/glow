import Foundation
import os

/// Holds a current value and hands out `AsyncStream`s that start with it and get every change.
/// A small building block for services that publish state (session state, realtime events).
public final class Broadcaster<Value: Sendable>: Sendable {
    private struct State {
        var value: Value
        var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]
    }

    private let state: OSAllocatedUnfairLock<State>

    public init(_ initial: Value) {
        state = OSAllocatedUnfairLock(uncheckedState: State(value: initial))
    }

    public var value: Value {
        state.withLockUnchecked { $0.value }
    }

    /// A stream that yields the current value now, then every new one.
    public func stream() -> AsyncStream<Value> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(16))
        let current = state.withLockUnchecked { state in
            state.continuations[id] = continuation
            return state.value
        }
        continuation.yield(current)
        continuation.onTermination = { [weak self] _ in
            self?.state.withLockUnchecked { _ = $0.continuations.removeValue(forKey: id) }
        }
        return stream
    }

    public func send(_ value: Value) {
        let continuations = state.withLockUnchecked { state in
            state.value = value
            return Array(state.continuations.values)
        }
        for continuation in continuations {
            continuation.yield(value)
        }
    }
}
