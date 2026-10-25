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

    /// Saves a screenshot of the whole device as `b1-<name>.png` in `TEST_RUNNER_GLOW_SHOTS_DIR`
    /// (docs/shots for the PR's proof). Does nothing without it.
    @MainActor
    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["GLOW_SHOTS_DIR"] else { return }
        Thread.sleep(forTimeInterval: 0.6) // let animations settle
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("b1-\(name).png"))
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
        shot("profile-empty")
        field.tap()
        field.typeText(name + "\n") // Done: closes the keyboard so the taps below land
        app.buttons["profile.gender.woman"].tap()
        XCTAssertTrue(app.buttons["profile.gender.woman"].isSelected)
        app.buttons["profile.showMe.man"].tap()
        XCTAssertTrue(app.buttons["profile.continue"].waitForExistence(timeout: 5))
        shot("profile-filled")
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
        shot("under-18")
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

    /// The welcome and profile screens at the largest accessibility text size (no backend).
    @MainActor
    func testLargestTextScreens() {
        guard ProcessInfo.processInfo.environment["GLOW_SHOTS_DIR"] != nil else { return }
        for (session, name) in [("signedOut", "welcome-largest-text"), ("onboarding", "profile-largest-text")] {
            let app = XCUIApplication()
            app.launchArguments += [
                "-GlowPreviewSession", session,
                "-GlowResetAgeGate", "YES",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
            app.launch()
            XCTAssertTrue(app.staticTexts.firstMatch.waitForExistence(timeout: 10))
            shot(name)
            app.terminate()
        }
    }

    /// A fresh test person signs in with the Debug test sign-in and reaches the tabs:
    /// profile, one photo from the library, notifications ("Not now").
    @MainActor
    func testTestSignInReachesAFinishedProfile() throws {
        let app = XCUIApplication()
        let email = "b1-ui-\(UUID().uuidString.prefix(8).lowercased())@glow.test"
        app.launchArguments += [
            "-GlowSignOutAtLaunch", "YES",
            "-GlowDebugTestLogin", email,
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
        shot("photos-empty")
        slot.tap()
        // The system photo picker: take the first photo in the library.
        // (Its thumbnails are the images with this identifier; the app's own tiles are images too.)
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        if !photo.waitForExistence(timeout: 10) {
            throw XCTSkip("The Simulator's photo library is empty (scripts/sim.sh photos A).")
        }
        // The picker animates in and lives in another process, where isHittable is unreliable:
        // wait a moment, then tap the middle of the thumbnail by coordinate.
        Thread.sleep(forTimeInterval: 1.5)
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let next = app.buttons["photos.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: next)
        waitForExpectations(timeout: 20)
        shot("photos-added")
        next.tap()

        let notNow = app.buttons["notifications.skip"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 15))
        shot("notifications")
        notNow.tap()

        XCTAssertTrue(app.tabBars.buttons["Rooms"].waitForExistence(timeout: 15))
        shot("tabs")
        captureSettings(app)
    }

    /// Settings, Edit profile and Edit photos, for the PR's proof.
    @MainActor
    private func captureSettings(_ app: XCUIApplication) {
        guard ProcessInfo.processInfo.environment["GLOW_SHOTS_DIR"] != nil else { return }
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings.editProfile"].waitForExistence(timeout: 10))
        shot("settings")
        app.buttons["settings.editProfile"].tap()
        XCTAssertTrue(app.textFields["editProfile.firstName"].waitForExistence(timeout: 10))
        shot("edit-profile")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["settings.editPhotos"].tap()
        XCTAssertTrue(app.buttons["editPhotos.slot.0"].waitForExistence(timeout: 10))
        shot("edit-photos")
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
        shot("welcome")
        getStarted.tap()
        XCTAssertTrue(app.buttons["signIn.email"].waitForExistence(timeout: 5))
        shot("sign-in")
        app.buttons["signIn.email"].tap()
        let field = app.textFields["email.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(email)
        shot("email")
        app.buttons["email.send"].tap()

        let code = try XCTUnwrap(waitForCode(to: email, mailpit: mailpit), "No code arrived in Mailpit")
        let codeField = app.textFields.firstMatch
        XCTAssertTrue(codeField.waitForExistence(timeout: 10))
        shot("code")
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
