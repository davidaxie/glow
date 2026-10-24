import AppCore
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

/// Rooms, Matches and Settings, each with its own navigation stack.
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

            NavigationStack(path: $router.settingsPath) {
                SettingsView().routeDestinations()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
    }
}

private struct LaunchView: View {
    var body: some View {
        Color("LaunchBackground")
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

extension View {
    fileprivate func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { RouteDestination(route: $0) }
    }
}
