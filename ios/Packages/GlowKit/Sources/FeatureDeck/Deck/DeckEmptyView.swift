import APIClient
import AppCore
import DesignSystem
import SwiftUI

// Owner: C1. Why the deck is empty, in the spec's voice, with the one thing to do about it.

struct DeckEmptyView: View {
    let reason: DeckEmptyReason
    @Bindable var model: DeckModel
    let checkInAgain: Route

    @Environment(\.navigate) private var navigate
    @Environment(\.dependencies) private var dependencies
    @State private var isWorking = false

    var body: some View {
        Group {
            switch reason {
            case .noMatch:
                GlowEmptyState(
                    systemImage: "line.3.horizontal.decrease.circle",
                    title: LocalizedStringKey(DeckCopy.emptyNoMatchTitle),
                    message: LocalizedStringKey(DeckCopy.emptyNoMatchMessage),
                ) {
                    Button(DeckCopy.changeNoticed) { model.isNoticeSheetOpen = true }
                        .buttonStyle(.glowSecondary)
                }
            case .quiet:
                GlowEmptyState(
                    systemImage: "moon.stars",
                    title: LocalizedStringKey(DeckCopy.emptyQuietTitle),
                    message: LocalizedStringKey(DeckCopy.emptyQuietMessage),
                )
            case .checkinEnded:
                GlowEmptyState(
                    systemImage: "hourglass",
                    title: LocalizedStringKey(DeckCopy.emptyCheckinTitle),
                    message: LocalizedStringKey(DeckCopy.emptyCheckinMessage),
                ) {
                    Button(DeckCopy.checkInAgain) { navigate(checkInAgain) }
                        .buttonStyle(.glowPrimary)
                        .accessibilityIdentifier("deck.empty.checkInAgain")
                }
            case .paused:
                GlowEmptyState(
                    systemImage: "pause.circle",
                    title: LocalizedStringKey(DeckCopy.emptyPausedTitle),
                    message: LocalizedStringKey(DeckCopy.emptyPausedMessage),
                ) {
                    Button(DeckCopy.emptyPausedAction) {
                        Task {
                            isWorking = true
                            if await model.becomeVisible() {
                                _ = try? await dependencies.session.refreshProfile()
                            }
                            isWorking = false
                        }
                    }
                    .buttonStyle(.glowPrimary)
                    .glowLoading(isWorking)
                    .accessibilityIdentifier("deck.empty.beVisible")
                }
            case .viewLimitReached:
                GlowEmptyState(
                    systemImage: "checkmark.seal",
                    title: LocalizedStringKey(DeckCopy.emptyViewsTitle),
                    message: LocalizedStringKey(DeckCopy.emptyViewsMessage),
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deck.empty.\(reason.rawValue)")
    }
}
