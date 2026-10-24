import APIClient
import AppCore
import Foundation
import Observation

// Owner: B8. The state behind the block and report sheets and the pause and delete screens.
// Each model calls the API through `GlowAPI` and never holds anyone's user ID: a block or report
// names a card, match or chat, and the server works out the person (P1).

/// Why a safety action didn't go through. Every case is safe to log and show.
public enum SafetyFailure: Error, Hashable, Sendable {
    /// The card or match isn't there any more (expired, left, or already ended). 404 (P11).
    case gone
    case offline
    case rateLimited
    case unexpected

    init(_ error: APIError) {
        switch error {
        case .notFound: self = .gone
        case .offline: self = .offline
        case .rateLimited: self = .rateLimited
        case .unauthorized, .cancelled, .unexpected: self = .unexpected
        }
    }
}

/// Where a safety action is.
public enum SafetyPhase: Hashable, Sendable {
    case ready
    case working
    case done
    case failed(SafetyFailure)

    public var isWorking: Bool {
        self == .working
    }
}

extension SafetyContext {
    /// What the API calls the thing the ID points at.
    var apiContext: Components.Schemas.ReportContext {
        switch self {
        case .card: .card
        case .match: .match
        case .chat: .chat
        }
    }

    /// The card or match ID. Never a user ID.
    var apiID: String {
        switch self {
        case let .card(id): id.rawValue
        case let .match(id): id.rawValue
        case let .chat(id): id.rawValue
        }
    }

    /// The match this context belongs to, if any. Blocking or reporting from it ends the match.
    public var matchID: MatchID? {
        switch self {
        case .card: nil
        case let .match(id), let .chat(id): id
        }
    }

    var analyticsSource: AnalyticsValue {
        switch self {
        case .card: "card"
        case .match: "match"
        case .chat: "chat"
        }
    }
}

/// The reasons a person can pick when reporting, in the order the sheet lists them.
public enum ReportReason: String, CaseIterable, Identifiable, Hashable, Sendable {
    case harassment
    case inappropriatePhoto
    case underage
    case spam
    case unsafe
    case other

    public var id: String {
        rawValue
    }

    var apiReason: Components.Schemas.ReportReason {
        switch self {
        case .harassment: .harassment
        case .inappropriatePhoto: .inappropriatePhoto
        case .underage: .underage
        case .spam: .spam
        case .unsafe: .unsafe
        case .other: .other
        }
    }

    var analyticsValue: AnalyticsValue {
        switch self {
        case .harassment: "harassment"
        case .inappropriatePhoto: "inappropriate_photo"
        case .underage: "underage"
        case .spam: "spam"
        case .unsafe: "unsafe"
        case .other: "other"
        }
    }
}

/// Blocks the person behind a card, match or chat.
@MainActor
@Observable
public final class BlockModel {
    public let context: SafetyContext
    public internal(set) var phase: SafetyPhase = .ready
    private let api: GlowAPI
    private let analytics: any Analytics

    public init(context: SafetyContext, api: GlowAPI, analytics: any Analytics) {
        self.context = context
        self.api = api
        self.analytics = analytics
    }

    public func block() async {
        guard !phase.isWorking, phase != .done else { return }
        phase = .working
        let body = Components.Schemas.BlockRequest(context: context.apiContext, contextId: context.apiID)
        do {
            let output = try await api.perform { @Sendable client in try await client.createBlock(body: .json(body)) }
            guard case .noContent = output else {
                phase = .failed(.unexpected)
                return
            }
            phase = .done
            analytics.track(AnalyticsEvent("safety_blocked", ["from": context.analyticsSource]))
        } catch {
            phase = .failed(SafetyFailure(error))
        }
    }
}

/// Reports the person behind a card, match or chat. Reporting also blocks them.
@MainActor
@Observable
public final class ReportModel {
    public let context: SafetyContext
    public var reason: ReportReason?
    /// Optional details. Trimmed before sending, and capped at REPORT_DETAILS_MAX_CHARS.
    public var details: String = "" {
        didSet {
            if details.count > Self.maxDetails { details = String(details.prefix(Self.maxDetails)) }
        }
    }

    public internal(set) var phase: SafetyPhase = .ready
    private let api: GlowAPI
    private let analytics: any Analytics

    public static let maxDetails = GlowConstants.reportDetailsMaxChars

    public init(context: SafetyContext, api: GlowAPI, analytics: any Analytics) {
        self.context = context
        self.api = api
        self.analytics = analytics
    }

    public var canSubmit: Bool {
        reason != nil && !phase.isWorking && phase != .done
    }

    public func submit() async {
        guard canSubmit, let reason else { return }
        phase = .working
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = Components.Schemas.ReportRequest(
            context: context.apiContext,
            contextId: context.apiID,
            reason: reason.apiReason,
            details: trimmed.isEmpty ? nil : trimmed,
        )
        do {
            let output = try await api.perform { @Sendable client in try await client.createReport(body: .json(body)) }
            guard case .noContent = output else {
                phase = .failed(.unexpected)
                return
            }
            phase = .done
            analytics.track(AnalyticsEvent("safety_reported", [
                "from": context.analyticsSource,
                "reason": reason.analyticsValue,
                "has_details": .bool(!trimmed.isEmpty),
            ]))
        } catch {
            phase = .failed(SafetyFailure(error))
        }
    }
}

/// Pause and resume. While paused, the person's card leaves every deck at once (P8).
@MainActor
@Observable
public final class PauseModel {
    /// What the server last said. Only meaningful once `isLoaded`.
    public private(set) var paused = false
    /// False until the profile has loaded; the toggle stays off and disabled until then.
    public private(set) var isLoaded = false
    public internal(set) var phase: SafetyPhase = .ready
    private let api: GlowAPI
    private let session: any SessionService
    private let analytics: any Analytics

    /// Starts unloaded; call `load()`.
    public init(api: GlowAPI, session: any SessionService, analytics: any Analytics) {
        self.api = api
        self.session = session
        self.analytics = analytics
    }

    /// Starts from a known state, for previews and tests.
    public convenience init(api: GlowAPI, session: any SessionService, analytics: any Analytics, paused: Bool) {
        self.init(api: api, session: session, analytics: analytics)
        self.paused = paused
        isLoaded = true
    }

    /// Reads the current state from the signed-in profile.
    public func load() async {
        if let me = await session.currentProfile() {
            paused = me.profile.paused
            isLoaded = true
        }
    }

    public func setPaused(_ newValue: Bool) async {
        guard isLoaded, !phase.isWorking, newValue != paused else { return }
        phase = .working
        do {
            let output = try await api.perform { @Sendable client in
                try await client.setPaused(body: .json(.init(paused: newValue)))
            }
            guard case let .ok(ok) = output, case let .json(state) = ok.body else {
                phase = .failed(.unexpected)
                return
            }
            paused = state.paused
            phase = .ready
            analytics.track(AnalyticsEvent("safety_paused", ["paused": .bool(state.paused)]))
            // So every screen that shows Visible or Paused follows.
            _ = try? await session.refreshProfile()
        } catch {
            phase = .failed(SafetyFailure(error))
        }
    }
}

/// Deletes the account and everything in it, then signs out.
@MainActor
@Observable
public final class DeleteAccountModel {
    public internal(set) var phase: SafetyPhase = .ready
    private let api: GlowAPI
    private let session: any SessionService
    private let analytics: any Analytics

    public init(api: GlowAPI, session: any SessionService, analytics: any Analytics) {
        self.api = api
        self.session = session
        self.analytics = analytics
    }

    public func delete() async {
        guard !phase.isWorking, phase != .done else { return }
        phase = .working
        do {
            let output = try await api.perform { @Sendable client in try await client.deleteAccount() }
            guard case .noContent = output else {
                phase = .failed(.unexpected)
                return
            }
            phase = .done
            analytics.track(AnalyticsEvent("account_deleted"))
            await session.signOut()
        } catch {
            phase = .failed(SafetyFailure(error))
        }
    }
}
