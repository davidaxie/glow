import AppCore
import DesignSystem
import SnapshotTesting
import SwiftUI
import Testing
@testable import FeatureMatch

/// FeatureMatch's screens at the default text size and the largest accessibility size.
///
/// To re-record after an intended change, delete the PNGs in `__Snapshots__/MatchSnapshotTests`
/// and run `scripts/sim.sh test FeatureMatch` twice (the first run records and fails).
@MainActor
struct MatchSnapshotTests {
    enum Screen: String, CaseIterable {
        case choosing
        case waiting
        case notInRoom = "not-in-room"
        case locationDenied = "location-denied"
        case list
        case empty
    }

    private static let id = FixtureMatchClient.revealMatch
    /// The fixed "now" every countdown reads, so snapshots never depend on the clock. In the
    /// future, so the fixtures never time the match out.
    private static let now = Date(timeIntervalSinceReferenceDate: 1_000_000_000)

    /// A match with no photos (so nothing loads while the snapshot is taken), 8:12 left to choose.
    private static func match(choice: MatchSnapshot.Choice? = nil) -> MatchSnapshot {
        var match = FixtureMatchClient.snapshot(id, "Blake", status: .choosing, photos: 0, now: now)
        match.choiceDeadline = now.addingTimeInterval(8 * 60 + 12)
        match.yourChoice = choice
        return match
    }

    private static func view(for screen: Screen) async -> AnyView {
        switch screen {
        case .choosing, .waiting, .notInRoom, .locationDenied:
            let model = MatchModel(
                matchID: id,
                client: FixtureMatchClient(matches: [match(choice: screen == .waiting ? .find : nil)]),
                location: PreviewLocationService(),
                analytics: NoopAnalytics(),
            )
            await model.load()
            #expect(model.phase == (screen == .waiting ? .waiting : .choosing))
            if screen == .notInRoom {
                model.notice = .notInRoom
            } else if screen == .locationDenied {
                model.notice = .locationDenied
            }
            return AnyView(MatchDetails(model: model, snapshot: model.snapshot!, showsHeadline: true))
        case .list, .empty:
            let model = MatchesListModel(client: FixtureMatchClient(screen == .list ? .list : .empty, now: now))
            await model.load()
            return AnyView(MatchesList(model: model) { _ in })
        }
    }

    @Test(arguments: Screen.allCases, [DynamicTypeSize.large, .accessibility5])
    func screen(_ screen: Screen, size: DynamicTypeSize) async {
        let height: CGFloat = size == .large ? 852 : 1900
        let view = await Self.view(for: screen)
            .frame(width: 393, height: height)
            .background(.glowBackground)
            .environment(\.dynamicTypeSize, size)
            .environment(\.colorScheme, .dark)
            .environment(\.matchClockOverride, Self.now)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.99,
                perceptualPrecision: 0.98,
                layout: .fixed(width: 393, height: height),
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
