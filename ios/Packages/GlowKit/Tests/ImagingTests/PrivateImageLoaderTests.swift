import APIClient
import AppCore
import Foundation
import HTTPTypes
import OpenAPIRuntime
import os
import Testing
@testable import Imaging

/// The loader C1 and C2 use for card photos and match photos (P4).
struct PrivateImageLoaderTests {
    static let card = "aaaaaaaa-0000-4000-8000-000000000001"
    static let link = "/api/cards/\(card)/image?exp=1793040000&sig=Xb3fQ0x2lN4m3P1QeRrS5T6uV7wX8yZ9a0b1c2d3e4f"
    static let match = MatchID(rawValue: "dddddddd-0000-4000-8000-000000000004")

    struct Sent: Sendable {
        let path: String?
        let operation: String
        let authorization: String?
        let url: URL
    }

    final class Recorder: Sendable {
        let requests = OSAllocatedUnfairLock<[Sent]>(initialState: [])
    }

    static func jpeg() throws -> Data {
        try Upscale.solidJPEG(width: 40, height: 50)
    }

    static func loader(
        status: HTTPResponse.Status = .ok,
        contentType: String = "image/jpeg",
        body: Data? = nil,
        recorder: Recorder = Recorder(),
    ) throws -> PrivateImageLoader {
        let payload = try body ?? jpeg()
        let transport = MockTransport { request, _, baseURL, operation in
            recorder.requests.withLock {
                $0.append(Sent(path: request.path, operation: operation, authorization: request.headerFields[.authorization], url: baseURL))
            }
            var fields = HTTPFields()
            fields[.contentType] = contentType
            fields[.cacheControl] = "no-store"
            return (HTTPResponse(status: status, headerFields: fields), HTTPBody(payload))
        }
        return PrivateImageLoader(api: .mock(transport, tokens: StaticAccessToken("token")))
    }

    @Test func loadsACardThroughTheAPIWithTheLinkAsIs() async throws {
        let recorder = Recorder()
        let photo = try await Self.loader(recorder: recorder).load(.card(signedURL: Self.link))
        #expect(photo.image.size.width == 40)
        let sent = try #require(recorder.requests.withLock { $0.first })
        #expect(sent.path == Self.link)
        #expect(sent.operation == "getCardImage")
        #expect(sent.authorization == "Bearer token")
        #expect(sent.url.host() == "localhost")
    }

    @Test func loadsAMatchPhoto() async throws {
        let recorder = Recorder()
        _ = try await Self.loader(recorder: recorder).load(.matchPhoto(Self.match, index: 2))
        let sent = try #require(recorder.requests.withLock { $0.first })
        #expect(sent.path == "/api/matches/\(Self.match.rawValue)/photos/2")
        #expect(sent.operation == "getMatchPhoto")
    }

    @Test(arguments: [
        "https://evil.example/api/cards/aaaaaaaa-0000-4000-8000-000000000001/image?exp=1&sig=x",
        "//evil.example/api/cards/aaaaaaaa-0000-4000-8000-000000000001/image?exp=1&sig=x",
        "/api/me/photos/aaaaaaaa-0000-4000-8000-000000000001",
        "/api/cards/../me/image?exp=1&sig=x",
        "/api/cards/AAAAAAAA-0000-4000-8000-000000000001/image?exp=1&sig=x",
        "/api/cards/aaaaaaaa-0000-4000-8000-000000000001/image?exp=1&sig=x&viewer=someone",
        "/api/cards/aaaaaaaa-0000-4000-8000-000000000001/image?exp=1",
        "/api/cards/aaaaaaaa-0000-4000-8000-000000000001/image#frag",
        "",
    ])
    func refusesLinksThatAreNotOurCardImages(_ link: String) async throws {
        let recorder = Recorder()
        await #expect(throws: PrivateImageError.invalidSource) {
            try await Self.loader(recorder: recorder).load(.card(signedURL: link))
        }
        #expect(recorder.requests.withLock { $0.isEmpty }, "Nothing may be sent for a bad link")
    }

    @Test(arguments: [-1, 3, 99])
    func refusesMatchPhotoIndexesOutOfRange(_ index: Int) async throws {
        await #expect(throws: PrivateImageError.invalidSource) {
            try await Self.loader().load(.matchPhoto(Self.match, index: index))
        }
    }

    @Test func a404IsNotFound() async throws {
        await #expect(throws: PrivateImageError.notFound) {
            try await Self.loader(status: .notFound, contentType: "application/json", body: Data("{}".utf8))
                .load(.card(signedURL: Self.link))
        }
    }

    @Test func aNonJPEGAnswerIsUnreadable() async throws {
        await #expect(throws: PrivateImageError.unreadable) {
            try await Self.loader(contentType: "text/html", body: Data("<html>".utf8)).load(.card(signedURL: Self.link))
        }
        await #expect(throws: PrivateImageError.unreadable) {
            try await Self.loader(body: Data("not a jpeg".utf8)).load(.card(signedURL: Self.link))
        }
    }

    @Test func otherStatusesFail() async throws {
        await #expect(throws: PrivateImageError.unauthorized) {
            try await Self.loader(status: .unauthorized, contentType: "application/json", body: Data("{}".utf8))
                .load(.card(signedURL: Self.link))
        }
        await #expect(throws: PrivateImageError.failed) {
            try await Self.loader(status: .internalServerError, contentType: "application/json", body: Data("{}".utf8))
                .load(.card(signedURL: Self.link))
        }
    }

    @Test func theAPISessionNeverCaches() {
        let configuration = URLSessionConfiguration.glowAPI
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }

    @Test func aSourceNeverPrintsItsLink() {
        #expect(!String(describing: PrivateImageSource.card(signedURL: Self.link)).contains("sig"))
    }
}
