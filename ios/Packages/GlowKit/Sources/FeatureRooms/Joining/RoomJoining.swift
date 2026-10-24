import APIClient
import AppCore
import Foundation

/// The two server calls behind joining a room: resolve the code or link, then send one fix.
/// A protocol so the join flow is tested without a network.
public protocol RoomJoining: Sendable {
    /// `POST /api/rooms/resolve`: the room a code or link opens.
    func resolve(_ entry: RoomEntry) async throws(JoinFailure) -> RoomInfo
    /// `POST /api/rooms/{id}/join`: the location check. The fix is sent once and dropped.
    func join(_ room: RoomID, entry: RoomEntry, fix: LocationFix) async throws(JoinFailure) -> JoinTicket
}

/// The real thing, through the generated client.
public struct APIRoomJoining: RoomJoining {
    private let api: GlowAPI

    public init(api: GlowAPI) {
        self.api = api
    }

    public func resolve(_ entry: RoomEntry) async throws(JoinFailure) -> RoomInfo {
        let output: Operations.ResolveRoom.Output
        do {
            output = try await api.perform { try await $0.resolveRoom(body: .json(entry.access)) }
        } catch {
            throw JoinFailure(APIError(error))
        }
        switch output {
        case let .ok(ok):
            guard let summary = try? ok.body.json, let room = RoomInfo(summary) else { throw .unexpected }
            return room
        case let .conflict(conflict):
            throw (try? conflict.body.json.error.code) == .onboardingIncomplete ? .onboardingIncomplete : .unexpected
        case .badRequest, .notFound:
            // A code that can't exist and a code that doesn't are the same to the person.
            throw .roomNotFound
        case .tooManyRequests:
            throw .rateLimited
        case .unauthorized, .default:
            throw .unexpected
        }
    }

    public func join(_ room: RoomID, entry: RoomEntry, fix: LocationFix) async throws(JoinFailure) -> JoinTicket {
        let request = Components.Schemas.JoinRequest(
            access: entry.access,
            location: .init(latitude: fix.latitude, longitude: fix.longitude, accuracy: fix.accuracy),
        )
        let output: Operations.JoinRoom.Output
        do {
            output = try await api.perform { try await $0.joinRoom(path: .init(id: room.rawValue), body: .json(request)) }
        } catch {
            let apiError = APIError(error)
            if apiError == .notFound {
                throw entry.isRotatingToken ? .codeChanged : .roomNotFound
            }
            throw JoinFailure(apiError)
        }
        switch output {
        case let .ok(ok):
            guard let ticket = try? ok.body.json else { throw .unexpected }
            return JoinTicket(ticket.ticket)
        case let .unprocessableContent(refused):
            switch try? refused.body.json.error.code {
            case .notInRoom: throw .notInRoom
            case .locationInaccurate: throw .weakSignal
            default: throw .unexpected
            }
        case let .conflict(conflict):
            switch try? conflict.body.json.error.code {
            case .roomNotLive: throw .roomClosed
            case .onboardingIncomplete: throw .onboardingIncomplete
            default: throw .unexpected
            }
        case .notFound:
            throw entry.isRotatingToken ? .codeChanged : .roomNotFound
        case .tooManyRequests:
            throw .rateLimited
        case .badRequest, .unauthorized, .default:
            throw .unexpected
        }
    }
}

extension RoomEntry {
    var access: Components.Schemas.RoomAccess {
        switch self {
        case let .link(slug, token): .link(.init(kind: .link, slug: slug, token: token))
        case let .code(code): .code(.init(kind: .code, code: code))
        }
    }
}

extension RoomInfo {
    init?(_ summary: Components.Schemas.RoomSummary) {
        guard let id = RoomID(validating: summary.id) else { return nil }
        let status: Status = switch summary.status {
        case .live: .live
        case .paused: .paused
        case .ended: .ended
        }
        self.init(id: id, slug: summary.slug, name: summary.name, status: status, startsAt: summary.startsAt, endsAt: summary.endsAt)
    }
}
