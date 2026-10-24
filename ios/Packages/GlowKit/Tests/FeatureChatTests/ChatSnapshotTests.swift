import AppCore
import SnapshotTesting
import SwiftUI
import Testing
@testable import FeatureChat

/// Every chat screen at the default text size and the largest accessibility size.
///
/// To re-record after an intended change, delete the PNGs in `__Snapshots__/ChatSnapshotTests`
/// and run `scripts/sim.sh test FeatureChat` twice (the first run records and fails).
///
/// Synchronous on purpose: SnapshotTesting waits for the render with XCTWaiter, which deadlocks
/// inside an async test on the main actor. The models are built already showing their state.
@MainActor
struct ChatSnapshotTests {
    enum Screen: String, CaseIterable, Sendable {
        case thread
        case sendingAndFailed
        case empty
        case nearLimit
        case notOpen
        case ended
        case failedToLoad
    }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    static let header = ChatHeader(firstName: "Sam")

    static func mine(_ id: String, _ body: String, _ delivery: ChatMessage.Delivery) -> ChatMessage {
        ChatMessage(id: id, clientID: id, body: body, createdAt: PreviewChatAPI.sampleNow, fromMe: true, delivery: delivery)
    }

    func model(for screen: Screen) -> ChatModel {
        let thread = PreviewChatAPI.sampleThread
        let calendar = Self.calendar
        switch screen {
        case .thread:
            var mine = thread
            mine.append(PreviewChatAPI.sample(6, "On my way 🙂", fromMe: true, minutesAgo: 1))
            return .showing(.ready, messages: mine, header: Self.header, calendar: calendar)
        case .sendingAndFailed:
            let outgoing = [
                Self.mine("c1", "Is the stage the one by the doors?", .sending),
                Self.mine("c2", "Did you see the lights?", .failed(.network)),
                Self.mine("c3", "something moderation refuses", .failed(.rejected)),
            ]
            return .showing(.ready, messages: thread, outgoing: outgoing, header: Self.header, calendar: calendar)
        case .empty:
            return .showing(.ready, header: Self.header, calendar: calendar)
        case .nearLimit:
            return .showing(
                .ready,
                messages: thread,
                header: Self.header,
                draft: String(repeating: "So much to say. ", count: 60),
                calendar: calendar,
            )
        case .notOpen:
            return .showing(.notOpen, header: Self.header, calendar: calendar)
        case .ended:
            return .showing(.ended, header: Self.header, calendar: calendar)
        case .failedToLoad:
            return .showing(.failed, calendar: calendar)
        }
    }

    @Test(arguments: Screen.allCases, [DynamicTypeSize.large, .accessibility5])
    func screen(_ screen: Screen, size: DynamicTypeSize) {
        let view = NavigationStack {
            ChatScreen(model: model(for: screen), startsByItself: false)
        }
        .environment(\.dynamicTypeSize, size)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "en_US"))

        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.99,
                perceptualPrecision: 0.98,
                layout: .device(config: .iPhone13Pro),
                traits: UITraitCollection { traits in
                    traits.displayScale = 2
                    traits.userInterfaceStyle = .dark
                    traits.preferredContentSizeCategory = size == .large ? .large : .accessibilityExtraExtraExtraLarge
                },
            ),
            named: "\(screen.rawValue)-\(size == .large ? "default" : "ax5")",
        )
    }
}
