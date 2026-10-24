import APIClient
import AppCore
import Foundation
import OpenAPIRuntime

/// Why a profile call didn't work, in words the screens can show. Nothing personal in any case.
public enum ProfileError: Error, Hashable, Sendable {
    /// 422 `under_18`. Nothing was stored (P10).
    case under18
    /// 400: the server didn't accept a field (the app checks first, so this is rare).
    case invalid
    /// 422 `photo_rejected`, with the reason the moderation gave.
    case photoRejected(PhotoRejection)
    /// The photo is too big even after preparing it.
    case photoTooLarge
    /// 503: moderation couldn't check the photo. Nothing was stored; try again.
    case moderationUnavailable
    /// 409 `last_photo`: a finished profile keeps at least one approved photo.
    case lastPhoto
    /// 409 `onboarding_incomplete`.
    case onboardingIncomplete
    /// 409 `conflict`: another change landed at the same moment. Try again.
    case conflict
    /// 404: that photo isn't there (or isn't yours, which looks the same, P11).
    case notFound
    case offline
    case rateLimited
    /// 401: the session ended. The session signs out.
    case signedOut
    case unexpected
}

/// The moderation's reason for refusing a profile photo.
public enum PhotoRejection: String, Hashable, Sendable {
    case faceVisible = "face_visible"
    case nudity
    case noOutfit = "no_outfit"
    case noPerson = "no_person"
    case possiblyMinor = "possibly_minor"
    case unreadable
    case other
}

/// The calls that change the signed-in person's own profile and photos. Every call that returns
/// a newer `Me` hands it to the session, so `states()` and `profiles()` follow at once.
public struct ProfileClient: Sendable {
    public let api: GlowAPI
    public let session: any SessionService

    public init(api: GlowAPI, session: any SessionService) {
        self.api = api
        self.session = session
    }

    /// `PUT /api/me/profile`.
    @discardableResult
    public func save(_ update: Components.Schemas.ProfileUpdate) async throws(ProfileError) -> Me {
        let output = try await call { try await $0.updateProfile(body: .json(update)) }
        switch output {
        case let .ok(ok):
            guard case let .json(me) = ok.body else { throw .unexpected }
            await session.apply(me)
            return me
        case .badRequest:
            throw .invalid
        case let .unprocessableContent(response):
            throw Self.error(from: try? response.body.json)
        case .tooManyRequests:
            throw .rateLimited
        case .unauthorized, .default:
            throw .unexpected
        }
    }

    /// `POST /api/me/photos`. `jpeg` must already be prepared (`ProfilePhotoPreparer`).
    public func addPhoto(jpeg: Data, position: Int) async throws(ProfileError) -> Components.Schemas.MyPhoto {
        let body = Components.Schemas.NewProfilePhoto(position: position, photo: Base64EncodedData(jpeg))
        let output = try await call { try await $0.addProfilePhoto(body: .json(body)) }
        switch output {
        case let .created(created):
            guard case let .json(photo) = created.body else { throw .unexpected }
            return photo
        case .badRequest:
            throw .invalid
        case .contentTooLarge:
            throw .photoTooLarge
        case let .unprocessableContent(response):
            throw Self.error(from: try? response.body.json)
        case .tooManyRequests:
            throw .rateLimited
        case .serviceUnavailable:
            throw .moderationUnavailable
        case .unauthorized, .default:
            throw .unexpected
        }
    }

    /// `GET /api/me/photos/{id}`: one of my own photos, as JPEG bytes. Never cached (D42).
    public func photoData(id: String) async throws(ProfileError) -> Data {
        let output = try await call { try await $0.getMyPhoto(path: .init(id: id)) }
        guard case let .ok(ok) = output, case let .jpeg(body) = ok.body else { throw .unexpected }
        do {
            return try await Data(collecting: body, upTo: 4_000_000)
        } catch {
            throw .unexpected
        }
    }

    /// `DELETE /api/me/photos/{id}`.
    public func deletePhoto(id: String) async throws(ProfileError) {
        let output = try await call { try await $0.deleteProfilePhoto(path: .init(id: id)) }
        switch output {
        case .noContent:
            return
        case let .conflict(response):
            throw Self.error(from: try? response.body.json)
        case .unauthorized, .notFound, .default:
            throw .unexpected
        }
    }

    /// `POST /api/me/onboarding/complete`. Called from the notifications step whatever the
    /// person answered: declining notifications never blocks anyone.
    @discardableResult
    public func finishOnboarding() async throws(ProfileError) -> Me {
        let output = try await call { try await $0.completeOnboarding() }
        switch output {
        case let .ok(ok):
            guard case let .json(me) = ok.body else { throw .unexpected }
            await session.apply(me)
            return me
        case let .conflict(response):
            throw Self.error(from: try? response.body.json)
        case .tooManyRequests:
            throw .rateLimited
        case .unauthorized, .default:
            throw .unexpected
        }
    }

    // MARK: Errors

    private func call<Output: Sendable>(
        _ operation: (Client) async throws -> Output,
    ) async throws(ProfileError) -> Output {
        do {
            return try await api.perform(operation)
        } catch {
            if error == .unauthorized {
                // Let the session find out and sign out.
                _ = try? await session.refreshProfile()
            }
            throw Self.error(from: error)
        }
    }

    /// The profile error for an API failure.
    public static func error(from error: APIError) -> ProfileError {
        switch error {
        case .notFound: .notFound
        case .unauthorized: .signedOut
        case .rateLimited: .rateLimited
        case .offline: .offline
        case .cancelled, .unexpected: .unexpected
        }
    }

    static func error(from body: Components.Schemas._Error?) -> ProfileError {
        guard let error = body?.error else { return .unexpected }
        if error.code == .photoRejected {
            return .photoRejected(error.reason.flatMap(PhotoRejection.init(rawValue:)) ?? .other)
        }
        return codes[error.code] ?? .unexpected
    }

    private static let codes: [Components.Schemas.ErrorCode: ProfileError] = [
        .under18: .under18,
        .lastPhoto: .lastPhoto,
        .onboardingIncomplete: .onboardingIncomplete,
        .conflict: .conflict,
        .badRequest: .invalid,
        .payloadTooLarge: .photoTooLarge,
        .unavailable: .moderationUnavailable,
        .rateLimited: .rateLimited,
    ]
}
