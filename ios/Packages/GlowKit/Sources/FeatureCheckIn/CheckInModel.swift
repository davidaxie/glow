import APIClient
import AppCore
import Foundation
import Observation
import os
import UIKit

/// The check-in flow: outfit photo, on-device blur, "This is what others will see", tags, upload.
///
/// The original photo is held only while the pipeline runs and dropped as soon as the blurred
/// copy exists. Only that copy is shown, and only that copy is uploaded (P3).
@MainActor
@Observable
public final class CheckInModel {
    public enum Step: Equatable {
        /// Take or pick a photo.
        case capture
        /// Finding and blurring faces on the phone.
        case processing
        /// "This is what others will see." Confirm or retake.
        case preview
        /// Top color, hair and extras.
        case tags
        /// Sending the card.
        case uploading
        /// Checked in.
        case done(CardID)
    }

    /// Something to tell the person, with what they can do about it.
    public enum Notice: Equatable {
        case noPerson
        case unreadable
        case processingFailed
        case rejected(PhotoRejection)
        case roomCheckExpired
        case roomNotLive
        case unavailable
        case rateLimited
        case offline
        case failed
    }

    public let roomID: RoomID
    public private(set) var step: Step = .capture
    public private(set) var notice: Notice?
    /// The blurred photo, exactly as it will be uploaded.
    public private(set) var prepared: PreparedCardPhoto?
    /// The blurred photo, decoded for the preview.
    public private(set) var previewImage: UIImage?
    public var tags = CheckInTags()

    private let ticket: JoinTicket
    private let imaging: any ImagingService
    private let uploader: CheckInUploader
    private let analytics: any Analytics
    private let logger = Logger(subsystem: Log.subsystem, category: "checkin")

    public init(roomID: RoomID, ticket: JoinTicket, dependencies: Dependencies) {
        self.roomID = roomID
        self.ticket = ticket
        imaging = dependencies.imaging
        uploader = CheckInUploader(api: dependencies.api)
        analytics = dependencies.analytics
    }

    /// Runs the on-device pipeline on a freshly taken or picked photo.
    public func photoTaken(_ original: Data) async {
        guard step == .capture || step == .preview else { return }
        notice = nil
        step = .processing
        do {
            // `original` is a local copy; it goes out of scope when this returns.
            let photo = try await imaging.prepareCardPhoto(from: original)
            prepared = photo
            previewImage = UIImage(data: photo.jpegData)
            step = .preview
            analytics.track(AnalyticsEvent("checkin_photo_prepared", ["faces_blurred": .int(photo.facesBlurred)]))
        } catch let error as ImagingError {
            discardPhoto()
            notice = switch error {
            case .noPersonFound: .noPerson
            case .unreadableImage: .unreadable
            case .processingFailed: .processingFailed
            }
            step = .capture
            analytics.track(AnalyticsEvent("checkin_photo_retake", ["reason": Self.literal(for: error)]))
        } catch {
            discardPhoto()
            notice = .processingFailed
            step = .capture
            analytics.record(error, context: "checkin.prepare")
        }
    }

    /// The person is happy with the blurred photo.
    public func confirmPhoto() {
        guard step == .preview, prepared != nil else { return }
        step = .tags
    }

    /// Back to the camera, forgetting the photo.
    public func retake() {
        discardPhoto()
        notice = nil
        step = .capture
    }

    /// Back from tags to the preview.
    public func backToPreview() {
        guard step == .tags, prepared != nil else { return }
        step = .preview
    }

    public var canSubmit: Bool {
        step == .tags && prepared != nil && tags.isComplete
    }

    /// Uploads the blurred photo and the tags with the join ticket.
    public func submit() async {
        guard canSubmit, let photo = prepared, let contractTags = tags.contract else { return }
        notice = nil
        step = .uploading
        do {
            let checkin = try await uploader.upload(photo, tags: contractTags, roomID: roomID, ticket: ticket)
            discardPhoto()
            step = .done(CardID(rawValue: checkin.cardId))
            analytics.track(AnalyticsEvent("checkin_created", ["extras": .int(contractTags.extras.count)]))
        } catch {
            handle(error)
        }
    }

    private func handle(_ failure: CheckInFailure) {
        logger.info("Check-in failed: \(String(describing: failure), privacy: .public)")
        switch failure {
        case let .photoRejected(reason):
            discardPhoto()
            notice = .rejected(reason)
            step = .capture
            analytics.track(AnalyticsEvent("checkin_photo_rejected", ["reason": Self.literal(for: reason)]))
        case .roomCheckExpired:
            discardPhoto()
            notice = .roomCheckExpired
            step = .capture
        case .roomNotLive, .notFound:
            discardPhoto()
            notice = .roomNotLive
            step = .capture
        case .unavailable:
            notice = .unavailable
            step = .tags
        case .rateLimited:
            notice = .rateLimited
            step = .tags
        case .offline:
            notice = .offline
            step = .tags
        case .signedOut, .failed:
            notice = .failed
            step = .tags
        }
    }

    private func discardPhoto() {
        prepared = nil
        previewImage = nil
    }

    private static func literal(for error: ImagingError) -> AnalyticsValue {
        switch error {
        case .noPersonFound: "no_person"
        case .unreadableImage: "unreadable"
        case .processingFailed: "processing_failed"
        }
    }

    private static func literal(for reason: PhotoRejection) -> AnalyticsValue {
        switch reason {
        case .faceVisible: "face_visible"
        case .nudity: "nudity"
        case .noOutfit: "no_outfit"
        case .noPerson: "no_person"
        case .possiblyMinor: "possibly_minor"
        case .unreadable: "unreadable"
        }
    }
}
