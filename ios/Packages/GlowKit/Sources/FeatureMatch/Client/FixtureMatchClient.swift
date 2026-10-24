import APIClient
import AppCore
import DesignSystem
import Foundation
import os
import SwiftUI
import UIKit

/// Made-up matches for previews, tests and Debug Simulator runs. Never touches the network.
///
/// Launch a Debug build with `-GlowMatchFixtures <scenario>` to drive the real screens without a
/// server, for screenshots and recordings:
///
/// ```
/// xcrun simctl launch "Glow A (C2)" com.davidxie.glow.debug -GlowMatchFixtures reveal
/// ```
///
/// The other person is played by the fixture: after you choose, they choose too.
public final class FixtureMatchClient: MatchClient {
    public enum Scenario: String, Sendable, CaseIterable {
        /// `match.created` arrives shortly after launch. They choose Find a few seconds after you do.
        case reveal
        /// Like `reveal`, but they choose Just chat.
        case revealChat = "reveal-chat"
        /// The match screen, already waiting: you chose Find, they haven't chosen.
        case waiting
        /// The matches list, with one match in each state.
        case list
        /// No matches yet.
        case empty
    }

    /// What the made-up other person does after you choose.
    public enum Partner: Hashable, Sendable {
        case choosesFind(after: Duration)
        case choosesChat(after: Duration)
        case staysUndecided
    }

    public static let revealMatch = MatchID(rawValue: "c2f1c2f1-0000-4000-8000-00000000000a")
    public static let glowingMatch = MatchID(rawValue: "c2f1c2f1-0000-4000-8000-00000000000b")
    public static let chattingMatch = MatchID(rawValue: "c2f1c2f1-0000-4000-8000-00000000000c")
    public static let metMatch = MatchID(rawValue: "c2f1c2f1-0000-4000-8000-00000000000d")

    private struct State {
        var matches: [MatchID: MatchSnapshot]
        var partner: Partner
        var choices: [(MatchSnapshot.Choice, MatchID)] = []
        var photoRequests: [(MatchID, Int)] = []
        var listeners: [UUID: AsyncStream<MatchEvent>.Continuation] = [:]
    }

    private let state: OSAllocatedUnfairLock<State>
    /// When set, every call fails with this.
    private let failure: MatchError?

    public init(matches: [MatchSnapshot], partner: Partner = .staysUndecided, failure: MatchError? = nil) {
        state = OSAllocatedUnfairLock(uncheckedState: State(
            matches: Dictionary(uniqueKeysWithValues: matches.map { ($0.id, $0) }),
            partner: partner,
        ))
        self.failure = failure
    }

    /// The fixtures for a scenario. `reveal` also announces its match a moment after launch.
    public convenience init(_ scenario: Scenario, now: Date = .now) {
        let choosing = Self.snapshot(Self.revealMatch, "Blake", status: .choosing, now: now)
        switch scenario {
        case .reveal:
            self.init(matches: [choosing], partner: .choosesFind(after: .seconds(4)))
            emit(.created, Self.revealMatch, after: .seconds(2))
        case .revealChat:
            self.init(matches: [choosing], partner: .choosesChat(after: .seconds(4)))
            emit(.created, Self.revealMatch, after: .seconds(2))
        case .waiting:
            var waiting = choosing
            waiting.yourChoice = .find
            waiting.choiceDeadline = now.addingTimeInterval(7 * 60 + 42)
            self.init(matches: [waiting])
        case .list:
            self.init(matches: [
                choosing,
                Self.snapshot(Self.glowingMatch, "Robin", status: .glowing, now: now.addingTimeInterval(-300)),
                Self.snapshot(Self.chattingMatch, "Sam", status: .chatting, now: now.addingTimeInterval(-3600)),
                Self.snapshot(Self.metMatch, "Jordan", status: .met, now: now.addingTimeInterval(-7200)),
            ])
        case .empty:
            self.init(matches: [])
        }
    }

    /// A made-up match, created at `now`, with the full choice window ahead of it.
    public static func snapshot(
        _ id: MatchID,
        _ firstName: String,
        status: MatchSnapshot.Status,
        photos: Int = 3,
        now: Date = .now,
    ) -> MatchSnapshot {
        MatchSnapshot(
            id: id,
            status: status,
            firstName: firstName,
            photoCount: photos,
            roomName: "Glow demo room",
            createdAt: now,
            choiceDeadline: now.addingTimeInterval(GlowConstants.choiceWindow),
        )
    }

    #if DEBUG
        /// The Debug launch fixtures, from `-GlowMatchFixtures <scenario>`, or nil.
        static let launchFixtures: FixtureMatchClient? = UserDefaults.standard
            .string(forKey: "GlowMatchFixtures")
            .flatMap(Scenario.init(rawValue:))
            .map { FixtureMatchClient($0) }
    #endif

    // MARK: What tests can check

    /// Every choice sent, in order.
    public var choices: [(MatchSnapshot.Choice, MatchID)] {
        state.withLockUnchecked { $0.choices }
    }

    /// Every photo asked for, in order.
    public var photoRequests: [(MatchID, Int)] {
        state.withLockUnchecked { $0.photoRequests }
    }

    /// Changes a match as if the server had, and tells listeners like Realtime would.
    public func update(_ id: MatchID, announce kind: MatchEvent.Kind = .choice, _ change: (inout MatchSnapshot) -> Void) {
        state.withLockUnchecked { state in
            if var match = state.matches[id] {
                change(&match)
                state.matches[id] = match
            }
        }
        send(MatchEvent(kind, id))
    }

    /// Ends a match (unmatch or block).
    public func end(_ id: MatchID) {
        _ = state.withLockUnchecked { $0.matches.removeValue(forKey: id) }
        send(MatchEvent(.ended, id))
    }

    // MARK: MatchClient

    public func match(_ id: MatchID) async throws(MatchError) -> MatchSnapshot {
        if let failure { throw failure }
        let match = state.withLockUnchecked { state -> MatchSnapshot? in
            guard var match = state.matches[id] else { return nil }
            // The server applies the timeout lazily, like this.
            if match.status == .choosing, match.choiceDeadline <= .now {
                match.status = .chatting
                state.matches[id] = match
            }
            return match
        }
        guard let match else { throw .notFound }
        return match
    }

    public func choose(_ choice: MatchSnapshot.Choice, for id: MatchID, fix _: LocationFix?) async throws(MatchError) -> ChoiceOutcome {
        if let failure { throw failure }
        let result = state.withLockUnchecked { state -> (ChoiceOutcome, Partner)? in
            guard var match = state.matches[id] else { return nil }
            state.choices.append((choice, id))
            guard match.status == .choosing else {
                return (ChoiceOutcome(next: match.status == .glowing ? .glow : .chat, reason: .alreadyDecided, match: match), .staysUndecided)
            }
            match.yourChoice = choice
            if choice == .chat {
                match.status = .chatting
                state.matches[id] = match
                return (ChoiceOutcome(next: .chat, reason: .choseChat, match: match), .staysUndecided)
            }
            state.matches[id] = match
            return (ChoiceOutcome(next: .waiting, reason: .otherUndecided, match: match), state.partner)
        }
        guard let (outcome, partner) = result else { throw .notFound }
        switch partner {
        case let .choosesFind(delay):
            schedule(after: delay) { [weak self] in
                self?.update(id, announce: .glowStarted) { $0.status = .glowing }
            }
        case let .choosesChat(delay):
            schedule(after: delay) { [weak self] in
                self?.update(id, announce: .choice) { $0.status = .chatting }
            }
        case .staysUndecided:
            break
        }
        return outcome
    }

    public func matches() async throws(MatchError) -> [MatchSummary] {
        if let failure { throw failure }
        return state.withLockUnchecked { state in
            state.matches.values
                .sorted { $0.createdAt > $1.createdAt }
                .map {
                    MatchSummary(
                        id: $0.id,
                        status: $0.status,
                        firstName: $0.firstName,
                        roomName: $0.roomName,
                        createdAt: $0.createdAt,
                        choiceDeadline: $0.choiceDeadline,
                    )
                }
        }
    }

    public func photo(_ id: MatchID, index: Int) async throws(MatchError) -> Data {
        if let failure { throw failure }
        let exists = state.withLockUnchecked { state -> Bool in
            state.photoRequests.append((id, index))
            guard let match = state.matches[id] else { return false }
            return index >= 0 && index < match.photoCount
        }
        guard exists else { throw .notFound }
        guard let data = await Self.renderPhoto(index) else { throw .failed }
        return data
    }

    public func events() -> AsyncStream<MatchEvent> {
        let (stream, continuation) = AsyncStream<MatchEvent>.makeStream(bufferingPolicy: .bufferingNewest(16))
        let id = UUID()
        state.withLockUnchecked { $0.listeners[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLockUnchecked { _ = $0.listeners.removeValue(forKey: id) }
        }
        return stream
    }

    // MARK: Helpers

    private func send(_ event: MatchEvent) {
        let listeners = state.withLockUnchecked { Array($0.listeners.values) }
        for listener in listeners {
            listener.yield(event)
        }
    }

    private func emit(_ kind: MatchEvent.Kind, _ id: MatchID, after delay: Duration) {
        schedule(after: delay) { [weak self] in self?.send(MatchEvent(kind, id)) }
    }

    private func schedule(after delay: Duration, _ work: @escaping @Sendable () -> Void) {
        Task {
            try? await Task.sleep(for: delay)
            work()
        }
    }

    /// A faceless, made-up "photo": soft glow colors. Nothing like a real person.
    @MainActor
    private static func renderPhoto(_ index: Int) -> Data? {
        let hues: [(GlowHue, GlowHue)] = [(.violet, .rose), (.sky, .aqua), (.ember, .sun)]
        let (top, bottom) = hues[index % hues.count]
        let renderer = ImageRenderer(content: FixturePhoto(top: top, bottom: bottom))
        renderer.scale = 2
        return renderer.uiImage?.jpegData(compressionQuality: 0.8)
    }
}

/// The made-up photo's picture.
private struct FixturePhoto: View {
    let top: GlowHue
    let bottom: GlowHue

    var body: some View {
        ZStack {
            LinearGradient(colors: [top.color, bottom.color], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(GlowPalette.textPrimary.color.opacity(0.18))
                .frame(width: 180, height: 180)
                .offset(x: 70, y: -110)
            Circle()
                .fill(GlowPalette.background.color.opacity(0.16))
                .frame(width: 240, height: 240)
                .offset(x: -90, y: 140)
        }
        .frame(width: 320, height: 400)
    }
}
