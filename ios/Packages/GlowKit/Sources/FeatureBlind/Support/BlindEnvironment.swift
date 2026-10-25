import AppCore
import DesignSystem
import Foundation
import SwiftUI
import UIKit

// Owner: X2. Where Blind mode gets its server calls. The app uses the live API (`LiveBlindService`
// over `dependencies.api`); previews and tests inject a `PreviewBlindService`, and Debug builds can
// launch on one:
//
//     -GlowDebugBlind swiping       newcomer, swiping, dropReady, chatting, revealed or capReached
//     -GlowDebugBlindDropClosed YES before tonight's drop (not demo mode)
//     -GlowDebugRoute blind         opens the Blind tab (also blindDrop, blindChat/<id>, ...)

extension EnvironmentValues {
    /// Overrides Blind mode's server calls. Nil means the live API.
    @Entry var blindService: (any BlindService)?
    /// What time it is, for countdowns. Snapshot tests fix it.
    @Entry var blindClock: @Sendable () -> Date = { Date() }
}

extension View {
    /// Runs Blind mode's screens on `service` instead of the live API (previews, tests).
    public func blindService(_ service: any BlindService) -> some View {
        environment(\.blindService, service)
    }
}

@MainActor
extension Dependencies {
    /// The Blind service for this environment: an injected one, a Debug mock, or the live API.
    func blindService(override: (any BlindService)?) -> any BlindService {
        if let override {
            return override
        }
        #if DEBUG
            if let mock = BlindDebugLaunch.shared.service {
                return mock
            }
        #endif
        return LiveBlindService(api: api)
    }
}

#if DEBUG
    /// Debug-only launch arguments for Simulator runs and UI tests. Compiled out of Release.
    @MainActor
    final class BlindDebugLaunch {
        static let shared = BlindDebugLaunch(defaults: .standard)

        /// One mock world for the whole launch, so the deck, the drop and the chats agree.
        let service: PreviewBlindService?

        init(defaults: UserDefaults) {
            guard let value = defaults.string(forKey: "GlowDebugBlind"), !value.isEmpty else {
                service = nil
                return
            }
            let scenario = PreviewBlindService.Scenario(rawValue: value) ?? .swiping
            service = PreviewBlindService(
                PreviewBlindService.Options(scenario: scenario, dropReady: !defaults.bool(forKey: "GlowDebugBlindDropClosed")),
            )
        }
    }
#endif

// MARK: - Photos

/// Photos in memory only, keyed by the signed link, with in-flight de-duplication, so the next
/// cards are ready before they're on top. Nothing is written to disk, and a card's photo is
/// evicted as soon as it has been swiped.
@MainActor
final class BlindImageStore {
    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let service: any BlindService

    init(service: any BlindService) {
        self.service = service
        cache.countLimit = 16
    }

    func hasImage(_ photo: BlindPhoto) -> Bool {
        cache.object(forKey: photo.url as NSString) != nil
    }

    func image(for photo: BlindPhoto) -> UIImage? {
        cache.object(forKey: photo.url as NSString)
    }

    /// The cached image, or one download however many views ask.
    @discardableResult
    func load(_ photo: BlindPhoto) async -> UIImage? {
        if let cached = image(for: photo) {
            return cached
        }
        if let task = inFlight[photo.url] {
            return await task.value
        }
        let service = service
        let key = photo.url
        let task = Task<UIImage?, Never> { [weak self] in
            let loaded = try? await service.photo(photo).image
            if let loaded {
                self?.cache.setObject(loaded, forKey: key as NSString)
            }
            self?.inFlight[key] = nil
            return loaded
        }
        inFlight[key] = task
        return await task.value
    }

    func preload(_ photos: [BlindPhoto]) {
        for photo in photos where !hasImage(photo) && inFlight[photo.url] == nil {
            Task { await load(photo) }
        }
    }

    func evict(_ photo: BlindPhoto) {
        cache.removeObject(forKey: photo.url as NSString)
    }
}

/// One Blind photo, full bleed in its frame. Shows soft frosted light while it loads.
struct BlindPhotoView: View {
    let photo: BlindPhoto
    let store: BlindImageStore
    var cornerRadius: CGFloat = 28
    /// Called when the photo couldn't be loaded (for example its link expired).
    var onFailure: (() -> Void)?

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Rectangle()
            .fill(.glowSurface)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else if failed {
                    Image(systemName: "photo")
                        .glowFont(.title)
                        .foregroundStyle(.glowTextSecondary)
                } else {
                    BlindVeilOrb(seed: photo.url, size: 120).blindBreathing()
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.glowTextPrimary.opacity(0.08), lineWidth: 1)
            }
            .task(id: photo.url) {
                if let cached = store.image(for: photo) {
                    image = cached
                    return
                }
                let loaded = await store.load(photo)
                withAnimation(BlindMotion.fade) {
                    image = loaded
                    failed = loaded == nil
                }
                if loaded == nil {
                    onFailure?()
                }
            }
            .accessibilityLabel(Text("Photo"))
            .accessibilityAddTraits(.isImage)
    }
}
