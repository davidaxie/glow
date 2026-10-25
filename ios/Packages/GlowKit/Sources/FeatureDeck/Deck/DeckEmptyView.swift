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
                DeckQuietState(title: DeckCopy.emptyNoMatchTitle, message: DeckCopy.emptyNoMatchMessage) {
                    Button(DeckCopy.changeNoticed) { model.isNoticeSheetOpen = true }
                        .buttonStyle(.glowSecondary)
                }
            case .quiet:
                DeckQuietState(title: DeckCopy.emptyQuietTitle, message: DeckCopy.emptyQuietMessage)
            case .checkinEnded:
                DeckQuietState(title: DeckCopy.emptyCheckinTitle, message: DeckCopy.emptyCheckinMessage, intensity: 0.5) {
                    Button(DeckCopy.checkInAgain) { navigate(checkInAgain) }
                        .buttonStyle(.glowPrimary)
                        .accessibilityIdentifier("deck.empty.checkInAgain")
                }
            case .paused:
                DeckQuietState(title: DeckCopy.emptyPausedTitle, message: DeckCopy.emptyPausedMessage, intensity: 0.4) {
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
                DeckQuietState(title: DeckCopy.emptyViewsTitle, message: DeckCopy.emptyViewsMessage)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deck.empty.\(reason.rawValue)")
    }
}
