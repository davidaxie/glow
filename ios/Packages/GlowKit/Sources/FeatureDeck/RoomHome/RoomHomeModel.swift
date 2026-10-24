import APIClient
import AppCore
import DesignSystem
import Foundation
import Observation

// Owner: C1. The room home: the room's name, my check-in and time left, Visible or Paused, Leave.

@MainActor
@Observable
final class RoomHomeModel {
    enum Phase: Equatable {
        case loading
        case loaded(RoomSnapshot)
        case failed(DeckFailure)
    }

    let roomID: RoomID
    private(set) var phase: Phase = .loading
    /// Paused applies to me in every room (`profiles.paused`, B8).
    private(set) var paused = false
    private(set) var isChangingPause = false
    private(set) var isLeaving = false
    var isConfirmingLeave = false
    var toast: GlowToastMessage?

    var snapshot: RoomSnapshot? {
        if case let .loaded(snapshot) = phase {
            return snapshot
        }
        return nil
    }

    @ObservationIgnored private let service: any DeckService
    @ObservationIgnored private let analytics: any Analytics

    init(roomID: RoomID, service: any DeckService, analytics: any Analytics = NoopAnalytics(), paused: Bool = false) {
        self.roomID = roomID
        self.service = service
        self.analytics = analytics
        self.paused = paused
    }

    /// Fetches the room and my place in it. Keeps what's showing if a refetch fails.
    func load() async {
        do {
            phase = try await .loaded(service.roomState(roomID))
        } catch {
            guard error != .cancelled else { return }
            if snapshot == nil {
                phase = .failed(error)
            }
        }
    }

    /// The person's own paused state, from their profile.
    func profileChanged(paused: Bool) {
        guard !isChangingPause else { return }
        self.paused = paused
    }

    /// The Visible toggle. Returns true if it changed, so the caller can refresh the profile.
    func setVisible(_ visible: Bool) async -> Bool {
        guard !isChangingPause, visible == paused else { return false }
        isChangingPause = true
        defer { isChangingPause = false }
        do {
            paused = try await service.setPaused(!visible)
            analytics.track(AnalyticsEvent("room_visibility_changed", ["paused": .bool(paused)]))
            return true
        } catch {
            toast = GlowToastMessage(DeckCopy.pauseFailed, kind: .error)
            return false
        }
    }

    /// Leave: ends my check-in and deletes my card now. Returns true once I've left.
    func leave() async -> Bool {
        guard !isLeaving else { return false }
        isLeaving = true
        defer { isLeaving = false }
        do {
            try await service.leave(roomID)
        } catch {
            // Leaving a room I'm not in is already a quiet 204; a 404 means the room is gone too.
            guard error == .notFound else {
                toast = GlowToastMessage(DeckCopy.leaveFailed, kind: .error)
                return false
            }
        }
        analytics.track(AnalyticsEvent("room_left"))
        return true
    }

    /// For snapshot tests and previews.
    func preview(_ phase: Phase, paused: Bool = false) {
        self.phase = phase
        self.paused = paused
    }
}
