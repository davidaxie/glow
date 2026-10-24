import APIClient
import AppCore
import Foundation
import os

// Owner: C1. Every server call the deck makes, behind one protocol so the screens are tested and
// previewed without a network.

/// The server calls behind the room home and the deck.
protocol DeckService: Sendable {
    /// `GET /api/rooms/{id}`: the room, my check-in there, and taps and views left today (B2).
    func roomState(_ room: RoomID) async throws(DeckFailure) -> RoomSnapshot
    /// `POST /api/rooms/{id}/deck`: one page of cards that fit me and my filters (B4).
    func deck(_ room: RoomID, filters: NoticedFilters, offset: Int) async throws(DeckFailure) -> DeckPage
    /// `POST /api/rooms/{id}/taps`: a secret tap on a card in my deck (B4).
    func tap(_ card: CardID, in room: RoomID) async throws(DeckFailure) -> TapOutcome
    /// `POST /api/rooms/{id}/leave`: ends my check-in and deletes my card now (B2).
    func leave(_ room: RoomID) async throws(DeckFailure)
    /// `POST /api/me/pause`: pause or resume being visible, in every room (B8). Returns the new state.
    func setPaused(_ paused: Bool) async throws(DeckFailure) -> Bool
    /// `POST /api/abuse/capture`: a screenshot or recording of the deck (B8, P12). Never throws:
    /// a lost report must never get in the way of the person.
    func reportCapture(_ kind: Components.Schemas.CaptureKind, in room: RoomID) async
}

/// The real thing, through the generated client.
struct APIDeckService: DeckService {
    private let api: GlowAPI
    private let logger = Logger(subsystem: Log.subsystem, category: "deck")

    init(api: GlowAPI) {
        self.api = api
    }

    func roomState(_ room: RoomID) async throws(DeckFailure) -> RoomSnapshot {
        let output = try await call { try await $0.getRoomState(path: .init(id: room.rawValue)) }
        switch output {
        case let .ok(ok):
            guard let state = try? ok.body.json else { throw .unexpected }
            return RoomSnapshot(state)
        case .notFound:
            throw .notFound
        case .unauthorized:
            throw .signedOut
        case .default:
            throw .unexpected
        }
    }

    func deck(_ room: RoomID, filters: NoticedFilters, offset: Int) async throws(DeckFailure) -> DeckPage {
        let request = Components.Schemas.DeckRequest(filters: filters.isEmpty ? nil : filters.contract, offset: offset)
        let output = try await call {
            try await $0.getDeck(path: .init(id: room.rawValue), body: .json(request))
        }
        switch output {
        case let .ok(ok):
            guard let deck = try? ok.body.json else { throw .unexpected }
            return DeckPage(deck)
        case .notFound:
            throw .notFound
        case .tooManyRequests:
            throw .rateLimited
        case .unauthorized:
            throw .signedOut
        case .badRequest, .default:
            throw .unexpected
        }
    }

    func tap(_ card: CardID, in room: RoomID) async throws(DeckFailure) -> TapOutcome {
        let output = try await call {
            try await $0.createTap(path: .init(id: room.rawValue), body: .json(.init(cardId: card.rawValue)))
        }
        switch output {
        case let .ok(ok):
            guard let result = try? ok.body.json else { throw .unexpected }
            return try Self.outcome(result)
        case let .conflict(conflict):
            throw (try? conflict.body.json.error.code) == .tapLimitReached ? .tapLimitReached : .unexpected
        case .notFound:
            throw .notFound
        case .tooManyRequests:
            throw .rateLimited
        case .unauthorized:
            throw .signedOut
        case .badRequest, .default:
            throw .unexpected
        }
    }

    /// Sent says only what's left; mutual carries the match. Nothing about the other person (P5).
    private static func outcome(_ result: Components.Schemas.TapResult) throws(DeckFailure) -> TapOutcome {
        let left = max(0, result.tapsLeftToday)
        switch result.result {
        case .sent:
            return .sent(tapsLeftToday: left)
        case .mutual:
            guard let raw = result.matchId, let match = MatchID(validating: raw) else { throw .unexpected }
            return .mutual(match, tapsLeftToday: left)
        }
    }

    func leave(_ room: RoomID) async throws(DeckFailure) {
        let output = try await call { try await $0.leaveRoom(path: .init(id: room.rawValue)) }
        switch output {
        case .noContent:
            return
        case .notFound:
            throw .notFound
        case .unauthorized:
            throw .signedOut
        case .default:
            throw .unexpected
        }
    }

    func setPaused(_ paused: Bool) async throws(DeckFailure) -> Bool {
        let output = try await call { try await $0.setPaused(body: .json(.init(paused: paused))) }
        switch output {
        case let .ok(ok):
            guard let state = try? ok.body.json else { throw .unexpected }
            return state.paused
        case .tooManyRequests:
            throw .rateLimited
        case .unauthorized:
            throw .signedOut
        case .badRequest, .default:
            throw .unexpected
        }
    }

    func reportCapture(_ kind: Components.Schemas.CaptureKind, in room: RoomID) async {
        do {
            let output = try await call {
                try await $0.logCapture(body: .json(.init(kind: kind, roomId: room.rawValue)))
            }
            if case .noContent = output {
                return
            }
            logger.notice("Capture report wasn't accepted")
        } catch {
            logger.notice("Capture report failed")
        }
    }

    private func call<Output: Sendable>(
        _ operation: (Client) async throws -> Output,
    ) async throws(DeckFailure) -> Output {
        do {
            return try await api.perform(operation)
        } catch {
            throw DeckFailure(error)
        }
    }
}
