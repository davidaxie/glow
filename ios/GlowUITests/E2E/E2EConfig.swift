import Foundation
import XCTest

/// What `scripts/e2e/run.sh` hands a journey, through `TEST_RUNNER_GLOW_E2E_*` variables
/// (xcodebuild passes each to the test runner without the prefix).
///
/// Without them a journey skips, so `scripts/sim.sh test` and CI's macOS job stay quick and
/// green: journeys only run through `scripts/e2e/run.sh`, which starts person B and the harness
/// first. D1 owns this folder.
struct E2EConfig {
    /// Player B's instructions, `http://127.0.0.1:<port>` (scripts/e2e/player-b.ts --control).
    let playerB: URL?
    /// The Mac-side helper, `http://127.0.0.1:<port>` (scripts/e2e/harness.ts serve).
    let harness: URL
    /// Person A's test address (`a-xxxxxxxx@glow.test`), for the app's Debug test sign-in.
    let emailA: String
    /// The run's own room link, `glow://r/<slug>?t=<token>`.
    let roomLink: String
    /// The outfit photo the check-in's Debug "Use test photo" button picks.
    let photo: String
    /// ios/fixtures/push, for the push journey.
    let pushFixtures: String?

    static func require(needsPlayerB: Bool = true, file: StaticString = #filePath, line: UInt = #line) throws -> E2EConfig {
        let env = ProcessInfo.processInfo.environment
        guard let harness = env["GLOW_E2E_HARNESS"].flatMap(URL.init(string:)),
              let emailA = env["GLOW_E2E_EMAIL_A"],
              let roomLink = env["GLOW_E2E_ROOM_LINK"],
              let photo = env["GLOW_E2E_PHOTO"]
        else {
            throw XCTSkip("An end-to-end journey: run it with scripts/e2e/run.sh.", file: file, line: line)
        }
        let playerB = env["GLOW_E2E_PLAYER_B"].flatMap(URL.init(string:))
        if needsPlayerB, playerB == nil {
            throw XCTSkip("This journey needs person B: run it with scripts/e2e/run.sh.", file: file, line: line)
        }
        return E2EConfig(
            playerB: playerB,
            harness: harness,
            emailA: emailA,
            roomLink: roomLink,
            photo: photo,
            pushFixtures: env["GLOW_E2E_PUSH_DIR"],
        )
    }
}

/// A local HTTP call from the test runner to a helper on the Mac. Both listen on 127.0.0.1 only.
enum MacHelper {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func post(_ url: URL, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        return try await send(request)
    }

    static func get(_ url: URL) async throws -> Data {
        try await send(URLRequest(url: url, timeoutInterval: 10))
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw Failure(description: "\(request.url?.path ?? "?") answered \(status): \(body)")
        }
        return data
    }
}

/// The harness on the Mac (scripts/e2e/harness.ts serve): what a UI test can't do from inside the
/// Simulator.
struct Harness {
    let base: URL

    /// `xcrun simctl push` with ios/fixtures/push/<fixture>.apns, to this Simulator.
    func push(_ fixture: String) async throws {
        _ = try await MacHelper.post(base.appending(path: "push/\(fixture)"), timeout: 30)
    }

    /// Ends person A's check-in as if its time ran out, then runs the purge cron.
    func expireCheckIn() async throws {
        _ = try await MacHelper.post(base.appending(path: "expire"), timeout: 30)
    }
}
