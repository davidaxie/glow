import APIClient
import AppCore
import Foundation
import os
import UserNotifications

/// Apple push for real: categories at launch, a device token whenever permission allows, and
/// that token on the server (`POST /api/devices`) for whoever is signed in.
///
/// - Xcode (Debug) builds register as `sandbox`, TestFlight (Release) builds as `production`.
/// - The token is uploaded once per person and token. Signing in as someone else moves it
///   (the server gives the new person a fresh device ID).
/// - `unregister()` deletes it on the server; Session calls it before signing out.
/// - Nothing here logs or reports the token or any ID.
public final class LivePushService: PushService {
    private let system: any PushSystem
    private let registrar: PushRegistrar
    private let tasks = OSAllocatedUnfairLock<[Task<Void, Never>]>(initialState: [])

    /// Builds the service and starts it: categories, a token if allowed, and following the session.
    public init(
        api: GlowAPI,
        session: any SessionService,
        environment: Components.Schemas.ApnsEnvironment,
        appVersion: String?,
        analytics: any Analytics,
        system: any PushSystem,
    ) {
        self.system = system
        registrar = PushRegistrar(
            api: api,
            session: session,
            environment: environment,
            appVersion: appVersion,
            analytics: analytics,
        )
        start(session: session)
    }

    deinit {
        for task in tasks.withLock({ $0 }) {
            task.cancel()
        }
    }

    // MARK: PushService

    public func authorization() async -> PushAuthorization {
        await system.authorizationStatus()
    }

    public func requestAuthorization() async throws -> PushAuthorization {
        _ = try await system.requestAuthorization()
        let status = await system.authorizationStatus()
        await registrar.permissionAnswered(status)
        if status.allowsPush {
            await system.registerForRemoteNotifications()
        }
        return status
    }

    public func didRegister(deviceToken: Data) async {
        await registrar.received(token: deviceToken)
    }

    public func didFailToRegister(_: any Error) async {
        await registrar.registrationFailed()
    }

    public func unregister() async {
        await registrar.unregister()
    }

    public func foregroundPresentation(for notification: PushNotification) -> UNNotificationPresentationOptions {
        PushRouting.foregroundPresentation(for: notification)
    }

    public func route(for notification: PushNotification) -> Route? {
        PushRouting.route(for: notification)
    }

    // MARK: Lifecycle

    private func start(session: any SessionService) {
        let system = system
        let registrar = registrar
        system.registerCategories()

        // Apple recommends asking for the token at every launch, and it's cheap: if permission
        // is already granted, the delegate gets the token back within a moment.
        let launch = Task {
            await Self.registerIfAllowed(system)
            for await _ in system.becameActive() {
                await Self.registerIfAllowed(system)
                await registrar.sync()
            }
        }
        // Upload the token when someone signs in; forget the upload when they sign out.
        let follow = Task {
            for await state in session.states() {
                await registrar.sessionChanged(state)
            }
        }
        tasks.withLock { $0 = [launch, follow] }
    }

    private static func registerIfAllowed(_ system: any PushSystem) async {
        if await system.authorizationStatus().allowsPush {
            await system.registerForRemoteNotifications()
        }
    }
}

/// Keeps the token and what the server knows about it. An actor, so uploads never race.
actor PushRegistrar {
    struct Registration: Equatable {
        let userID: String
        let token: String
        let deviceID: String
    }

    private let api: GlowAPI
    private let session: any SessionService
    private let environment: Components.Schemas.ApnsEnvironment
    private let appVersion: String?
    private let analytics: any Analytics
    private let logger = Logger(subsystem: Log.subsystem, category: "push")

    private(set) var token: String?
    private(set) var registration: Registration?
    private var inFlight: Task<Void, Never>?

    init(
        api: GlowAPI,
        session: any SessionService,
        environment: Components.Schemas.ApnsEnvironment,
        appVersion: String?,
        analytics: any Analytics,
    ) {
        self.api = api
        self.session = session
        self.environment = environment
        self.appVersion = appVersion
        self.analytics = analytics
    }

    func received(token data: Data) async {
        token = data.map { String(format: "%02x", $0) }.joined()
        await sync()
    }

    func registrationFailed() {
        logger.error("Apple didn't give a push token")
        analytics.track(AnalyticsEvent("push_token_failed"))
    }

    func permissionAnswered(_ status: PushAuthorization) {
        analytics.track(AnalyticsEvent("push_permission", ["allowed": .bool(status.allowsPush)]))
    }

    func sessionChanged(_ state: SessionState) async {
        switch state {
        case .restoring:
            return
        case .signedOut:
            // The session is gone, so the server can't be told. Session calls `unregister()`
            // before signing out; this only forgets the upload so the next person gets theirs.
            registration = nil
        case .onboarding, .ready:
            await sync()
        }
    }

    /// Uploads the token for the signed-in person, unless the server already has it for them.
    /// Calls that overlap wait for the upload in flight instead of sending a second one.
    func sync() async {
        while true {
            // `runUpload` clears `inFlight` on this actor before its task finishes, so after this
            // wait `inFlight` is nil or a newer upload, never the finished one.
            while let current = inFlight {
                await current.value
            }
            guard let token, let userID = await session.currentUserID() else { return }
            if let registration, registration.userID == userID, registration.token == token {
                return
            }
            // Another call may have started an upload while this one asked the session.
            guard inFlight == nil else { continue }
            let upload = Task { await self.runUpload(token: token, userID: userID) }
            inFlight = upload
            await upload.value
            return
        }
    }

    private func runUpload(token: String, userID: String) async {
        await upload(token: token, userID: userID)
        inFlight = nil
    }

    private func upload(token: String, userID: String) async {
        let body = Components.Schemas.DeviceRegistration(apnsToken: token, environment: environment, appVersion: appVersion)
        do {
            let output = try await api.perform { try await $0.registerDevice(body: .json(body)) }
            guard case let .created(created) = output, case let .json(device) = created.body else {
                logger.error("Push token upload was refused")
                analytics.track(AnalyticsEvent("push_token_upload_failed"))
                return
            }
            // The person may have changed while the request was out; only keep a current result.
            guard await session.currentUserID() == userID else { return }
            registration = Registration(userID: userID, token: token, deviceID: device.id)
            logger.info("Registered for push")
            analytics.track(AnalyticsEvent("push_registered", ["sandbox": .bool(environment == .sandbox)]))
        } catch {
            logger.notice("Push token upload failed; will retry when the app is next active")
            analytics.track(AnalyticsEvent("push_token_upload_failed"))
        }
    }

    func unregister() async {
        guard let registration else { return }
        self.registration = nil
        do {
            _ = try await api.perform { try await $0.deleteDevice(path: .init(id: registration.deviceID)) }
            logger.info("Removed push token")
        } catch {
            // A 404 means it's already gone. Anything else: the next sign-in moves the token anyway.
            logger.notice("Couldn't remove the push token")
        }
    }
}
