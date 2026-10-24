import APIClient
import AppCore
import DesignSystem
import Foundation

// Owner: C1. DeckModel, continued: tapping, block and report, Be visible, and capture reports.

extension DeckModel {
    /// "That's them": asks to confirm.
    func requestTap(_ card: CardID) {
        guard cards.contains(where: { $0.id == card }) else { return }
        confirming = card
    }

    func cancelTap() {
        confirming = nil
    }

    /// Block or report from a card: the card leaves my deck at once, before B8's sheet even sends
    /// (C1-D6). The server's block removes it for good; if the sheet is cancelled, it comes back on a
    /// refresh after a minute.
    func hideForSafety(_ card: CardID) {
        locallyHidden[card] = now().addingTimeInterval(60)
        cards.removeAll { $0.id == card }
        confirming = nil
        enlarged = nil
    }

    func isLocallyHidden(_ card: CardID) -> Bool {
        guard let until = locallyHidden[card] else { return false }
        if until > now() {
            return true
        }
        locallyHidden[card] = nil
        return false
    }

    /// Sends the secret tap. Returns the match when it's mutual, for the hand-off to FeatureMatch.
    func confirmTap() async -> MatchID? {
        guard let card = confirming, !isTapping else { return nil }
        isTapping = true
        defer { isTapping = false }
        do {
            let outcome = try await service.tap(card, in: roomID)
            tapsLeftToday = outcome.tapsLeftToday
            if let index = cards.firstIndex(where: { $0.id == card }) {
                cards[index].tappedByMe = true
            }
            confirming = nil
            let seconds = firstShownAt.map { Int(now().timeIntervalSince($0).rounded()) } ?? 0
            switch outcome {
            case .sent:
                analytics.track(AnalyticsEvent("deck_tap", ["result": "sent", "seconds": .int(seconds)]))
                toast = GlowToastMessage(DeckCopy.tapSent, kind: .success)
                return nil
            case let .mutual(match, _):
                analytics.track(AnalyticsEvent("deck_tap", ["result": "mutual", "seconds": .int(seconds)]))
                enlarged = nil
                return match
            }
        } catch {
            tapFailed(error)
            return nil
        }
    }

    /// What a failed tap tells the person.
    private func tapFailed(_ error: DeckFailure) {
        switch error {
        case .tapLimitReached:
            tapsLeftToday = 0
            confirming = nil
            toast = GlowToastMessage(DeckCopy.noTapsLeft)
        case .notFound:
            confirming = nil
            enlarged = nil
            toast = GlowToastMessage(DeckCopy.cardGone)
            scheduleRefresh()
        case .rateLimited:
            toast = GlowToastMessage(DeckCopy.slowDown, kind: .error)
        case .offline:
            toast = GlowToastMessage(DeckCopy.offline, kind: .error)
        case .cancelled:
            break
        case .signedOut, .unexpected:
            toast = GlowToastMessage(DeckCopy.tapFailed, kind: .error)
        }
    }

    /// The paused empty state's "Be visible".
    func becomeVisible() async -> Bool {
        do {
            let paused = try await service.setPaused(false)
            guard !paused else { return false }
            await reload(showingProgress: true)
            return true
        } catch {
            toast = GlowToastMessage(DeckCopy.pauseFailed, kind: .error)
            return false
        }
    }

    // MARK: Capture (P12)

    /// The screen started being recorded or mirrored while the deck is open. Reported once per
    /// capture, as a recording (B8 can't tell the two apart either, C1-D3).
    func captureChanged(isCaptured: Bool) {
        guard isCaptured else {
            reportedRecording = false
            return
        }
        guard !reportedRecording else { return }
        reportedRecording = true
        enlarged = nil
        confirming = nil
        analytics.track(AnalyticsEvent("deck_capture", ["kind": "recording"]))
        let service = service
        let room = roomID
        Task { await service.reportCapture(.recording, in: room) }
    }

    /// A screenshot was taken while the deck was open: a gentle note, and a report.
    func screenshotTaken() {
        toast = GlowToastMessage(DeckCopy.screenshotNote, duration: .seconds(5))
        analytics.track(AnalyticsEvent("deck_capture", ["kind": "screenshot"]))
        let service = service
        let room = roomID
        Task { await service.reportCapture(.screenshot, in: room) }
    }

    // MARK: Helpers

    static func literal(_ reason: DeckEmptyReason) -> AnalyticsValue {
        switch reason {
        case .quiet: "quiet"
        case .noMatch: "no_match"
        case .viewLimitReached: "view_limit_reached"
        case .paused: "paused"
        case .checkinEnded: "checkin_ended"
        }
    }
}
