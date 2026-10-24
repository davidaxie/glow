import SwiftUI
import UIKit

// Owner: B6. Keeps the screen from locking while a glow is showing, and puts things back after.
//
//     GlowView(…).glowKeepAwake()               // GlowSurface already does this

/// Anything with an idle timer switch, like `UIApplication`. A protocol so tests can use a fake.
@MainActor
public protocol GlowIdleTimerControlling: AnyObject {
    var isIdleTimerDisabled: Bool { get set }
}

extension UIApplication: GlowIdleTimerControlling {}

/// Turns the idle timer off while at least one holder wants it, and restores the value from before
/// the first holder (so it never turns off a keep-awake something else in the app asked for).
@MainActor
public final class GlowKeepAwake {
    private let target: any GlowIdleTimerControlling
    private var holders: Set<UUID> = []
    /// The idle timer setting from before the first holder.
    private var savedValue = false

    public init(target: any GlowIdleTimerControlling) {
        self.target = target
    }

    /// Whether anything is keeping the screen awake.
    public var isHolding: Bool {
        !holders.isEmpty
    }

    public func hold(_ holder: UUID) {
        if holders.isEmpty {
            savedValue = target.isIdleTimerDisabled
        }
        holders.insert(holder)
        target.isIdleTimerDisabled = true
    }

    public func release(_ holder: UUID) {
        guard holders.remove(holder) != nil else { return }
        if holders.isEmpty {
            target.isIdleTimerDisabled = savedValue
        }
    }
}

@available(iOSApplicationExtension, unavailable)
extension GlowKeepAwake {
    /// The app-wide instance the view modifier uses. Apps only: extensions have no idle timer.
    public static let shared = GlowKeepAwake(target: UIApplication.shared)
}

@available(iOSApplicationExtension, unavailable)
extension View {
    /// Keeps the screen awake while this view is on screen and the app is in front.
    public func glowKeepAwake(_ isActive: Bool = true) -> some View {
        modifier(GlowKeepAwakeModifier(isActive: isActive, controller: .shared))
    }
}

struct GlowKeepAwakeModifier: ViewModifier {
    let isActive: Bool
    let controller: GlowKeepAwake

    @Environment(\.scenePhase) private var scenePhase
    @State private var holder = UUID()
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
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
    }

    private func update() {
        if isActive, isVisible, scenePhase == .active {
            controller.hold(holder)
        } else {
            controller.release(holder)
        }
    }
}
