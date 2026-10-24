# Glow Build Plan

Oct 23, 2026 · @David

Glow ships as a native iPhone app, built by 24 agents in five waves, with four checkpoints where you and Robin decide whether to go on. Every iOS agent builds and tests in the iOS Simulator first, then on real iPhones through TestFlight. This tab is how to run the build. Technical spec is what every agent builds against, and Agent briefs holds the brief to paste into each agent.

## How to run this build

Set up Apple first, because Apple is the slowest part of the whole build.

1. **Apple account.** Confirm you have a paid Apple Developer Program membership. Free accounts can't use push notifications. In App Store Connect, create the app and an App Store Connect API key for uploads.
2. **Other accounts.** A GitHub repo named `glow`, plus Supabase, Vercel, Anthropic API, Upstash Redis, PostHog and Sentry. Keep every key in one password manager vault and in Vercel's environment settings.
3. **A Mac for every iOS agent.** The iOS Simulator only runs on macOS with the latest Xcode. Server-only agents can run anywhere.
4. **Export the spec.** Export the Technical spec tab as Markdown. Agent A1 commits it as `docs/SPEC.md`.
5. **Wave 0.** Launch A1, A2 and A3 in parallel. Give each one the Kickoff prompt plus its brief.
6. **Checkpoint 1**, then launch all nine Wave 1 agents in parallel. A1 stays on as Integrator for the whole build.
7. **Checkpoint 2**, then Wave 2. D2 (security) and D3 (device QA) can start early, on the first TestFlight build.
8. **Checkpoint 3**, then the rest of Wave 3, then **Checkpoint 4** before the demo.
9. **Wave 4** only if Waves 1 to 3 are green and someone is free.

B9 sends the first build to Apple for TestFlight review as soon as sign-in and room joining work. That way Apple's review runs while everyone else keeps building.

## Waves at a glance

&#91;embedded content: build roadmap · 24 agents, 5 waves, 4 checkpoints\]

Each wave starts only after you pass the checkpoint above it. Wave 4 is dashed because it's optional and needs real iPhones.

## Human checkpoints

Each wave starts only after you pass the checkpoint before it. Each one takes about 30 minutes.

| Checkpoint | After | What you check | Pass means |
| --- | --- | --- | --- |
| 1. Contracts | Wave 0 | Read the schema, `contracts/openapi.yaml` and the privacy invariants. Launch the empty app in the Simulator. | You'd be happy if every agent built exactly this |
| 2. Two-Simulator smoke test | Wave 1 | On Glow A and Glow B: sign in, join a room, check in, see each other's card, tap, and both get the mutual notification | The core plumbing works end to end |
| 3. Venue test | Wave 2 | You and Robin on two real iPhones from TestFlight, on the venue floor: the full loop, including glow and chat | It feels good, not just that it works |
| 4. Go or no-go | Wave 3 | The security report has no open high-severity findings, device QA is green, and the demo has had two dry runs | Ship the demo |

## Rules every agent follows

A1 copies these into `AGENTS.md` word for word.

- **Read first.** In order: `AGENTS.md`, `docs/SPEC.md`, `contracts/`, `docs/HANDOFFS.md`, then your brief.
- **Branches.** Use `w{wave}/{agent id}-{short name}`, for example `w1/b3-checkin`. Open a draft PR in your first hour and push often.
- **Ownership.** Edit only the paths you own. If you need something elsewhere, add a request under the owner's ID in `docs/HANDOFFS.md`, or open a tiny PR labeled `cross-owner` and tag the owner.
- **Contracts are law.** Change `contracts/` only in a PR labeled `contract-change` that updates `openapi.yaml`, regenerates both clients and updates the spec. A1 approves.
- **Migrations.** Never edit a merged migration. Add a new one named `NNNN_{agent id}_{what}.sql`.
- **Xcode project.** Never hand-edit the `.xcodeproj`. Change `ios/project.yml` and run `xcodegen`.
- **Mocks.** If something you depend on isn't merged, mock it using the generated contract types. On iOS, that's a protocol plus a mock in your module. On the server, a stub module.
- **Secrets.** None in code. Server secrets come from `server/src/env.ts`. The app only ever holds the Supabase anon key and the API URL.
- **Analytics and errors.** A1 sets up Sentry on the server. A3 sets up Sentry and PostHog in the app behind an Analytics protocol in AppCore. Each feature logs its own key moments through that protocol, never with names, photos, coordinates or message text.
- **Proof.** Every PR passes build, lint and tests in CI. iOS UI PRs include Simulator screenshots of every new screen and a short screen recording.
- **Unclear spec.** Pick the option that protects privacy more, write it in `docs/DECISIONS.md`, and keep going.
- **Done.** Every box under Done when is true, and `docs/HANDOFFS.md` says what you built, what's still mocked and what the next wave needs.

## Privacy invariants

No agent may weaken these to save time. Each one has an automated test and an owner, and D2 tries to break all of them in Wave 3.

| ID | Rule | How it's tested | Owner |
| --- | --- | --- | --- |
| P1 | Before a mutual match, nothing the app receives (API, realtime or push) contains another user's ID, name or face photo. | Contract tests on every endpoint, plus a proxy scan of all traffic during the end-to-end run | A2, D2 |
| P2 | User coordinates are never stored or logged. Only pass or fail is kept. | Logger spy tests on the join route, plus a database column audit | B2 |
| P3 | Only face-blurred card photos leave the phone. | Unit test on the upload payload, plus the end-to-end traffic check | B3 |
| P4 | Every image is checked per request. There are no public storage links. | Storage read with the anon key fails; expired signed links fail | B3, D2 |
| P5 | One-sided taps are never revealed by any response, count or event. | Contract tests | B4 |
| P6 | Lock screen text never includes a name. | Snapshot tests of every push payload | B5 |
| P7 | Blocks apply both ways, everywhere, within 5 seconds. | Database tests plus end to end | B8 |
| P8 | Paused or departed people leave every deck within 5 seconds. | End to end | B8, C1 |
| P9 | Card photos and check-ins are deleted within 10 minutes of expiring. | Cron test | B8 |
| P10 | Nobody under 18 can finish onboarding. | Unit test plus UI test | B1 |
| P11 | Asking for something you're not allowed to see returns 404, never 403, so its existence never leaks. | Contract tests | Every API owner |
| P12 | The deck blurs while the screen is recorded or mirrored, and screenshots of it are logged. | UI test with screen capture faked | C1 |

## Kickoff prompt

Paste this into every agent, fill in the three placeholders, then paste the agent's brief at the bottom.

```
You are agent {ID}, {NAME}, on the Glow build. Glow is a native iPhone app that lets two people in the same room find out, privately, that they noticed each other.

Read these before writing any code, in this order:
1. AGENTS.md
2. docs/SPEC.md
3. contracts/openapi.yaml, contracts/events.json and contracts/constants.json
4. docs/HANDOFFS.md
5. Your brief, pasted below

How you work:
- Edit only the paths your brief says you own. Requests for anything else go in docs/HANDOFFS.md.
- The privacy invariants in AGENTS.md come before speed, every time.
- If something you depend on isn't merged yet, mock it with the generated contract types.
- Work on branch {BRANCH}. Open a draft PR within your first hour and keep pushing.
- For iOS work, build and run in the iOS Simulator with scripts/sim.sh, and attach screenshots to your PR.
- If the spec is unclear, choose the option that protects users' privacy more, note it in docs/DECISIONS.md, and keep going.
- You're done only when every box under Done when is true, CI is green, and docs/HANDOFFS.md is updated.

BRIEF
{paste the brief from the agent's wave tab}
```

## Merge order and integration

A1 is the Integrator for the whole build. A1 reviews every PR against `AGENTS.md`, merges it, keeps main green, and regenerates both clients after any contract change.

- **Wave 1 order.** B6 design system first, then B5 push and realtime, B8 safety, B2 rooms, B3 check-in, B4 deck, B1 onboarding and B7 admin. B9 release merges whenever it's ready. Shared building blocks land first, so feature PRs rebase onto them.
- **Breaking main.** A PR that breaks main gets reverted first and fixed second.
- **End of each wave.** A1 tags main (for example `wave-1-done`), ships a TestFlight build through B9's pipeline, and posts the build number in `docs/HANDOFFS.md`.

## Realistic risks

| Risk | Why it matters | Plan |
| --- | --- | --- |
| No paid Apple Developer account yet | Free accounts can't use push or TestFlight, and apps installed from Xcode stop opening after 7 days ([Flavio Copes](https://flaviocopes.com/apple-developer-free-vs-paid/)) | Check tonight. Until it's active, build against the Simulator using email codes and simulated pushes. |
| TestFlight review for attendees | Up to 100 internal testers need no review, but external testers (up to 10,000, through a public link) wait for Apple to review the first build ([Apple](https://developer.apple.com/help/app-store-connect/test-a-beta-version/overview-of-testflight/)) | B9 submits as early as possible. Until it's approved, the demo runs on your phones as internal testers. |
| No camera, Bluetooth or Ultra Wideband in the Simulator | Some features can only be tested on a real iPhone | Fixture photos and the photo picker in Debug builds. Camera, haptics, glow brightness and Wave 4 get tested on devices at Checkpoint 3. |
| 24 agents in one repo | Merge conflicts and drift between agents | Strict ownership, generated clients, XcodeGen instead of a shared project file, and one Integrator |
| Venue Wi-Fi and indoor GPS | Indoor location is fuzzy and Wi-Fi can be flaky | A 200 m room radius, an admin-only demo mode for the two stage phones, and a recorded backup video |
