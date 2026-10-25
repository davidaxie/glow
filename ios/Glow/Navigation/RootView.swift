import AppCore
import DesignSystem
import FeatureBlind
import FeatureMatch
import FeatureOnboarding
import FeatureRooms
import FeatureSettings
import SwiftUI

/// Moves between launching, onboarding and the tabs by following the session, presents every
/// Route the Router holds, and hands incoming links to the Router.
struct RootView: View {
    @Bindable var router: Router
    @Environment(\.dependencies) private var dependencies

    var body: some View {
        content
            .preferredColorScheme(.dark)
            .opensMutualMoments() // FeatureMatch (C2): match.created opens the takeover from anywhere
            .fullScreenCover(item: $router.cover) { route in
                RouteDestination(route: route)
                    .sheet(item: $router.sheet) { RouteDestination(route: $0) }
            }
            .sheet(item: sheetWithoutCover) { RouteDestination(route: $0) }
            .environment(\.navigate, NavigateAction { router.go($0) })
            .onOpenURL { router.open($0) }
            .task {
                for await state in dependencies.session.states() {
                    router.apply(state)
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch router.phase {
        case .launching:
            LaunchView()
        case let .onboarding(step):
            OnboardingFlowView(step: step)
        case .main:
            MainTabs(router: router)
        }
    }

    /// A sheet opened during a full-screen takeover is presented from the takeover instead.
    private var sheetWithoutCover: Binding<Route?> {
        Binding(
            get: { router.cover == nil ? router.sheet : nil },
            set: {
                if router.cover == nil {
                    router.sheet = $0
                }
            },
        )
    }
}

/// Rooms, Matches, Blind and Settings, each with its own navigation stack.
private struct MainTabs: View {
    @Bindable var router: Router

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.roomsPath) {
                RoomsHomeView().routeDestinations()
            }
            .tabItem { Label("Rooms", systemImage: "qrcode.viewfinder") }
            .tag(AppTab.rooms)

            NavigationStack(path: $router.matchesPath) {
                MatchesListView().routeDestinations()
            }
            .tabItem { Label("Matches", systemImage: "sparkles") }
            .tag(AppTab.matches)

            NavigationStack(path: $router.blindPath) {
                BlindHomeView().routeDestinations()
            }
            .tabItem { Label("Blind", systemImage: "eye.slash") }
            .tag(AppTab.blind)

            NavigationStack(path: $router.settingsPath) {
                SettingsView().routeDestinations()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
        // U1 (design wave): the accent is the one light in the tab bar.
        .tint(.glowAccent)
    }
}

/// While the session resolves: the launch color, then the canvas with a breathing light, so the
/// first frame after the launch screen is already warm.
private struct LaunchView: View {
    var body: some View {
        ZStack {
            Color("LaunchBackground")
            GlowBreathingLight()
        }
        .glowCanvas()
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Every tab's navigation stack on the canvas instead of plain system black (iOS 18 and later;
    /// iOS 17 keeps each screen's own background).
    @ViewBuilder private func glowTabCanvas() -> some View {
        if #available(iOS 18.0, *) {
            containerBackground(for: .navigation) { GlowCanvasBackground() }
        } else {
            self
        }
    }
}

extension View {
    /// Also puts the stack's root and every pushed screen on the warm canvas (U1).
    fileprivate func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { RouteDestination(route: $0).glowTabCanvas() }
            .glowTabCanvas()
    }
}
