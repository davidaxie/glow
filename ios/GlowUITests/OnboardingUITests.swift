import XCTest

/// B1's onboarding, end to end in the app (cross-owner in D1's folder, for P10's UI test).
///
/// `testUnder18IsStoppedAndStaysStopped` needs no backend: the 18+ check runs on the phone before
/// anything is sent. `testTestSignInReachesAFinishedProfile` needs a local server with
/// `ALLOW_TEST_LOGIN` at the build's API URL, and skips itself without one.
/// `testEmailCodeReachesAFinishedProfile` also needs the stack's Mailpit (see the test).
final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Today minus 17 years, as `YYYY-MM-DD`.
    private var seventeenYearsAgo: String {
        let date = Calendar(identifier: .gregorian).date(byAdding: .year, value: -17, to: .now) ?? .now
        return date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }

    @MainActor
    private func fillProfile(_ app: XCUIApplication, name: String) {
        let field = app.textFields["profile.firstName"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(name)
        app.buttons["profile.gender.woman"].tap()
        app.buttons["profile.showMe.man"].tap()
        app.buttons["profile.continue"].tap()
    }

    /// P10: an under-18 birthday gets the kind message and no way forward, and the profile step
    /// stays closed after relaunching.
    @MainActor
    func testUnder18IsStoppedAndStaysStopped() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-GlowPreviewSession", "onboarding",
            "-GlowResetAgeGate", "YES",
            "-GlowTestBirthday", seventeenYearsAgo,
        ]
        app.launch()
        fillProfile(app, name: "Sam")

        XCTAssertTrue(app.otherElements["onboarding.underAge"].waitForExistence(timeout: 5)
            || app.staticTexts["Glow is for adults"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Glow is for adults"].exists)
        XCTAssertTrue(app.buttons["underAge.signOut"].exists)
        XCTAssertFalse(app.buttons["profile.continue"].exists)

        // Relaunch without resetting: still closed.
        app.terminate()
        let again = XCUIApplication()
        again.launchArguments += ["-GlowPreviewSession", "onboarding"]
        again.launch()
        XCTAssertTrue(again.staticTexts["Glow is for adults"].waitForExistence(timeout: 10))
        XCTAssertFalse(again.textFields["profile.firstName"].exists)
        again.terminate()

        // Leave the Simulator as it was for the next test.
        let reset = XCUIApplication()
        reset.launchArguments += ["-GlowPreviewSession", "onboarding", "-GlowResetAgeGate", "YES"]
        reset.launch()
        XCTAssertTrue(reset.textFields["profile.firstName"].waitForExistence(timeout: 10))
    }

    /// A fresh test person signs in with the Debug test sign-in and reaches the tabs:
    /// profile, one photo from the library, notifications ("Not now").
    @MainActor
    func testTestSignInReachesAFinishedProfile() throws {
        let app = XCUIApplication()
        let email = "b1-ui-\(UUID().uuidString.prefix(8).lowercased())@glow.test"
        app.launchArguments += [
            "-GlowSignOutAtLaunch", "YES",
            "-GlowTestSignIn", email,
            "-GlowResetAgeGate", "YES",
            "-GlowTestBirthday", "1999-04-12",
        ]
        app.launch()

        let profile = app.textFields["profile.firstName"]
        if !profile.waitForExistence(timeout: 20) {
            throw XCTSkip("Needs a local server with ALLOW_TEST_LOGIN at the build's API URL.")
        }
        fillProfile(app, name: "Robin")

        try finishPhotosAndNotifications(app)
    }

    /// Photos (the first one in the library), then notifications ("Not now"), then the tabs.
    @MainActor
    private func finishPhotosAndNotifications(_ app: XCUIApplication) throws {
        let slot = app.buttons["photos.slot.0"]
        XCTAssertTrue(slot.waitForExistence(timeout: 15))
        slot.tap()
        // The system photo picker: take the first photo in the library.
        let photo = app.scrollViews.otherElements.images.firstMatch
        if !photo.waitForExistence(timeout: 10) {
            throw XCTSkip("The Simulator's photo library is empty (scripts/sim.sh photos A).")
        }
        photo.tap()

        let next = app.buttons["photos.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: next)
        waitForExpectations(timeout: 20)
        next.tap()

        let notNow = app.buttons["notifications.skip"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 15))
        notNow.tap()

        XCTAssertTrue(app.tabBars.buttons["Rooms"].waitForExistence(timeout: 15))
    }

    /// A fresh install signs in with the 6-digit email code and reaches the tabs. Reads the code
    /// from the stack's Mailpit: set `TEST_RUNNER_GLOW_MAILPIT_URL` (for B1's own stack,
    /// `http://127.0.0.1:55114`) when running `scripts/sim.sh test ui`. Skips without it.
    @MainActor
    func testEmailCodeReachesAFinishedProfile() throws {
        guard let mailpit = ProcessInfo.processInfo.environment["GLOW_MAILPIT_URL"].flatMap(URL.init(string:)) else {
            throw XCTSkip("Set TEST_RUNNER_GLOW_MAILPIT_URL to the stack's Mailpit to run this.")
        }
        let email = "b1-code-\(UUID().uuidString.prefix(8).lowercased())@glow.test"
        let app = XCUIApplication()
        app.launchArguments += [
            "-GlowSignOutAtLaunch", "YES",
            "-GlowResetAgeGate", "YES",
            "-GlowTestBirthday", "1999-04-12",
        ]
        app.launch()

        let getStarted = app.buttons["onboarding.getStarted"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 15))
        getStarted.tap()
        app.buttons["signIn.email"].tap()
        let field = app.textFields["email.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(email)
        app.buttons["email.send"].tap()

        let code = try XCTUnwrap(waitForCode(to: email, mailpit: mailpit), "No code arrived in Mailpit")
        let codeField = app.textFields.firstMatch
        XCTAssertTrue(codeField.waitForExistence(timeout: 10))
        codeField.tap()
        codeField.typeText(code) // six digits sign in at once

        fillProfile(app, name: "Robin")
        try finishPhotosAndNotifications(app)
    }

    /// Polls Mailpit for the newest email to `address`, and returns its 6-digit code.
    private func waitForCode(to address: String, mailpit: URL) -> String? {
        for _ in 0 ..< 30 {
            if let code = latestCode(to: address, mailpit: mailpit) {
                return code
            }
            Thread.sleep(forTimeInterval: 1)
        }
        return nil
    }

    private func latestCode(to address: String, mailpit: URL) -> String? {
        guard let list = fetchJSON(mailpit.appending(path: "api/v1/messages").appending(queryItems: [.init(name: "limit", value: "50")])),
              let messages = list["messages"] as? [[String: Any]],
              let message = messages
                  .first(where: { ($0["To"] as? [[String: Any]])?.contains { $0["Address"] as? String == address } == true }),
              let id = message["ID"] as? String,
              let full = fetchJSON(mailpit.appending(path: "api/v1/message/\(id)")),
              let html = full["HTML"] as? String,
              let match = html.firstMatch(of: />\s*(\d{6})\s*</)
        else { return nil }
        return String(match.1)
    }

    private func fetchJSON(_ url: URL) -> [String: Any]? {
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: [String: Any]?
        URLSession.shared.dataTask(with: url) { data, _, _ in
            result = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 5)
        return result
    }
}
