import AppCore
import SnapshotTesting
import SwiftUI
import Testing
@testable import FeatureChat

/// Every chat screen at the default text size and the largest accessibility size.
///
/// To re-record after an intended change, delete the PNGs in `__Snapshots__/ChatSnapshotTests`
/// and run `scripts/sim.sh test FeatureChat` twice (the first run records and fails).
@MainActor
struct ChatSnapshotTests {
    enum Screen: String, CaseIterable, Sendable {
        case thread
        case sendingAndFailed
        case empty
        case nearLimit
        case notOpen
        case ended
    }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    func model(for screen: Screen) async -> ChatModel {
        let api = switch screen {
        case .empty: PreviewChatAPI(thread: [])
        default: PreviewChatAPI()
        }
        if screen == .notOpen {
            api.failPages(.notOpen)
        }
        let model = ChatModel(matchID: PreviewChatAPI.sampleMatch, api: api, now: { PreviewChatAPI.sampleNow }, calendar: Self.calendar)
        await model.start()
        switch screen {
        case .sendingAndFailed:
            api.failNextSends(.offline, .rejected)
            model.draft = "Is the stage the one by the doors?"
            await model.send()
            model.draft = "something moderation refuses"
            await model.send()
        case .nearLimit:
            model.draft = String(repeating: "So much to say. ", count: 60)
        case .ended:
            api.failPages(.ended)
            await model.refresh()
        default:
            break
        }
        return model
    }

    @Test(arguments: Screen.allCases, [DynamicTypeSize.large, .accessibility5])
    func screen(_ screen: Screen, size: DynamicTypeSize) async {
        let model = await model(for: screen)
        let view = NavigationStack {
            ChatScreen(model: model, startsByItself: false)
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
