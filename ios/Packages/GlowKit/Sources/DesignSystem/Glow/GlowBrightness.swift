import SwiftUI
import UIKit

// Owner: B6. Full screen brightness while a glow is showing, and the person's own level back the
// moment it isn't: when the view goes away, the app leaves the foreground, or Control Center opens.
//
//     GlowView(…).glowFullBrightness()          // GlowSurface already does this

/// Anything with a brightness, like `UIScreen`. A protocol so tests can use a fake screen.
@MainActor
public protocol GlowBrightnessAdjustable: AnyObject {
    var brightness: CGFloat { get set }
}

extension UIScreen: GlowBrightnessAdjustable {}

/// Raises screen brightness while at least one holder wants it, and restores the level the person
/// had before the first holder. Holders are counted, so two glow views overlapping during a
/// transition never save the raised level as the person's own.
@MainActor
public final class GlowBrightness {
    /// The app-wide instance the view modifier uses.
    public static let shared = GlowBrightness()

    /// The level while raised, 0 to 1.
    public let raisedLevel: CGFloat
    private var holders: Set<UUID> = []
    private var savedLevel: CGFloat?
    private var screen: (any GlowBrightnessAdjustable)?

    public init(raisedLevel: CGFloat = 1) {
        self.raisedLevel = min(max(raisedLevel, 0), 1)
    }

    /// Whether anything is holding the brightness up.
    public var isRaised: Bool {
        !holders.isEmpty
    }

    /// The level that comes back when the last holder lets go: the person's own.
    public var levelToRestore: CGFloat? {
        savedLevel
    }

    /// Raises the brightness of `screen` for `holder`. The first holder saves the current level.
    public func raise(for holder: UUID, on screen: any GlowBrightnessAdjustable) {
        if let current = self.screen, current !== screen {
            // A different screen (not possible on iPhone today): give the old one its level back.
            restore()
            holders.removeAll()
        }
        if holders.isEmpty {
            savedLevel = screen.brightness
            self.screen = screen
        }
        holders.insert(holder)
        screen.brightness = max(raisedLevel, savedLevel ?? 0)
    }

    /// Lets go for `holder`. When nobody holds it any more, the saved level comes back.
    public func release(_ holder: UUID) {
        guard holders.remove(holder) != nil else { return }
        if holders.isEmpty {
            restore()
        }
    }

    private func restore() {
        if let screen, let savedLevel {
            screen.brightness = savedLevel
        }
        savedLevel = nil
        screen = nil
    }
}

extension View {
    /// Full brightness while this view is on screen and the app is in front. The person's own level
    /// comes back when the view disappears, the app goes to the background, or Control Center or
    /// a call covers it (it's raised again, from their new level, when they come back).
    public func glowFullBrightness(_ isActive: Bool = true) -> some View {
        modifier(GlowFullBrightnessModifier(isActive: isActive, controller: .shared))
    }
}

struct GlowFullBrightnessModifier: ViewModifier {
    let isActive: Bool
    let controller: GlowBrightness

    @Environment(\.scenePhase) private var scenePhase
    @State private var holder = UUID()
    @State private var isVisible = false
    @State private var screen: UIScreen?

    func body(content: Content) -> some View {
        content
            .background(GlowWindowSceneReader { screen = $0?.screen })
            .onAppear {
                isVisible = true
                update()
            }
            .onDisappear {
                isVisible = false
                update()
            }
            .onChange(of: scenePhase) { update() }
            .onChange(of: isActive) { update() }
            .onChange(of: screen) { update() }
    }

    private func update() {
        if isActive, isVisible, scenePhase == .active, let screen {
            controller.raise(for: holder, on: screen)
        } else {
            controller.release(holder)
        }
    }
}

/// Reports the window scene a view lives in, without `UIApplication.shared` or the deprecated
/// `UIScreen.main`.
struct GlowWindowSceneReader: UIViewRepresentable {
    let onChange: @MainActor (UIWindowScene?) -> Void

    func makeUIView(context _: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: ReaderView, context _: Context) {
        view.onChange = onChange
    }

    final class ReaderView: UIView {
        var onChange: (@MainActor (UIWindowScene?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            let scene = window?.windowScene
            // Report after this layout pass, not during a SwiftUI update.
            Task { @MainActor [onChange] in onChange?(scene) }
        }
    }
}
