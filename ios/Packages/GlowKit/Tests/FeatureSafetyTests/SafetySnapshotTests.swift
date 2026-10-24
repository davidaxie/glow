import APIClient
import AppCore
import DesignSystem
import SnapshotTesting
import SwiftUI
import Testing
@testable import FeatureSafety

/// Every FeatureSafety screen, in each state, at the default text size and the largest
/// accessibility size (spec: snapshots at default and largest text size).
///
/// To re-record after an intended change, delete the PNGs in `__Snapshots__/SafetySnapshotTests`
/// and run `scripts/sim.sh test FeatureSafety` twice (the first run records and fails).
@MainActor
struct SafetySnapshotTests {
    enum Screen: String, CaseIterable {
        case blockCard = "block-card"
        case blockMatch = "block-match"
        case blockFailed = "block-failed"
        case blockDone = "block-done"
        case report
        case reportDone = "report-done"
        case pause
        case paused
        case deleteAccount = "delete-account"

        /// Sheets fit their content; the rest are full screens in the Settings tab.
        var isSheet: Bool {
            switch self {
            case .pause, .paused, .deleteAccount: false
            default: true
            }
        }
    }

    @Test(arguments: Screen.allCases, [DynamicTypeSize.large, .accessibility5])
    func screen(_ screen: Screen, size: DynamicTypeSize) {
        let traits = UITraitCollection { traits in
            traits.displayScale = 2
            traits.userInterfaceStyle = .dark
            traits.preferredContentSizeCategory = size == .large ? .large : .accessibilityExtraExtraExtraLarge
        }
        let name = "\(screen.rawValue)-\(size == .large ? "default" : "ax5")"

        if screen.isSheet {
            let view = content(screen)
                .padding(.horizontal, GlowSpacing.screenMargin)
                .padding(.vertical, GlowSpacing.xl)
                .frame(width: 393)
                .background(.glowSurface)
                .environment(\.dynamicTypeSize, size)
                .environment(\.colorScheme, .dark)
            assertSnapshot(
                of: view,
                as: .image(precision: 0.99, perceptualPrecision: 0.98, layout: .sizeThatFits, traits: traits),
                named: name,
            )
        } else {
            let view = NavigationStack { content(screen) }
                .environment(\.dynamicTypeSize, size)
                .environment(\.colorScheme, .dark)
            assertSnapshot(
                of: view,
                as: .image(
                    precision: 0.99,
                    perceptualPrecision: 0.98,
                    layout: .fixed(width: 393, height: 852),
                    traits: traits,
                ),
                named: name,
            )
        }
    }

    @ViewBuilder
    private func content(_ screen: Screen) -> some View {
        let api = GlowAPI.mock()
        switch screen {
        case .blockCard:
            BlockContent(model: BlockModel(context: .card(card), api: api, analytics: NoopAnalytics()))
        case .blockMatch:
            BlockContent(model: BlockModel(context: .match(match), api: api, analytics: NoopAnalytics()))
        case .blockFailed:
            BlockContent(model: blockModel(phase: .failed(.offline)))
        case .blockDone:
            BlockContent(model: blockModel(phase: .done))
        case .report:
            ReportContent(model: reportModel(phase: .ready))
        case .reportDone:
            ReportContent(model: reportModel(phase: .done))
        case .pause:
            PauseContent(model: PauseModel(
                api: api, session: PreviewSessionService(), analytics: NoopAnalytics(), paused: false,
            ))
            .background(.glowBackground)
            .navigationTitle("Pause")
        case .paused:
            PauseContent(model: PauseModel(
                api: api, session: PreviewSessionService(), analytics: NoopAnalytics(), paused: true,
            ))
            .background(.glowBackground)
            .navigationTitle("Pause")
        case .deleteAccount:
            DeleteAccountContent(model: DeleteAccountModel(
                api: api, session: PreviewSessionService(), analytics: NoopAnalytics(),
            ))
            .background(.glowBackground)
            .navigationTitle("Delete account")
        }
    }

    private func blockModel(phase: SafetyPhase) -> BlockModel {
        let model = BlockModel(context: .card(card), api: .mock(), analytics: NoopAnalytics())
        model.phase = phase
        return model
    }

    private func reportModel(phase: SafetyPhase) -> ReportModel {
        let model = ReportModel(context: .chat(match), api: .mock(), analytics: NoopAnalytics())
        model.reason = .harassment
        model.details = "Kept messaging after I said no."
        model.phase = phase
        return model
    }
}
