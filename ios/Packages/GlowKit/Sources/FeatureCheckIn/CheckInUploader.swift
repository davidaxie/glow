import APIClient
import AppCore
import Foundation
import OpenAPIRuntime

/// The card tags someone picked. Top color is required; hair is optional (hats, hijabs).
public struct CheckInTags: Hashable, Sendable {
    public var topColor: Components.Schemas.TopColor?
    public var hairLength: Components.Schemas.HairLength?
    public var hairColor: Components.Schemas.HairColor?
    public var extras: Set<Components.Schemas.CardExtra>

    public init(
        topColor: Components.Schemas.TopColor? = nil,
        hairLength: Components.Schemas.HairLength? = nil,
        hairColor: Components.Schemas.HairColor? = nil,
        extras: Set<Components.Schemas.CardExtra> = [],
    ) {
        self.topColor = topColor
        self.hairLength = hairLength
        self.hairColor = hairColor
        self.extras = extras
    }

    public var isComplete: Bool {
        topColor != nil
    }

    /// The contract's tags, with extras in a stable order. Nil until a top color is picked.
    public var contract: Components.Schemas.CardTags? {
        guard let topColor else { return nil }
        let ordered = Components.Schemas.CardExtra.allCases.filter(extras.contains)
        return Components.Schemas.CardTags(topColor: topColor, hairLength: hairLength, hairColor: hairColor, extras: ordered)
    }
}

/// Why a check-in didn't go through, in terms the screen can act on.
public enum CheckInFailure: Error, Hashable, Sendable {
    /// Moderation refused the photo. Retake.
    case photoRejected(PhotoRejection)
    /// The join ticket expired or isn't for this room: go back through the room check.
    case roomCheckExpired
    /// The room isn't open right now.
    case roomNotLive
    /// Moderation or the server is briefly down. Try again.
    case unavailable
    case rateLimited
    case offline
    case signedOut
    /// The room doesn't exist (or isn't ours to see).
    case notFound
    case failed
}

/// The `reason` of a 422 `photo_rejected`.
public enum PhotoRejection: String, Hashable, Sendable, CaseIterable {
    case faceVisible = "face_visible"
    case nudity
    case noOutfit = "no_outfit"
    case noPerson = "no_person"
    case possiblyMinor = "possibly_minor"
    case unreadable
}

/// Sends a prepared card photo, the join ticket and the tags to `POST /api/rooms/{id}/checkin`.
///
/// It only accepts a `PreparedCardPhoto`, the output of the on-device blur pipeline, so an
/// original photo can't be uploaded by mistake (P3).
public struct CheckInUploader: Sendable {
    private let api: GlowAPI

    public init(api: GlowAPI) {
        self.api = api
    }

    public func upload(
        _ photo: PreparedCardPhoto,
        tags: Components.Schemas.CardTags,
        roomID: RoomID,
        ticket: JoinTicket,
    ) async throws(CheckInFailure) -> Components.Schemas.MyCheckin {
        let request = Components.Schemas.CheckinRequest(
            ticket: ticket.rawValue,
            photo: Base64EncodedData(photo.jpegData),
            tags: tags,
        )
        let output: Operations.CreateCheckin.Output
        do {
            output = try await api.perform { client in
                try await client.createCheckin(path: .init(id: roomID.rawValue), body: .json(request))
            }
        } catch {
            throw Self.map(error)
        }
        switch output {
        case let .created(created):
            guard case let .json(checkin) = created.body else { throw .failed }
            return checkin
        case let .unprocessableContent(response):
            guard case let .json(body) = response.body else { throw .failed }
            throw Self.map(unprocessable: body.error)
        case let .conflict(response):
            guard case let .json(body) = response.body else { throw .failed }
            throw body.error.code == .roomNotLive ? .roomNotLive : .failed
        case .serviceUnavailable:
            throw .unavailable
        case .unauthorized:
            throw .signedOut
        case .notFound:
            throw .notFound
        case .tooManyRequests:
            throw .rateLimited
        case .badRequest, .contentTooLarge, .default:
            throw .failed
        }
    }

    static func map(unprocessable error: Components.Schemas.ErrorBody) -> CheckInFailure {
        switch error.code {
        case .photoRejected:
            .photoRejected(error.reason.flatMap(PhotoRejection.init(rawValue:)) ?? .unreadable)
        case .joinTicketInvalid, .notInRoom, .locationRequired, .locationInaccurate:
            .roomCheckExpired
        default:
            .failed
        }
    }

    static func map(_ error: APIError) -> CheckInFailure {
        switch error {
        case .notFound: .notFound
        case .unauthorized: .signedOut
        case .rateLimited: .rateLimited
        case .offline: .offline
        case .cancelled, .unexpected: .failed
        }
    }
}
