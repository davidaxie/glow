import APIClient
import AppCore
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Session

/// P10 on the phone: the same 18+ rule as the server and the database (UTC-12, D24).
struct AgeGateTests {
    private func day(_ year: Int, _ month: Int, _ day: Int) -> DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    private func at(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test func isAdultOnTheDayTheyTurn18InUTCMinus12() {
        let noonUTC = at("2026-10-24T12:00:00Z") // 2026-10-24 in UTC-12
        #expect(AgeGate.isAdult(birthday: day(2008, 10, 24), now: noonUTC))
        #expect(!AgeGate.isAdult(birthday: day(2008, 10, 25), now: noonUTC))
        // Earlier the same UTC day it's still the 23rd in UTC-12.
        #expect(!AgeGate.isAdult(birthday: day(2008, 10, 24), now: at("2026-10-24T11:59:59Z")))
    }

    @Test func feb29IsFeb28InACommonYear() {
        #expect(!AgeGate.isAdult(birthday: day(2008, 2, 29), now: at("2026-02-28T12:00:00Z")))
        #expect(AgeGate.isAdult(birthday: day(2008, 2, 29), now: at("2026-03-01T12:00:00Z")))
    }

    @Test func incompleteDatesAreNeverAdult() {
        #expect(!AgeGate.isAdult(birthday: DateComponents(year: 1990), now: .now))
    }

    @Test func formatsTheAPIDate() {
        #expect(AgeGate.isoDate(day(1999, 4, 2)) == "1999-04-02")
        #expect(AgeGate.isoDate(DateComponents(year: 1999)) == nil)
    }

    @Test func theLockKeepsOnlyAYesOrNo() {
        let lock = AgeGateLock(key: "test.ageGate.\(UUID().uuidString)")
        defer { lock.reopen() }
        #expect(!lock.isClosed)
        lock.close()
        #expect(lock.isClosed)
        #expect(UserDefaults.standard.object(forKey: lock.key) as? Bool == true)
        lock.reopen()
        #expect(!lock.isClosed)
    }
}

@MainActor
struct ProfileFormTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func filled(_ birthday: DateComponents, now: Date = .now) -> ProfileForm {
        let calendar = utc
        let form = ProfileForm(calendar: calendar, now: { now })
        form.firstName = "  Robin "
        form.pickBirthday(calendar.date(from: birthday)!)
        form.gender = .nonbinary
        form.toggleShowMe(.man)
        form.toggleShowMe(.woman)
        return form
    }

    @Test func startsNeutral() {
        let form = ProfileForm()
        // The picker starts at today, which is nobody's 18+ birthday, and Continue stays off
        // until a date is picked.
        #expect(!form.birthdayChosen)
        #expect(!form.isComplete)
        #expect(form.birthdateISO == nil)
    }

    @Test func buildsTheRequestInContractShape() throws {
        let form = filled(DateComponents(year: 1999, month: 4, day: 12, hour: 12))
        let update = try #require(form.update)
        #expect(update.firstName == "Robin")
        #expect(update.birthdate == "1999-04-12")
        #expect(update.gender == .nonbinary)
        #expect(update.showMe == [.woman, .man])
    }

    @Test func needsEveryField() {
        let form = filled(DateComponents(year: 1999, month: 4, day: 12, hour: 12))
        form.firstName = "   "
        #expect(!form.isComplete)
        form.firstName = String(repeating: "a", count: ProfileForm.nameLimit + 1)
        #expect(!form.isComplete)
        form.firstName = "Robin"
        form.showMe = []
        #expect(!form.isComplete)
    }

    @Test func under18NeverLeavesThePhoneAndClosesTheGate() async {
        let recorder = APIRecorder()
        let client = ProfileClient(api: recorder.api, session: PreviewSessionService(state: .onboarding(.profile)))
        let lock = AgeGateLock(key: "test.ageGate.\(UUID().uuidString)")
        defer { lock.reopen() }
        let seventeen = Calendar.current.date(byAdding: .year, value: -17, to: .now)!
        let form = filled(utc.dateComponents([.year, .month, .day, .hour], from: seventeen))

        let saved = await form.save(using: client, closeGate: lock)

        #expect(!saved)
        #expect(form.phase == .underAge)
        #expect(lock.isClosed)
        #expect(recorder.operations.isEmpty) // nothing sent: the birthday never left the phone
    }

    @Test func anAdultIsSavedAndTheSessionMovesOn() async {
        let recorder = APIRecorder(["updateProfile": TestData.json(TestData.me(.photos, id: Me.preview().id))])
        let session = PreviewSessionService(state: .onboarding(.profile))
        let client = ProfileClient(api: recorder.api, session: session)
        let form = filled(DateComponents(year: 1999, month: 4, day: 12, hour: 12))

        #expect(await form.save(using: client))
        #expect(recorder.operations == ["updateProfile"])
        #expect(session.current == .onboarding(.photos))
    }

    @Test func theServersUnder18IsTheSameKindMessage() async {
        let recorder = APIRecorder(["updateProfile": TestData.error(.unprocessableContent, "under_18")])
        let client = ProfileClient(api: recorder.api, session: PreviewSessionService(state: .onboarding(.profile)))
        let lock = AgeGateLock(key: "test.ageGate.\(UUID().uuidString)")
        defer { lock.reopen() }
        let form = filled(DateComponents(year: 1999, month: 4, day: 12, hour: 12))

        #expect(await !form.save(using: client, closeGate: lock))
        #expect(form.phase == .underAge)
        #expect(lock.isClosed)
    }

    @Test func startsFromASavedProfile() {
        let form = ProfileForm(existing: Me.preview(step: .complete).profile)
        #expect(form.firstName == "Robin")
        #expect(form.birthdayChosen)
        #expect(form.birthdateISO == "1999-04-12")
        #expect(form.isComplete)
    }
}

struct ProfileClientTests {
    private func client(_ answers: [String: MockTransport.Response]) -> (ProfileClient, PreviewSessionService) {
        let session = PreviewSessionService(state: .onboarding(.photos))
        return (ProfileClient(api: APIRecorder(answers).api, session: session), session)
    }

    @Test(arguments: [
        ("nudity", PhotoRejection.nudity), ("no_person", .noPerson), ("unreadable", .unreadable), ("new_reason", .other),
    ])
    func rejectedPhotosCarryTheirReason(_ reason: String, _ expected: PhotoRejection) async {
        let (client, _) = client(["addProfilePhoto": TestData.error(.unprocessableContent, "photo_rejected", reason: reason)])
        await #expect(throws: ProfileError.photoRejected(expected)) {
            _ = try await client.addPhoto(jpeg: Data([0xFF, 0xD8]), position: 0)
        }
    }

    @Test func moderationOutagesAndSizes() async {
        let (down, _) = client(["addProfilePhoto": TestData.error(.serviceUnavailable, "unavailable", reason: "moderation")])
        await #expect(throws: ProfileError.moderationUnavailable) { _ = try await down.addPhoto(jpeg: Data(), position: 0) }
        let (big, _) = client(["addProfilePhoto": TestData.error(.contentTooLarge, "payload_too_large")])
        await #expect(throws: ProfileError.photoTooLarge) { _ = try await big.addPhoto(jpeg: Data(), position: 0) }
    }

    @Test func aPhotoComesBackWithItsStatus() async throws {
        let (client, _) = client(["addProfilePhoto": TestData.heldPhoto])
        let photo = try await client.addPhoto(jpeg: Data(), position: 1)
        #expect(photo.moderationStatus == .held)
    }

    @Test func theLastPhotoStays() async {
        let (client, _) = client(["deleteProfilePhoto": TestData.error(.conflict, "last_photo")])
        await #expect(throws: ProfileError.lastPhoto) { try await client.deletePhoto(id: "0f0f0f0f-0000-4000-8000-0000000000b1") }
    }

    @Test func someoneElsesPhotoIsJustNotFound() async {
        let (client, _) = client(["deleteProfilePhoto": .status(.notFound)])
        await #expect(throws: ProfileError.notFound) { try await client.deletePhoto(id: "0f0f0f0f-0000-4000-8000-0000000000b9") }
    }

    @Test func finishingMovesTheSessionToReady() async throws {
        let (client, session) = client(["completeOnboarding": TestData.json(TestData.me(.complete, id: Me.preview().id))])
        let me = try await client.finishOnboarding()
        #expect(me.onboardingStep == .complete)
        #expect(session.current == .ready)
    }

    @Test func finishingTooEarlyIsOnboardingIncomplete() async {
        let (client, session) = client(["completeOnboarding": TestData.error(.conflict, "onboarding_incomplete")])
        await #expect(throws: ProfileError.onboardingIncomplete) { try await client.finishOnboarding() }
        #expect(session.current == .onboarding(.photos))
    }
}

/// Photos leave the phone cropped to 4:5, sized down, and with no metadata at all.
struct ProfilePhotoPreparerTests {
    /// A JPEG with a GPS position, a camera and a date in its metadata.
    private func photo(width: Int, height: Int) throws -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
        ))
        context.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 37.8029, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.4484, kCGImagePropertyGPSLongitudeRef: "W",
            ],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "ExampleCam", kCGImagePropertyTIFFModel: "One"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:24 20:15:00"],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func properties(_ jpeg: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test func theOriginalReallyHasMetadata() throws {
        let original = try properties(photo(width: 400, height: 300))
        #expect(original[kCGImagePropertyGPSDictionary] != nil)
    }

    @Test(arguments: [(400, 300), (300, 900), (800, 1000), (4000, 3000)])
    func cropsTo4by5AndDropsAllMetadata(_ width: Int, _ height: Int) throws {
        let jpeg = try ProfilePhotoPreparer.prepare(photo(width: width, height: height))
        let props = try properties(jpeg)
        let outWidth = try #require(props[kCGImagePropertyPixelWidth] as? Int)
        let outHeight = try #require(props[kCGImagePropertyPixelHeight] as? Int)
        #expect(abs(Double(outWidth) / Double(outHeight) - 0.8) < 0.01)
        #expect(max(outWidth, outHeight) <= GlowConstants.photoMaxDimensionPixels)
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        #expect((props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] == nil)
        #expect((props[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] == nil)
        #expect(jpeg.count <= GlowConstants.photoMaxBytes)
        let text = String(decoding: jpeg, as: UTF8.self)
        #expect(!text.contains("ExampleCam"))
    }

    @Test func aBigPhotoComesOutAt1920Tall() throws {
        let jpeg = try ProfilePhotoPreparer.prepare(photo(width: 3024, height: 4032))
        let props = try properties(jpeg)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 1920)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 1536)
    }

    @Test func refusesWhatIsNotAnImage() {
        #expect(throws: ProfilePhotoPreparer.Failure.unreadable) { try ProfilePhotoPreparer.prepare(Data("not a photo".utf8)) }
    }

    @Test func cropMath() {
        #expect(ProfilePhotoPreparer.cropRect(width: 1000, height: 1000) == CGRect(x: 100, y: 0, width: 800, height: 1000))
        #expect(ProfilePhotoPreparer.cropRect(width: 800, height: 2000) == CGRect(x: 0, y: 500, width: 800, height: 1000))
    }
}

@MainActor
struct PhotoSlotsTests {
    private let passThrough: @Sendable (Data) throws(ProfilePhotoPreparer.Failure) -> Data = { $0 }

    @Test func showsWhatMeLists() {
        let slots = PhotoSlots(photos: Me.preview(step: .complete).photos, prepare: passThrough)
        #expect(slots.slots.count == GlowConstants.profilePhotosMax)
        #expect(slots.approvedCount == 1)
        #expect(slots.isEnough)
        #expect(slots.nextEmptyPosition == 1)
    }

    @Test func aHeldPhotoIsStoredButDoesntCount() async {
        let client = ProfileClient(api: APIRecorder(["addProfilePhoto": TestData.heldPhoto]).api, session: PreviewSessionService())
        let slots = PhotoSlots(prepare: passThrough)
        await slots.add(Data([1, 2, 3]), at: 1, using: client)
        #expect(slots.slots[1].status == .held)
        #expect(slots.hasHeld)
        #expect(!slots.isEnough)
    }

    @Test func anApprovedPhotoIsEnough() async {
        let client = ProfileClient(api: APIRecorder(["addProfilePhoto": TestData.photo]).api, session: PreviewSessionService())
        let slots = PhotoSlots(prepare: passThrough)
        await slots.add(Data([1, 2, 3]), at: 0, using: client)
        #expect(slots.slots[0].status == .approved)
        #expect(slots.slots[0].image == Data([1, 2, 3]))
        #expect(slots.isEnough)
    }

    @Test func aRejectedPhotoLeavesTheSlotAsItWas() async {
        let client = ProfileClient(
            api: APIRecorder(["addProfilePhoto": TestData.error(.unprocessableContent, "photo_rejected", reason: "nudity")]).api,
            session: PreviewSessionService(),
        )
        let slots = PhotoSlots(prepare: passThrough)
        await slots.add(Data([1]), at: 2, using: client)
        #expect(slots.slots[2].status == .empty)
        #expect(slots.slots[2].image == nil)
        #expect(slots.error == .photoRejected(.nudity))
    }

    @Test func anUnreadablePickNeverUploads() async {
        let recorder = APIRecorder()
        let slots = PhotoSlots()
        await slots.add(Data("nope".utf8), at: 0, using: ProfileClient(api: recorder.api, session: PreviewSessionService()))
        #expect(slots.error == .photoRejected(.unreadable))
        #expect(recorder.operations.isEmpty)
    }

    @Test func removingTheLastPhotoIsRefused() async {
        let client = ProfileClient(
            api: APIRecorder(["deleteProfilePhoto": TestData.error(.conflict, "last_photo")]).api,
            session: PreviewSessionService(),
        )
        let slots = PhotoSlots(photos: Me.preview(step: .complete).photos, prepare: passThrough)
        await slots.remove(at: 0, using: client)
        #expect(slots.error == .lastPhoto)
        #expect(slots.slots[0].status == .approved)
    }
}
