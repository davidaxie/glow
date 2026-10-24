import APIClient
import AppCore
import Foundation
import HTTPTypes
import ImageIO
import Imaging
import OpenAPIRuntime
import os
import Testing
import Vision
@testable import FeatureCheckIn

enum CheckInFixtures {
    static let ios: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 5 {
            url.deleteLastPathComponent()
        }
        return url
    }()

    static func face(_ name: String = "faces-group-of-3.jpg") throws -> Data {
        try Data(contentsOf: ios.appending(path: "fixtures/faces/\(name)"))
    }

    static let room = RoomID(rawValue: "de000000-0000-4000-8000-000000000001")
    static let card = "aaaaaaaa-0000-4000-8000-000000000001"

    static let created = """
    {"cardId":"\(card)","roomId":"\(room.rawValue)","tags":{"topColor":"green","extras":["glasses"]},
     "visible":true,"joinedAt":"2026-10-24T20:00:00.000Z","expiresAt":"2026-10-24T23:00:00.000Z",
     "image":{"url":"/api/cards/\(card)/image?exp=1793040000&sig=Xb3fQ0x2lN4m3P1QeRrS5T6uV7wX8yZ9a0b1c2d3e4f",
              "expiresAt":"2026-10-24T20:01:00.000Z"}}
    """

    static func error(_ code: String, reason: String? = nil) -> String {
        let reasonField = reason.map { #","reason":"\#($0)""# } ?? ""
        return #"{"error":{"code":"\#(code)","message":"x"\#(reasonField)}}"#
    }
}

/// Captures what the app sends to `createCheckin`.
final class UploadRecorder: Sendable {
    let bodies = OSAllocatedUnfairLock<[Data]>(initialState: [])

    func transport(status: HTTPResponse.Status, json: String) -> MockTransport {
        MockTransport { request, body, _, operation in
            if operation == "createCheckin", let body {
                let data = try await Data(collecting: body, upTo: 10_000_000)
                self.bodies.withLock { $0.append(data) }
            }
            #expect(request.method == .post)
            var fields = HTTPFields()
            fields[.contentType] = "application/json"
            return (HTTPResponse(status: status, headerFields: fields), HTTPBody(Data(json.utf8)))
        }
    }
}

@MainActor
struct CheckInModelTests {
    func model(
        status: HTTPResponse.Status = .created,
        json: String = CheckInFixtures.created,
        recorder: UploadRecorder = UploadRecorder(),
        imaging: (any ImagingService)? = nil,
    ) -> CheckInModel {
        let api = GlowAPI.mock(recorder.transport(status: status, json: json), tokens: StaticAccessToken("token"))
        let context = ServiceContext(config: .preview, api: api, session: PreviewSessionService(), analytics: NoopAnalytics())
        let dependencies = Dependencies.preview(api: api, imaging: imaging ?? ImagingModule.live(context))
        return CheckInModel(roomID: CheckInFixtures.room, ticket: JoinTicket("ticket-123"), dependencies: dependencies)
    }

    /// P3: the only photo that leaves the phone is the blurred, metadata-free one.
    @Test func theUploadCarriesOnlyTheBlurredPhoto() async throws {
        let recorder = UploadRecorder()
        let model = model(recorder: recorder)
        let original = try CheckInFixtures.face()

        await model.photoTaken(original)
        #expect(model.step == .preview)
        let prepared = try #require(model.prepared)
        #expect(prepared.facesBlurred >= 3)
        model.confirmPhoto()
        model.tags.topColor = .green
        model.tags.extras = [.glasses]
        await model.submit()

        #expect(model.step == .done(CardID(rawValue: CheckInFixtures.card)))
        let body = try #require(recorder.bodies.withLock { $0.first })
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(json.keys) == ["ticket", "photo", "tags"])
        #expect(json["ticket"] as? String == "ticket-123")
        let tags = try #require(json["tags"] as? [String: Any])
        #expect(tags["topColor"] as? String == "green")
        #expect(tags["extras"] as? [String] == ["glasses"])

        let base64 = try #require(json["photo"] as? String)
        let uploaded = try #require(Data(base64Encoded: base64))
        // Exactly the photo the preview showed, not the original.
        #expect(uploaded == prepared.jpegData)
        #expect(uploaded != original)
        // No metadata, and Vision finds no face in it.
        #expect(!JPEGSanitizer.hasMetadata(uploaded))
        let source = try #require(CGImageSourceCreateWithData(uploaded as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        #expect(props[kCGImagePropertyExifDictionary as String] == nil)
        #expect(props[kCGImagePropertyGPSDictionary as String] == nil)
        #expect(props[kCGImagePropertyTIFFDictionary as String] == nil)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let request = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        #expect((request.results ?? []).isEmpty)
        // The photo is dropped from memory once it's sent.
        #expect(model.prepared == nil)
        #expect(model.previewImage == nil)
    }

    @Test(arguments: [
        ("face_visible", PhotoRejection.faceVisible),
        ("nudity", PhotoRejection.nudity),
        ("no_outfit", PhotoRejection.noOutfit),
        ("no_person", PhotoRejection.noPerson),
        ("possibly_minor", PhotoRejection.possiblyMinor),
        ("unreadable", PhotoRejection.unreadable),
    ])
    func aRejectedPhotoAsksForARetake(_ reason: String, _ expected: PhotoRejection) async throws {
        let model = model(status: .unprocessableContent, json: CheckInFixtures.error("photo_rejected", reason: reason))
        try await model.photoTaken(CheckInFixtures.face("face-portrait-mann.jpg"))
        model.confirmPhoto()
        model.tags.topColor = .black
        await model.submit()
        #expect(model.notice == .rejected(expected))
        #expect(model.step == .capture)
        #expect(model.prepared == nil)
        #expect(!CheckInCopy.message(for: .rejected(expected)).isEmpty)
    }

    @Test func aFaceVisibleRejectionSaysToRetakeFromTheNeckDown() {
        #expect(CheckInCopy.message(for: .rejected(.faceVisible)).contains("neck down"))
    }

    @Test func anExpiredJoinTicketSendsThemBackToTheRoomCheck() async throws {
        let model = model(status: .unprocessableContent, json: CheckInFixtures.error("join_ticket_invalid"))
        try await model.photoTaken(CheckInFixtures.face("face-portrait-mann.jpg"))
        model.confirmPhoto()
        model.tags.topColor = .black
        await model.submit()
        #expect(model.notice == .roomCheckExpired)
    }

    @Test func aModerationOutageKeepsThePhotoAndTags() async throws {
        let model = model(status: .serviceUnavailable, json: CheckInFixtures.error("unavailable", reason: "moderation"))
        try await model.photoTaken(CheckInFixtures.face("face-portrait-mann.jpg"))
        model.confirmPhoto()
        model.tags.topColor = .black
        await model.submit()
        #expect(model.notice == .unavailable)
        #expect(model.step == .tags)
        #expect(model.prepared != nil)
        #expect(model.tags.topColor == .black)
    }

    @Test func aRoomThatIsNotLiveSaysSo() async throws {
        let model = model(status: .conflict, json: CheckInFixtures.error("room_not_live"))
        try await model.photoTaken(CheckInFixtures.face("face-portrait-mann.jpg"))
        model.confirmPhoto()
        model.tags.topColor = .black
        await model.submit()
        #expect(model.notice == .roomNotLive)
    }

    @Test func aPhotoWithNobodyInItAsksForARetakeBeforeAnythingIsSent() async {
        let recorder = UploadRecorder()
        let model = model(recorder: recorder, imaging: FailingImaging(error: .noPersonFound))
        await model.photoTaken(Data([1, 2, 3]))
        #expect(model.notice == .noPerson)
        #expect(model.step == .capture)
        #expect(recorder.bodies.withLock { $0.isEmpty })
    }

    @Test func checkInNeedsATopColor() async throws {
        let model = model()
        try await model.photoTaken(CheckInFixtures.face("face-portrait-mann.jpg"))
        model.confirmPhoto()
        #expect(!model.canSubmit)
        model.tags.hairLength = .short
        #expect(!model.canSubmit)
        model.tags.topColor = .blue
        #expect(model.canSubmit)
    }

    @Test func retakeForgetsThePhoto() async throws {
        let model = model()
        try await model.photoTaken(CheckInFixtures.face("face-portrait-mann.jpg"))
        #expect(model.previewImage != nil)
        model.retake()
        #expect(model.prepared == nil)
        #expect(model.previewImage == nil)
        #expect(model.step == .capture)
    }

    @Test func tagsGoOutInContractOrder() {
        let tags = CheckInTags(topColor: .red, hairColor: .dyed, extras: [.backpack, .glasses, .hat])
        #expect(tags.contract?.extras == [.glasses, .hat, .backpack])
        #expect(tags.contract?.hairLength == nil)
        #expect(CheckInTags().contract == nil)
    }

    @Test func entryViewKeepsTheRoom() {
        let room = RoomID(rawValue: "00000000-0000-4000-8000-000000000002")
        #expect(CheckInView(roomID: room, ticket: JoinTicket("t")).roomID == room)
    }
}

struct FailingImaging: ImagingService {
    let error: ImagingError

    func prepareCardPhoto(from _: Data) async throws -> PreparedCardPhoto {
        throw error
    }

    func loadPrivateImage(_: PrivateImageSource) async throws(PrivateImageError) -> PrivateImage {
        throw .failed
    }
}
