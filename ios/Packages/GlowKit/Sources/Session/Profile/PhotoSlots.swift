import APIClient
import AppCore
import Foundation
import Observation

/// The three profile photo slots, shared by onboarding's photos step and Settings' Edit photos.
///
/// Photos are kept in memory only, as JPEG bytes: the prepared upload for a new one, or the bytes
/// `GET /api/me/photos/{id}` returned for one already saved. Nothing is written to disk, to the
/// photo library or to any cache.
@MainActor
@Observable
public final class PhotoSlots {
    public enum Status: Hashable, Sendable {
        case empty
        case uploading
        /// Saved and visible to matches.
        case approved
        /// Saved, waiting for a person at Glow to look at it. Shown to nobody until then, and
        /// doesn't count towards finishing onboarding.
        case held
    }

    public struct Slot: Identifiable, Hashable, Sendable {
        public let position: Int
        public var photoID: String?
        public var status: Status
        /// The JPEG to show. Nil while it's still loading or the slot is empty.
        public var image: Data?

        public var id: Int {
            position
        }
    }

    public private(set) var slots: [Slot]
    /// The last thing that went wrong, for the screen to explain.
    public var error: ProfileError?

    private let prepare: @Sendable (Data) throws(ProfilePhotoPreparer.Failure) -> Data

    public init(
        photos: [Components.Schemas.MyPhoto] = [],
        prepare: @escaping @Sendable (Data) throws(ProfilePhotoPreparer.Failure) -> Data = ProfilePhotoPreparer.prepare,
    ) {
        self.prepare = prepare
        slots = (0 ..< GlowConstants.profilePhotosMax).map { Slot(position: $0, photoID: nil, status: .empty, image: nil) }
        show(photos)
    }

    /// Shows the photos a `Me` lists, keeping any image bytes already loaded for them.
    public func show(_ photos: [Components.Schemas.MyPhoto]) {
        for index in slots.indices {
            guard let photo = photos.first(where: { $0.position == slots[index].position }) else {
                if slots[index].status != .uploading {
                    slots[index] = Slot(position: slots[index].position, photoID: nil, status: .empty, image: nil)
                }
                continue
            }
            let keep = slots[index].photoID == photo.id ? slots[index].image : nil
            slots[index] = Slot(position: photo.position, photoID: photo.id, status: Self.status(photo.moderationStatus), image: keep)
        }
    }

    public var approvedCount: Int {
        slots.count(where: { $0.status == .approved })
    }

    public var hasHeld: Bool {
        slots.contains { $0.status == .held }
    }

    public var isUploading: Bool {
        slots.contains { $0.status == .uploading }
    }

    /// Enough approved photos to go on.
    public var isEnough: Bool {
        approvedCount >= GlowConstants.profilePhotosMin && !isUploading
    }

    /// The first empty slot, for "Add photo".
    public var nextEmptyPosition: Int? {
        slots.first { $0.status == .empty }?.position
    }

    /// Fetches the bytes of every saved photo that isn't loaded yet.
    public func loadImages(using client: ProfileClient) async {
        for slot in slots where slot.photoID != nil && slot.image == nil {
            guard let id = slot.photoID, let data = try? await client.photoData(id: id) else { continue }
            if let index = slots.firstIndex(where: { $0.photoID == id }) {
                slots[index].image = data
            }
        }
    }

    /// Prepares `original` (crop, resize, no metadata) and uploads it to `position`, replacing
    /// whatever was there. The original is never kept.
    public func add(_ original: Data, at position: Int, using client: ProfileClient) async {
        guard let index = slots.firstIndex(where: { $0.position == position }) else { return }
        error = nil
        let jpeg: Data
        do {
            jpeg = try prepare(original)
        } catch .tooLarge {
            error = .photoTooLarge
            return
        } catch {
            self.error = .photoRejected(.unreadable)
            return
        }
        let previous = slots[index]
        slots[index] = Slot(position: position, photoID: previous.photoID, status: .uploading, image: jpeg)
        do {
            let photo = try await client.addPhoto(jpeg: jpeg, position: position)
            slots[index] = Slot(position: position, photoID: photo.id, status: Self.status(photo.moderationStatus), image: jpeg)
        } catch {
            slots[index] = previous
            self.error = error
        }
    }

    /// Removes the photo at `position`.
    public func remove(at position: Int, using client: ProfileClient) async {
        guard let index = slots.firstIndex(where: { $0.position == position }), let id = slots[index].photoID else { return }
        error = nil
        do {
            try await client.deletePhoto(id: id)
            slots[index] = Slot(position: position, photoID: nil, status: .empty, image: nil)
        } catch .notFound {
            // Already gone.
            slots[index] = Slot(position: position, photoID: nil, status: .empty, image: nil)
        } catch {
            self.error = error
        }
    }

    static func status(_ moderation: Components.Schemas.ModerationStatus) -> Status {
        switch moderation {
        case .approved: .approved
        // Pending counts as held: not shown, not counted.
        case .held, .pending, .rejected: .held
        }
    }
}
