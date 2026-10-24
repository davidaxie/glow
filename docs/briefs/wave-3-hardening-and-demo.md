# Wave 3 · Hardening and demo

Five agents. D2 and D3 can start as soon as the first TestFlight build exists.

## D1 · Integration and end-to-end tests

**Mission.** Prove the whole loop works, every time.

**Read first.** In the Technical spec: Product flow, Simulator workflow, Testing and definition of done. Every Wave 1 and Wave 2 hand-off note.

**You own.** `ios/GlowUITests/` and `scripts/e2e/`. You may make small fixes anywhere through PRs labeled `integration`, as long as you tell the owner in `docs/HANDOFFS.md`.

**Build.**

1. `scripts/e2e/player-b.ts`, which plays person B through the API: test sign-in, join, check in, tap, choose, we met.
2. XCUITest journeys on Glow A, with B played by that script: the full loop to We met, the chat path, the block path, and check-in expiry.
3. A two-Simulator script that runs both apps side by side for recordings.
4. All of it running in CI on every merge to main.

**Done when.**

- [ ] The full loop passes 10 runs in a row in CI
- [ ] No flaky tests
- [ ] A recording of the two-Simulator run is in `docs/shots/`

**Hand off.** How to run any journey locally with one command.

## D2 · Security and privacy red team

**Mission.** Try to break every privacy invariant, then fix or file what you find.

**Read first.** Build plan: Privacy invariants. The whole Technical spec.

**You own.** `docs/SECURITY_REVIEW.md` and `server/tests/security/`. Fixes go through PRs to each owner.

**Build.**

1. An automated test for every privacy invariant, running in CI.
2. Work through this attack list:
   - guess or reuse card image links
   - look for any user ID or name in responses before a match
   - join another person's Realtime channel
   - read storage directly with the anon key
   - send fake coordinates (write down what's left of this risk)
   - send parallel requests to get past the tap and view caps
   - look for timing differences that reveal a one-sided tap
   - find out whether an email has an account through sign-in
   - inject text through names and messages
   - find the test sign-in in a Release build
   - find the service role key in the app or admin bundle
   - find coordinates or message bodies in logs, Sentry or PostHog
3. Run a proxy (Proxyman or mitmproxy) on the Simulator during D1's end-to-end run, and check every response.

**Done when.**

- [ ] The report lists every finding with a severity
- [ ] Every high and critical finding is fixed and retested

**Hand off.** The report, linked from `docs/HANDOFFS.md` for Checkpoint 4.

## D3 · Device QA and performance

**Mission.** Make sure Glow works on real iPhones, in a real, crowded venue.

**Read first.** In the Technical spec: Simulator workflow (what it can't test), Private images on device, Location check. C3's hand-off notes.

**You own.** `docs/DEVICE_QA.md`. Performance fixes go through PRs to each owner.

**Build.**

1. A device matrix: the newest iPhone, the oldest iPhone that runs iOS 17, a small-screen iPhone, and the current and previous iOS versions.
2. On each device, check: installing from TestFlight, sign-in, camera and blur speed (under 1 second), QR scanning in dim light, location inside the venue, push while locked, the Live Activity, haptics, glow visibility in a bright hall, and battery use over an hour in a room.
3. Instruments: launch time, memory during camera and blur, and energy during glow.

**Done when.**

- [ ] The matrix is filled in, and every blocker is fixed
- [ ] Cold launch takes under 1.5 seconds on the oldest device

**Hand off.** The matrix, linked from `docs/HANDOFFS.md` for Checkpoint 4.

## D4 · Accessibility, copy and motion

**Mission.** Make every screen kind, clear and usable by everyone.

**Read first.** In the Technical spec: Design system (voice and flash safety). Every module's list of strings from its hand-off notes.

**You own.** The string catalogs (`Localizable.xcstrings`) in every module. Accessibility fixes go through PRs to each owner.

**Build.**

1. VoiceOver labels, order and hints on every screen, and the full journey done with VoiceOver.
2. Dynamic Type up to the largest accessibility sizes, with nothing cut off.
3. Reduce Motion and Reduce Transparency respected everywhere.
4. A copy pass against the voice table: warm, calm, never pushy. Rewrite every error message.
5. A flash safety check on the glow.

**Done when.**

- [ ] The full journey works with VoiceOver on a real iPhone
- [ ] The Accessibility Inspector audit is clean
- [ ] You've signed off on the copy

**Hand off.** A short list of any accessibility gaps left, with owners.

## D5 · Demo and launch kit

**Mission.** Make the demo impossible to break, and fill the room with real people.

**Read first.** Build plan: Human checkpoints and Realistic risks. B7's and B9's hand-off notes.

**You own.** `docs/DEMO.md`, `scripts/seed-demo.ts`, and the demo room's content in the admin web.

**Build.**

1. The real Cal Hacks room: an accurate center and radius, and meeting spots people will recognize. Print posters with the TestFlight link, and put the rotating QR code on a laptop at your table.
2. Demo mode turned on, with the two stage phones signed in as admins.
3. A 3-minute demo script with timings, plus a recorded backup video of the full loop.
4. The live metrics page, ready to show on stage.
5. A plan to get the first 50 people in: posters by the food line, a message in the hackathon Discord, and visits to nearby teams.
6. Pitch points, including the privacy story and the Lovegety line, and a Devpost draft.

**Done when.**

- [ ] Two full dry runs on real phones, on venue Wi-Fi
- [ ] The backup video is recorded
- [ ] The Devpost draft is ready

**Hand off.** `docs/DEMO.md`, with the script, the timings and the fallback plan.
