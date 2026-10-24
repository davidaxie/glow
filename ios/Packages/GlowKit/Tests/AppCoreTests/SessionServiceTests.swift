import APIClient
import Testing
@testable import AppCore

// Owner: B1. The session contract every module codes against.
struct SessionServiceTests {
    @Test(arguments: zip(
        [Components.Schemas.OnboardingStep.profile, .photos, .notifications, .complete],
        [SessionState.onboarding(.profile), .onboarding(.photos), .onboarding(.notifications), .ready],
    ))
    func serverStepMapsToState(step: Components.Schemas.OnboardingStep, state: SessionState) {
        #expect(SessionState(serverStep: step) == state)
    }

    @Test func onlyACompleteProfileIsReady() {
        let states = Components.Schemas.OnboardingStep.allCases.map(SessionState.init(serverStep:))
        #expect(states.filter(\.isReady).count == 1)
    }

    @Test func previewSessionFollowsAppliedProfile() async {
        let session = PreviewSessionService(state: .onboarding(.profile))
        var states = session.states().makeAsyncIterator()
        #expect(await states.next() == .onboarding(.profile))

        await session.apply(.preview(step: .photos))
        #expect(await states.next() == .onboarding(.photos))
        #expect(await session.currentProfile()?.onboardingStep == .photos)

        await session.apply(.preview(step: .complete))
        #expect(await states.next() == .ready)
    }

    @Test func signingOutForgetsTheProfile() async {
        let session = PreviewSessionService(state: .ready)
        #expect(await session.currentProfile() != nil)
        await session.signOut()
        #expect(await session.currentProfile() == nil)
        #expect(await session.currentUserID() == nil)
    }

    @Test func signedOutPreviewHasNoProfile() async {
        let session = PreviewSessionService(state: .signedOut)
        #expect(await session.currentProfile() == nil)
    }
}
