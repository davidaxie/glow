import AppCore
import Foundation
import Observation

/// State and actions of the drop screen, ported from Double Blind's DropModel.
@MainActor
@Observable
final class BlindDropModel {
    enum Phase: Equatable {
        case loading
        /// The countdown, the progress and the button.
        case idle
        /// The request is in flight (the opening animation plays).
        case opening
        /// The drop opened: these codenames turn over one by one. Empty means nothing new.
        case revealing(names: [String])
        /// The clock couldn't be loaded at all.
        case unavailable(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var status: BlindDropStatus?
    /// A problem with the last attempt to open, shown under the button.
    private(set) var errorText: String?

    private let service: any BlindService
    private let analytics: any Analytics
    /// The opening animation never ends faster than this, even if the server answers instantly.
    private let minimumOpening: Duration

    init(service: any BlindService, analytics: any Analytics = NoopAnalytics(), minimumOpening: Duration = .milliseconds(1400)) {
        self.service = service
        self.analytics = analytics
        self.minimumOpening = minimumOpening
    }

    var mode: BlindDropRules.Mode? {
        status.map(BlindDropRules.mode(for:))
    }

    func load() async {
        do throws(BlindError) {
            let fresh = try await service.dropStatus()
            status = fresh
            if phase == .loading {
                phase = .idle
            }
            if case .unavailable = phase {
                phase = .idle
            }
        } catch {
            if status == nil {
                phase = .unavailable(error.message)
            }
        }
    }

    /// Opens my waiting chats and prepares the reveal.
    func open() async {
        guard phase == .idle else { return }
        phase = .opening
        errorText = nil
        let clock = ContinuousClock()
        let started = clock.now
        do throws(BlindError) {
            let result = try await service.openDrop()
            let names = BlindDropRules.revealNames(result)
            analytics.track(AnalyticsEvent("blind_drop_opened", ["chats": .int(names.count)]))
            let elapsed = clock.now - started
            if elapsed < minimumOpening {
                try? await Task.sleep(for: minimumOpening - elapsed)
            }
            phase = .revealing(names: names)
        } catch .dropNotReady {
            phase = .idle
            errorText = String(localized: "Your drop opens at 8pm. Come back then.")
            await load()
        } catch {
            phase = .idle
            errorText = error.message
        }
    }

    /// Back to the countdown, with fresh numbers.
    func finish() async {
        phase = .idle
        await load()
    }

    func retry() async {
        phase = .loading
        await load()
    }
}
