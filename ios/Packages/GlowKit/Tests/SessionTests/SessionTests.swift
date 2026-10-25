import APIClient
import AppCore
import Foundation
import Testing
@testable import Session

struct SignInInputTests {
    @Test(arguments: ["robin@example.com", "  Robin@Example.COM ", "a.b+c@sub.example.co.uk"])
    func acceptsEmails(_ raw: String) {
        #expect(SignInInput.email(raw) == raw.trimmingCharacters(in: .whitespaces).lowercased())
    }

    @Test(arguments: ["", "robin", "robin@", "@example.com", "robin@example", "robin example@x.com"])
    func refusesNonEmails(_ raw: String) {
        #expect(SignInInput.email(raw) == nil)
    }

    @Test func codesAreExactlySixDigits() {
        #expect(SignInInput.code("123456") == "123456")
        #expect(SignInInput.code("123 456") == "123456")
        #expect(SignInInput.code("12345") == nil)
        #expect(SignInInput.code("1234567") == nil)
        #expect(SignInInput.code("12345a") == nil)
        #expect(SignInInput.code("١٢٣٤٥٦") == nil) // non-ASCII digits
    }

    @Test func appleNonceHashIsTheSHA256OfTheRawValue() {
        let nonce = AppleSignInNonce(raw: "abc")
        #expect(nonce.hashed == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let fresh = AppleSignInNonce.make()
        #expect(fresh.raw.count >= 43)
        #expect(fresh != AppleSignInNonce.make())
    }
}

struct LiveSessionServiceTests {
    private func makeSession(
        backend: FakeAuthBackend,
        recorder: APIRecorder,
        memory: StepMemory = TestData.memory(),
    ) -> LiveSessionService {
        LiveSessionService(
            backend: backend,
            config: .preview,
            analytics: NoopAnalytics(),
            api: recorder.api,
            memory: memory,
            restore: false,
        )
    }

    @Test func nobodySavedMeansSignedOut() async {
        let session = makeSession(backend: FakeAuthBackend(), recorder: APIRecorder())
        await session.restore()
        var states = session.states().makeAsyncIterator()
        #expect(await states.next() == .signedOut)
        #expect(await session.currentProfile() == nil)
    }

    @Test(arguments: [
        Components.Schemas.OnboardingStep.profile, .photos, .notifications, .complete,
    ])
    func aSavedSessionResumesAtTheServersStep(_ step: Components.Schemas.OnboardingStep) async {
        let recorder = APIRecorder(["getMe": TestData.json(TestData.me(step))])
        let session = makeSession(backend: FakeAuthBackend(signedInAs: TestData.userID), recorder: recorder)
        await session.restore()
        var states = session.states().makeAsyncIterator()
        #expect(await states.next() == SessionState(serverStep: step))
        #expect(await session.currentProfile()?.onboardingStep == step)
    }

    @Test func a401SignsOutAtOnce() async {
        let backend = FakeAuthBackend(signedInAs: TestData.userID)
        let session = makeSession(backend: backend, recorder: APIRecorder(["getMe": .status(.unauthorized)]))
        await session.restore()
        var states = session.states().makeAsyncIterator()
        #expect(await states.next() == .signedOut)
        #expect(backend.calls.contains("signOut"))
    }

    @Test func offlineFallsBackToTheLastStepSeen() async {
        let memory = TestData.memory()
        memory.remember(.complete)
        defer { memory.forget() }
        // 501 is what the mock answers by default: the profile can't load.
        let session = makeSession(backend: FakeAuthBackend(signedInAs: TestData.userID), recorder: APIRecorder(), memory: memory)
        await session.restore()
        var states = session.states().makeAsyncIterator()
        #expect(await states.next() == .ready)
        #expect(await session.currentProfile() == nil)
    }

    @Test func theEmailCodeSignsInAndLoadsTheProfile() async throws {
        let backend = FakeAuthBackend()
        let recorder = APIRecorder(["getMe": TestData.json(TestData.me(.profile))])
        let session = makeSession(backend: backend, recorder: recorder)
        try await session.sendEmailCode(to: " Robin@Example.com ")
        try await session.verifyEmailCode("123 456", email: "robin@example.com")
        #expect(backend.calls == ["send:robin@example.com", "verify:123456:robin@example.com"])
        var states = session.states().makeAsyncIterator()
        #expect(await states.next() == .onboarding(.profile))
        #expect(await session.currentUserID() == TestData.userID)
        #expect(recorder.operations == ["getMe"])
    }

    @Test func badInputNeverReachesSupabase() async {
        let backend = FakeAuthBackend()
        let session = makeSession(backend: backend, recorder: APIRecorder())
        await #expect(throws: SessionError.invalidEmail) { try await session.sendEmailCode(to: "robin") }
        await #expect(throws: SessionError.invalidCode) {
            try await session.verifyEmailCode("12", email: "robin@example.com")
        }
        #expect(backend.calls.isEmpty)
    }

    @Test func supabaseErrorsComeThroughAsSessionErrors() async {
        let backend = FakeAuthBackend()
        backend.failNext(.invalidCode)
        let session = makeSession(backend: backend, recorder: APIRecorder())
        await #expect(throws: SessionError.invalidCode) {
            try await session.verifyEmailCode("123456", email: "robin@example.com")
        }
        #expect(await session.currentUserID() == nil)
    }

    @Test func aProfileForSomeoneElseIsIgnored() async {
        let session = makeSession(backend: FakeAuthBackend(signedInAs: TestData.userID), recorder: APIRecorder())
        await session.apply(TestData.me(.complete, id: "7e570000-0000-4000-8000-00000000dead"))
        #expect(await session.currentProfile() == nil)
    }

    @Test func signingOutForgetsEverything() async {
        let memory = TestData.memory()
        let backend = FakeAuthBackend(signedInAs: TestData.userID)
        let session = makeSession(
            backend: backend,
            recorder: APIRecorder(["getMe": TestData.json(TestData.me(.complete))]),
            memory: memory,
        )
        await session.restore()
        #expect(memory.lastState == .ready)
        await session.signOut()
        #expect(await session.currentProfile() == nil)
        #expect(await session.currentUserID() == nil)
        #expect(memory.lastState == nil)
        var states = session.states().makeAsyncIterator()
        #expect(await states.next() == .signedOut)
    }

    @Test func aSessionEndedBySupabaseSignsOut() async {
        let backend = FakeAuthBackend(signedInAs: TestData.userID)
        let session = makeSession(backend: backend, recorder: APIRecorder(["getMe": TestData.json(TestData.me(.complete))]))
        await session.restore()
        backend.endSessionRemotely()
        let signedOut = await eventually { await session.currentProfile() == nil }
        #expect(signedOut)
    }

    @Test func theAPIGetsTheSessionsTokenOnly() async throws {
        let backend = FakeAuthBackend(signedInAs: TestData.userID)
        #expect(try await BackendTokens(backend: backend).currentAccessToken() == "token-for-\(TestData.userID)")
        await backend.signOut()
        #expect(try await BackendTokens(backend: backend).currentAccessToken() == nil)
    }

    @Test func anUnconfiguredBuildIsSignedOutAndSaysSo() async {
        let session = LiveSessionService(backend: UnconfiguredBackend(), config: .preview, analytics: NoopAnalytics(), restore: false)
        await session.restore()
        var states = session.states().makeAsyncIterator()
        #expect(await states.next() == .signedOut)
        await #expect(throws: SessionError.notConfigured) {
            try await session.verifyEmailCode("123456", email: "robin@example.com")
        }
    }

    @Test func supabaseErrorMapping() {
        #expect(SupabaseAuthBackend.map(URLError(.notConnectedToInternet), invalid: .invalidCode) == .offline)
        #expect(SupabaseAuthBackend.map(URLError(.badServerResponse), invalid: .invalidCode) == .unexpected)
        #expect(SupabaseAuthBackend.map(CancellationError(), invalid: .invalidCode) == .unexpected)
    }
}

struct StepMemoryTests {
    @Test func remembersOnlyTheStep() {
        let memory = TestData.memory()
        defer { memory.forget() }
        #expect(memory.lastState == nil)
        memory.remember(.photos)
        #expect(memory.lastState == .onboarding(.photos))
        #expect(UserDefaults.standard.string(forKey: memory.key) == "photos")
        memory.forget()
        #expect(memory.lastState == nil)
    }
}
