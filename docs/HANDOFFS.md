# Handoffs

What each agent built, what's still mocked, and what the next wave needs. Requests for another agent go under that agent's ID in **Requests**. Each agent keeps its own section under **Status** up to date. Newest notes go at the top of each section.

## Needs David

Things only David can do. None of these block Wave 0 work locally.

**First (from D5, 2026-10-24): confirm the Cal Hacks venue, meeting spots and table location.** The demo room is still a placeholder at the Palace of Fine Arts, San Francisco (37.8029, -122.4484). Send D5 (or edit yourself) the hall's center, a radius that covers it, 3 to 5 meeting spots everyone will recognize, and where the Glow table goes. It's one edit: `VENUE` at the top of `scripts/seed-demo.ts`, then copy the two lines from `scripts/seed-demo.ts --print-venue` into `ios/fixtures/demo-room.env` (D5-D4). D5's other items for David, in order: (a) ask the organizers whether Glow may put up posters, post once in the Discord and have a table; (b) the Apple account and TestFlight (item 11 below), because without the public link attendees can't install Glow; (c) make both stage accounts admins with real profile photos; (d) run the two dry runs on real phones on the venue Wi-Fi from the checklist in [`docs/DEMO.md`](DEMO.md#dry-runs-on-real-phones); (e) check the Lovegety facts in the pitch, and fill in the Devpost draft's brackets (team description, numbers on the day). Nothing has been posted anywhere.

1. **Link Vercel.** Create a Vercel project from `davidaxie/glow` with Root Directory `server` (framework Next.js, Node 24). Then add three GitHub repository secrets: `VERCEL_TOKEN` (a Vercel access token), `VERCEL_ORG_ID` and `VERCEL_PROJECT_ID` (both in the project's `.vercel/project.json` after `vercel link`, or in Project Settings). From then on, every PR gets a preview URL posted on it and main deploys to production. You don't need to connect Vercel's Git integration: `server/vercel.json` turns its auto-deploys off, and the workflow deploys instead.
2. **Add the Vercel env vars**, per D1 in `docs/DECISIONS.md`. Preview and production both need `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (from the Supabase cloud project), `JOIN_TICKET_SECRET`, `CARD_URL_SECRET`, `CRON_SECRET` (each from `openssl rand -base64 32`, all different, different per environment), `ANTHROPIC_API_KEY`, `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN`. Production also needs `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` and `APNS_BUNDLE_ID` (B9 makes the .p8 key). `SENTRY_DSN` and `POSTHOG_KEY` are optional. Never set `ALLOW_TEST_LOGIN` on Vercel; the server refuses to start if you do.
3. **Vercel plan for the purge cron.** P9 needs `GET /api/cron/purge` every 5 minutes. Vercel's Hobby plan only runs crons once a day, so the project needs Pro (or B8 needs an outside scheduler that sends `Authorization: Bearer $CRON_SECRET`).
4. **Branch protection on main** (optional, recommended): require the `Ubuntu · server and database` and `macOS · iOS build and tests` checks before merging. A1 didn't change repo settings.
5. **Cloud accounts** from Build plan step 2 (Supabase cloud, Upstash, Anthropic, PostHog, Sentry, Apple Developer). None exist yet; local development doesn't need them.
6. **Confirm the venue** (from A2). The seeded `demo` room sits at a placeholder: the Palace of Fine Arts, San Francisco (37.8029, -122.4484). That's fine for the Simulator. The real event room gets made in B7's admin web with the real center, so this only matters if you want `sim.sh at venue` to match the real hall (D11).
7. **When the Supabase cloud project exists** (from A2): run the migrations with `supabase db push`, and in the dashboard under Realtime settings turn off "Allow public access", so only private channels work (D27). Don't load `seed.sql` there; it's local test data.
8. **Disk space and the Sentry iOS SDK** (from A3). This Mac had under 3 GB free during Wave 0 (`df -h /`), and a build failed with "No space left on device". The Sentry iOS SDK alone downloads 3.2 GB of binary frameworks per checkout, so A3 deferred it (D36 in `docs/DECISIONS.md`); PostHog is live and the Sentry adapter is written and switches on when the package is added back. Please free space before Wave 1 (nine iOS worktrees, each with its own build folder of about 2 GB, plus Supabase's Docker images), and decide whether the app gets Sentry now or with B9's release pipeline.
9. **PostHog project setting** (from A3): when the PostHog project exists, turn on "Discard client IP data". The app already disables GeoIP and never identifies anyone (D35).
10. **Web domain** (from A3): when {DOMAIN} is chosen, B9 sets it in one place, `GLOW_WEB_DOMAIN` in `ios/Glow/Config/Shared.xcconfig` (D33).
11. **Apple Developer account and TestFlight** (from B9). Everything is click by click in [`docs/RELEASE.md`](RELEASE.md#apple-setup-for-david); the release pipeline is ready and waits on these, in order:
    1. Join the paid Apple Developer Program; copy the **Team ID** into `DEVELOPMENT_TEAM` in `ios/Glow/Config/Shared.xcconfig` (via A1).
    2. Register bundle IDs `com.davidxie.glow` (capabilities: Associated Domains, Push Notifications, Sign In with Apple, Time Sensitive Notifications) and `com.davidxie.glow.LiveActivity` (none).
    3. Make the APNs key (`.p8`, Sandbox & Production) and put it in Vercel production: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` (the file's contents), `APNS_BUNDLE_ID=com.davidxie.glow`.
    4. Make an **Apple Distribution** certificate in Xcode, and export it as a `.p12` with a password.
    5. Make two **App Store** provisioning profiles, named exactly `Glow App Store` (app) and `Glow Live Activity App Store` (extension).
    6. Create the app record in App Store Connect (bundle ID `com.davidxie.glow`, SKU `glow-ios`).
    7. Make an App Store Connect **API key** with the **App Manager** role.
    8. Add the GitHub secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY`, `DIST_CERT_P12_BASE64`, `DIST_CERT_PASSWORD`, `PROFILE_APP_BASE64`, `PROFILE_LIVE_ACTIVITY_BASE64`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` (the hosted project's), optionally `POSTHOG_KEY`; and for beta review, `GLOW_REVIEW_FIRST_NAME`, `GLOW_REVIEW_LAST_NAME`, `GLOW_REVIEW_EMAIL`, `GLOW_REVIEW_PHONE`, `GLOW_FEEDBACK_EMAIL`.
    9. Run `ios/fastlane/ship release`, then make the internal group **Glow team** (automatic distribution on) with you, Robin (an App Store Connect user with the Developer role) and the two stage phones. Install from TestFlight, and check push between two iPhones.
    10. When sign-in and room joining work on `main`: create the external group **Public**, fill in App Privacy (answers in RELEASE.md) with a privacy policy at `https://{DOMAIN}/privacy`, and run the workflow's **external** lane to submit for beta review.
    11. When it's approved: turn on the **public link**, set it as `TESTFLIGHT_URL` in Vercel, and give it to B7 for the posters.
    12. When the domain exists: set `GLOW_WEB_DOMAIN` (via A1) and `APPLE_APP_ID={TEAM_ID}.com.davidxie.glow` in Vercel, then scan a poster QR with the iPhone Camera and check Glow opens.
12. **GitHub Actions billing** (from B9, 2026-10-24). Since about 18:40 UTC, jobs don't start: "The job was not started because recent account payments have failed or your spending limit needs to be increased" (github.com → Settings → Billing and plans). It hit macOS first (PR #17), then Ubuntu too (PR #5's Release checks, which passed in 13 seconds on an earlier commit). The repo is private, so macOS minutes count ten times; the TestFlight job runs on macOS, so releases need this fixed as well.
13. **Purge every 5 minutes** (from B8, item 3 above). `server/vercel.json` already schedules `/api/cron/purge` at `*/5 * * * *`. On a Pro plan that's all. On Hobby, Vercel may refuse to deploy a schedule that runs more than once a day: change it to `0 0 * * *` and add an outside schedule instead, for example an Upstash QStash schedule (`*/5 * * * *`) that calls `GET https://{DOMAIN}/api/cron/purge` and forwards `Authorization: Bearer <CRON_SECRET>` (QStash's `Upstash-Forward-Authorization` header). The route is safe to be called by both (B8-D8).
14. **Moderation** (from B8). With `ANTHROPIC_API_KEY` set, run `pnpm --filter server exec vitest run tests/moderation/live.test.ts` once: it checks p95 latency under 2.5 s and decides every photo in `server/tests/moderation/fixtures/live/` as its name says (`approve-*.jpg`, `reject-face_visible-*.jpg`, `reject-nudity-*.jpg`, `hold-*.jpg`). No such photos are committed, because they need real people who agreed to be fixtures (or freely licensed ones, D44); please add a few, or decide they stay local. Note the synthetic outfit drawings in `ios/fixtures/photos/` are *rejected* by real Claude as "no person", so Simulator check-ins with a key set need real outfit photos.
15. **Supabase cloud, account deletion** (from B8). After `supabase db push`, check that `select public.purge_auth_audit(interval '7 days')` runs as the service role. It deletes from `auth.audit_log_entries`, which a hosted project may restrict. If it's refused, deletion still works but Auth's audit log keeps emails and IPs: either allow it, or turn off "write auth audit logs to the database" in the project's Auth settings (B8-D4, B8-D5).
16. **Select the full Xcode** (from B6, optional): `xcode-select` points at the Command Line Tools, so Claude Code's built-in iOS Simulator panel refuses to start. `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` fixes it. Agents work around it with `scripts/sim.sh` (which sets `DEVELOPER_DIR` itself), so nothing is blocked.
17. **Haptics and brightness on a real iPhone** (from B6): the Simulator can't play haptics or change brightness. On a device, check the Gallery (Settings > Debug > Gallery): the Haptics buttons, and "Open a live glow", which should go to full brightness, keep the screen awake, and return your own brightness when closed or when you open Control Center.
16. **Admin accounts** (from B7). There's no screen to make someone an admin, on purpose. When the Supabase cloud project exists, each organizer signs up in the app once, then add them in the SQL editor: `insert into public.admins (user_id) select id from auth.users where email = 'organizer@example.com';`. Locally, `admin@glow.test` is already an admin.
17. **Email for admin sign-in codes** (from B7, shared with B1). Admins sign in to the admin web with a 6-digit email code from Supabase Auth. Supabase's built-in email sender is limited to a few emails an hour, which won't survive an event: in the cloud project, set up custom SMTP (Auth, then SMTP settings) with any provider, and make sure the email template includes `{{ .Token }}`.
18. **Print the posters on the day** (from B7). The poster PDF is US Letter, black on white. Print it at 100% (no "fit to page" shrink) so the QR code stays at least 4 inches wide. Posters only let people in while "Printed posters" is on for that room.
16. **Point `xcode-select` at Xcode** (from B3). The Claude Code iOS Simulator tool refuses to run while `xcode-select` points at the Command Line Tools, so agents can't tap through the app with it. Run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` once. Until then agents drive screens with XCUITest and `scripts/sim.sh shot`, which works but is slower.
19. **A real sandbox push** (from B5). The `xcode-select` items above (from B6 and B3) also let agents tap notifications in the Simulator. Once the APNs key from item 11.3 exists, run `server/tests/notify/apns-live.test.ts` once with `APNS_*` and `APNS_TEST_DEVICE_TOKEN` set, to check a real push through Apple's sandbox.
20. **Cloud Auth settings for D2-F1, no password sign-in** (from D2, 2026-10-24; details in [`docs/SECURITY_REVIEW.md`](SECURITY_REVIEW.md#d2-f1)). Migration `0005_d2_no_passwords.sql` refuses every password session. In the Supabase cloud project, under Authentication:
    - **Confirm email must be on** (Providers → Email; it's on by default). With it off, Supabase signs a brand-new email-code person in with a password session, the migration refuses it, and nobody new can sign up.
    - **Secure email change** on. **Email OTP expiration** 600 seconds (it's 3600 by default). **Anonymous sign-ins**, **phone** and **manual identity linking** stay off.
    - Optional: CAPTCHA protection on the Auth endpoints. It makes it harder to check in bulk whether an address has an account (D2-F2).
    - After `supabase db push`, check the trigger exists: `select tgname from pg_trigger where tgname = 'glow_refuse_password_sessions';`. If `db push` stops with "permission denied" on `auth.mfa_amr_claims`, tell D2 or A1. Don't skip the migration.
    - Never run `seed.sql` there. It's the only thing that turns on `allow_test_passwords`.

## Checkpoint 1 · Contracts (after Wave 0)

_Run by the orchestrator, to whom David handed the checkpoint decisions; written up by A1, 2026-10-24. Result: **pass**. Wave 1 started on main at 51c72dd and later._

**What was checked** (Build plan: "Read the schema, `contracts/openapi.yaml` and the privacy invariants. Launch the empty app in the Simulator.")

- **Contract and schema review.** No blockers. Six should-fixes, all landed in A2's `contract-change` PR #14 (migration `0002_a2_checkpoint1.sql`, D46 to D56): `service_role` default privileges for later migrations; a name-free `match.recheck` push when a Find needs a fresh location check; `start_glow` falls back to chat instead of raising; `create_checkin` needs a passed join location check; `POST /api/me/onboarding/complete` and admin review of held profile photos; settled timeouts returned so the calling route sends the events. Also in #14: no tap counts in room metrics, an exact daily tap count (`room_days`), the deck's `emptyReason` after purge, and a codegen check that ties `openapi.yaml` limits to `constants.json`. A1 added 501 stubs for the four new operations and updated `docs/SPEC.md` (endpoints, events, functions, tables) in the same PR.
- **Privacy invariants.** Copied word for word into `AGENTS.md` (a test keeps them in step with the build plan). The server enforces P1 (replies carry only contract fields), P2 (logs and Sentry redact coordinates), P11 (403 becomes 404) in the route helper, and A2's pgTAP suite covers the database side.
- **The empty app.** Verified from A3's Simulator shots and recordings (`docs/shots/launch-rooms-*.png`, `scan-demo-*.png`, `push-match-created-A.png`, `skeleton-scan-and-push-*.mp4`) and by building and testing main locally.

**Main at Checkpoint 1**: tagged `wave-0-done` at e53053a (the #14 merge). Wave 0 merges: #1 cab8f97 (A1 skeleton), #2 e51b0d2 (A2 contracts and database), #3 51c72dd (A3 iPhone skeleton, A3's decisions renumbered to D33–D45), #14 e53053a (Checkpoint 1 fixes), plus A1's integration PRs #4 443bfc0 (parallel agents), #13 cbc563f (generated registry and stubs), #28, #30 and #31.

**CI**: the last fully green GitHub Actions run on main is 40120018085 at 443bfc0. Both jobs ran everything, including codegen staleness, pgTAP (390 tests) and the iOS build and tests; 40118791968 at 51c72dd did the same. GitHub Actions stopped starting jobs at about 18:40 UTC (billing, Needs David 12), so main and PRs are verified with `scripts/ci-local.sh` since: `ci-local A1 53877f0: ubuntu pass, macos pass` for #14.

**Not done at this checkpoint**: no TestFlight build yet (Build plan: end of each wave), because there's no Apple Developer account (Needs David 11). No Vercel preview URL (Needs David 1).
18. **Sign-in on the Supabase cloud project** (from B1). (a) Auth → Email Templates: paste `supabase/templates/magic_link.html` into **Magic Link** and `confirmation.html` into **Confirm signup**, subject "Your Glow code" for both, and keep the email OTP length at 6. Without this, the cloud sends links and the app's code screen can't sign anyone in (B1-D4). (b) Auth → Providers → Apple: turn it on with Client IDs `com.davidxie.glow` (the app's bundle ID; no secret is needed for the native ID-token sign-in) and **Allow users without an email** on, because the app asks Apple for no name and no email (B1-D3). This needs the Apple Developer account (item 11). Until then Sign in with Apple is built but blocked, and the email code is the way in.
19. **The shared local stack's email** (from B1). The shared `glow` stack (54421) still sends sign-in links until it restarts with #11's config. Nobody restarts it mid-wave; when it next restarts (`supabase stop && supabase start` from the main checkout, after #11 merges), codes work there too.

## Requests

### For A1

_From D1, 2026-10-24._ PR [#43](https://github.com/davidaxie/glow/pull/43).

1. **`--e2e` in `scripts/ci-local.sh`, and an e2e job in `ci.yml` for when Actions is back.** The command is `scripts/e2e/run.sh all` (after `scripts/sim.sh build`, with a server that has `ALLOW_TEST_LOGIN`; run.sh starts `pnpm dev` itself if nothing answers on `$GLOW_API`). It takes both of the agent's Simulators only with `--record`. A job would run it on main merges (the brief's "every merge to main"), with `ios/build/results/*.xcresult` and `.agent-state/e2e/` as failure artifacts.
2. **Two cheap checks in the Ubuntu job**, for `scripts/e2e/`: `node --test scripts/e2e/glow.test.ts` (6 tests, under a second) and `(cd server && node_modules/.bin/tsc -p ../scripts/e2e)` (the scripts against the generated contract types). Prettier already covers the folder.
3. **Debug launch routes.** C3's #38 (merged) reads `-GlowDebugRoute glow/<matchID>`; C1's #39 adds `-GlowDebugRoute deck:<roomID>` in another file with another separator. Please settle one format before #39 merges; the journeys use neither.

_From D1, 2026-10-24, `integration` PR (`w3/d1-push-tap-fix`)._ Tapping any notification crashed the app (SIGABRT in UIKit's `_updateSnapshotAndStateRestorationWithAction`): the async form of `userNotificationCenter(_:didReceive:)` in `ios/Glow/AppDelegate.swift` calls UIKit's completion from wherever its task finishes, and UIKit asserts it's on the main thread. It's now the completion-handler form, which routes on the main actor and then calls the completion there. Found by D1's `PushTapUITests` (`scripts/e2e/run.sh push`), which now taps all nine fixtures' banners and checks each opens its screen. B5: your `route(for:)` is unchanged.

_From C3, 2026-10-24._ PR [#27](https://github.com/davidaxie/glow/pull/27).

1. **End finished glows' Live Activities at launch and on foreground.** In `ios/Glow/AppDelegate.swift` (or wherever the app sees `scenePhase` become `.active`), call `Task { await ActivityKitGlowLiveActivities.endFinishedGlows() }` from `FeatureGlow`. It ends only glows whose time has run out or that already show an ending, so a glow that ended while the app slept never lingers on the lock screen (C3-D4). Glows that are still on are left alone.
2. **A Debug-only way to open a match screen in the Simulator**, for proof before push taps and sign-in are live: a `GlowDebugRoute` launch argument next to `GlowDebugOpenURL`, taking `glow/<matchID>` (and `mutual/`, `match/`, `chat/`). C3 sent it as a tiny `cross-owner` PR (linked in C3's status); C2 and C4 can use it too.
_From D5, 2026-10-24, PR #42._ (1) When David confirms the venue, `ios/fixtures/demo-room.env` needs the two lines `scripts/seed-demo.ts --print-venue` prints (`GLOW_DEMO_LAT`, `GLOW_DEMO_LNG`), so `sim.sh at venue` lands in the seeded room; `server/tests/seed-demo` fails until they match. (2) Optional: a root script `"seed:demo": "scripts/seed-demo.ts"` in `package.json`. The file runs directly (its shebang passes `--disable-warning=MODULE_TYPELESS_PACKAGE_JSON`, because the root package has no `"type": "module"`). (3) `server/tests/seed-demo/` is D5's (tests for D5's script, per "Owners put tests in `server/tests/{module}/`").
_From C1, 2026-10-24._ `cross-owner` PR [#39](https://github.com/davidaxie/glow/pull/39), stacked on #25 (merge #25 first): C3's `DebugRoute` (#38) also takes a room's screens, `-GlowDebugRoute deck/<room id>` and `room/<room id>`, with tests in `ios/GlowTests/DebugRouteTests.swift`. C1's P12 and find UI tests need it.

_From B6, 2026-10-24._

1. **DesignSystem strings** (for D4, later): when D4 adds a string catalog to DesignSystem, its target needs `resources: [.process("Resources")]` in `Package.swift`.
_From B3, 2026-10-24._ PR [#7](https://github.com/davidaxie/glow/pull/7).

1. **`Cache-Control` on images.** `server/next.config.ts` adds `Cache-Control: no-store, max-age=0` to every `/api` response, so the image routes go out with that instead of the contract's exact `no-store` (`CacheControlNoStore` is `enum: [no-store]`). Both forbid caching, so nothing leaks; it's only a contract mismatch a strict checker (D2) would flag. Either let the contract's enum allow `no-store, max-age=0`, or skip the header rule for responses that already set one.
2. **Explicit package dependencies.** `Imaging` imports `HTTPTypes` and `OpenAPIRuntime` (for `GlowAPI.send`), and `FeatureCheckIn` imports `OpenAPIRuntime` (for `Base64EncodedData`). They build today through `APIClient`; if you'd like every import declared, add `openAPIRuntime` and `httpTypes` to `core` and `feature` in `Package.swift`.
3. **After check-in.** `CheckInView` sends `.roomHome(roomID)` when the card is made, which pushes on top of `.checkIn`, so Back returns to the finished check-in. Consider a way for a Route to replace the top of the stack (or have the Router drop `.checkIn` when `.roomHome` for the same room is pushed).
4. **Fixture README.** PR #7 corrects one line of `ios/fixtures/faces/README.md` (yours): `faces-group-of-3.jpg` shows 6 faces, two crews of three.
_From C4, 2026-10-24._

1. ~~**SwiftFormat skipped every file in an agent worktree.**~~ Fixed in #30: `.swiftformat` no longer excludes `.claude`, and `sim.sh lint` fails if it checks no files.
2. **When `limitRequest` goes into `route()`** (B8's item 1 below), `sendMessage` would count twice: tell C4, or drop the `rateLimit(senderId, 'messages')` line in `server/src/server/chat/messages.ts` in the same PR (a `cross-owner` edit C4 pre-approves).

_From C2, 2026-10-24._

1. **The mutual takeover from anywhere in the app.** `match.created` reaches whoever didn't make the second tap while they could be on any screen, so the takeover has to be opened from the root. FeatureMatch exports a modifier for it: one line in `ios/Glow/Navigation/RootView.swift`, on `content` inside `body` (after `.preferredColorScheme(.dark)`):

   ```swift
   .opensMutualMoments() // FeatureMatch (C2): match.created opens the takeover from anywhere
   ```

   It listens to `dependencies.realtime` and sends `.mutual(matchID)` through `navigate`. `RootView` already imports FeatureMatch. **Carried in PR #26 as its own `cross-owner` commit** (so the reveal could be tested); keep it, reword it, or drop it and add your own.

_From A2, Checkpoint 1 fixes, 2026-10-24._ `contract-change` PR [#14](https://github.com/davidaxie/glow/pull/14) on `w0/a2-checkpoint1`. It adds migration `0002_a2_checkpoint1.sql` (0001 untouched), D46 to D56, and 53 new pgTAP tests (443 in all).

1. **New operations that need stub routes:**
   - `completeOnboarding` · `POST /api/me/onboarding/complete` → `server/app/api/me/onboarding/complete/route.ts` (B1)
   - `adminListPhotos` · `GET /api/admin/photos` → `server/app/api/admin/photos/route.ts` (B7)
   - `adminPhotoImage` · `GET /api/admin/photos/{id}/image` → `server/app/api/admin/photos/[id]/image/route.ts` (B7, raw JPEG)
   - `adminReviewPhoto` · `POST /api/admin/photos/{id}/review` → `server/app/api/admin/photos/[id]/review/route.ts` (B7)
2. **Event changes:**
   - **New `match.recheck`** (`{ type, matchId }`, `MatchRecheckEvent`): a push with "Open Glow to find each other.", category `MATCH`, time-sensitive. It goes to whoever's location check went stale while both chose Find (D47).
   - **`match.choice`** is now also sent to both people when choosing ends without a glow (a timeout, or `start_glow` answering `chat`).
   - **`glow.ended`** can now also come from the routes that report a `settled` glow expiry, not only purge (D51).
3. **Schema changes:** `RoomMetrics` loses `taps` (D52). New `AdminPhoto`, `AdminPhotoList`, `AdminPhotoReview` and `MatchRecheckEvent`. `GlowEvent` and `GlowEventType` include `match.recheck`. Descriptions changed for `createCheckin`, `getDeck`, `createTap`, `listMatches`, `getMatch`, `setChoice` and `markGlowMet`. Several limits now carry `x-constant`, which `codegen.sh` checks against constants.json (D55).
4. **For `docs/SPEC.md`:**
   - New table `room_days` (today's taps and room visits, D53 and D54).
   - New function `complete_onboarding`.
   - `start_glow` returns `{ result: started | chat | waiting }` instead of raising (D48).
   - `create_checkin` needs a passed join check (D49).
   - `get_match`, `list_matches`, `set_choice`, `start_glow` and `glow_met` report `settled` (D51).
   - `service_role` default privileges for later migrations (D46).
5. **CI:** no new commands. `codegen.sh` also accepts `GLOW_DB_URL` (for example `postgresql://postgres:postgres@127.0.0.1:56422/postgres?sslmode=disable`) to generate `database.ts` from a scratch stack. CI doesn't need it.
6. **Decision numbers:** D46 to D56 follow A3's D45. Renumber at merge if yours collide.

_From B9, 2026-10-24._ PRs [#5](https://github.com/davidaxie/glow/pull/5) (release pipeline) and [#17](https://github.com/davidaxie/glow/pull/17) (`cross-owner`).

1. ~~**Signing in `ios/project.yml`**~~ Merged in #17, thanks: Release device builds of `Glow` and `GlowLiveActivity` sign manually with Apple Distribution and the profiles `Glow App Store` and `Glow Live Activity App Store` (B9-D1). A test in `ios/fastlane/test` checks `project.yml` keeps naming the profiles the Fastfile uses, so keep the two in step if either changes.
2. **`Shared.xcconfig` values, later.** When David has them, `DEVELOPMENT_TEAM` (the Team ID) and `GLOW_WEB_DOMAIN` go in `ios/Glow/Config/Shared.xcconfig`, which is yours now. The release lane refuses to ship while either is empty or the placeholder.
3. **A privacy policy page** at `https://{DOMAIN}/privacy`. App Privacy and external TestFlight testing need a policy URL. A draft in Glow's voice is in `docs/RELEASE.md` ("Privacy policy draft"), with `{CONTACT_EMAIL}` to fill in. The path isn't in the ownership map, so it's yours to place or assign.
4. **Privacy manifest, two candidates to declare** (D43 says more, not less): `NSPrivacyCollectedDataTypeEmailsOrTextMessages` for chat messages (Apple's definition is about message contents; the manifest has them only as Other User Content), and `NSPrivacyCollectedDataTypeDeviceID` for the push token stored with each account. If you add either, run `ios/fastlane/ship privacy_answers`, commit `ios/fastlane/app-privacy.json` and tell B9 to update the table in `docs/RELEASE.md`. CI's **Release iOS → Release checks** job fails while the two disagree.
5. **CI.** `.github/workflows/release-ios.yml` adds one Ubuntu job (**Release checks**, about a minute) on PRs that touch release files: the lane helper tests and `fastlane check`. The macOS TestFlight job only runs on `beta-*` and `wave-*-done` tags or by hand, and skips with a notice until the Apple secrets exist. After you tag `wave-1-done`, the build number shows in that run's summary.

_From B7, 2026-10-24._

1. **The web domain as a server variable.** Poster and display links are built from one constant, `WEB_DOMAIN` in `server/src/server/admin/links.ts` (`glow-domain-not-chosen.invalid`, the same placeholder as `GLOW_WEB_DOMAIN` in the app, D33). A test fails if the two differ. When {DOMAIN} is chosen, please add an optional `WEB_DOMAIN` to `server/src/env.ts` (a bare hostname, default the placeholder, required on Vercel production), and B7 will read it with `getEnv()`.
2. **`authorize` in the route helper:** PR [#29](https://github.com/davidaxie/glow/pull/29) (`cross-owner`) adds `route(id, handler, { authorize })`, run right after sign-in and before the path, query or body is read. Without it, a signed-in non-admin sending a malformed body to `/api/admin/*` got a 400 with field paths instead of the 404 (found with `scripts/smoke.sh` and a throwaway token). B7's PR carries the same commit so its routes can use it; it drops out when #29 merges.
3. **Rate limits in the route helper** (B8's item 1 above) cover `/api/admin/*` with the `admin` policy. The admin web's server actions already call `rateLimit(adminId, 'admin')` themselves, and sign-in steps `signIn` per address and per email.

_From B8, 2026-10-24._

1. **Rate limit every route in the helper.** In `route()` (`server/src/server/http/route.ts`), right after `authenticate`, add `await limitRequest(operationId, req, user)` from `@/server/ratelimit`. It picks the policy per operation (`policyForOperation`, a test covers every operation in the contract), keys by person or by client IP, throws your `rateLimited()` 429, and skips `runPurge`. Then no handler has to remember to call it.
2. ~~**`reason` on errors.**~~ Done in #13. `photoRejected(reason)` is built on `unprocessable`, and `ModerationUnavailableError` passes `reason: 'moderation'`.
3. **`tests/setup.ts`:** please also delete `ANTHROPIC_API_KEY` before each test, so a key exported in someone's shell never makes the suite call the real API (B8's live test reads the key once at import, before setup runs).
4. **Review migration `0003_b8_forget_account.sql`** (PR #22, A2 has finished). Functions only, no tables: `forget_account_traces(p_user_id)` deletes Supabase Auth audit entries (and any stored Realtime message on `user:{id}`) for a person whose auth user is already gone, and refuses anyone who still exists; `purge_auth_audit(p_older_than)` deletes audit entries older than that (at least 1 hour). Both security definer, `search_path = ''`, service role only. `server/src/contracts/database.ts` was regenerated from B8's own stack with the same `supabase gen types` command; the only change is the two functions.
5. **`scripts/codegen.sh` and own stacks** (it's A2's, but A2 has finished). Its `supabase gen types --local` always reads the shared `glow` stack, so an agent with a new migration gets stale types. Please make it pass `--workdir "$GLOW_SUPABASE_WORKDIR"` (to both `supabase status` and `gen types`) when that's set.

_A1's answers, 2026-10-24._ 1: done, `route()` calls `limitRequest(operationId, req, user)` right after sign-in, so every route is limited and a 401 is never counted. 3: done, `tests/setup.ts` deletes `ANTHROPIC_API_KEY` and resets the in-memory store before every test.

_From B2, 2026-10-24._ Branch `w1/b2-rooms`.

_All three answered in A1's #13, thanks._ 1: the ownership row covers `server/app/api/rooms/[id]/route.ts`, and B2 took over the stub. 2: B2 reads `TESTFLIGHT_URL` for the `/r/{slug}` page and `APPLE_APP_ID` for the link file (B2-D3). 3: B2 builds on the generated registry.
_From B4, 2026-10-24._ PR [#9](https://github.com/davidaxie/glow/pull/9).

1. **Integration tests in CI.** B4's integration tests (`server/tests/{deck,taps,matches}/*.integration.test.ts`) run inside `pnpm test` whenever `CI` is set, against the Supabase CI starts, reading keys from the `server/.env.local` that `env-setup.sh --force` writes. They take about 20 seconds, refuse any non-local Supabase, and delete everything they make before pgTAP runs (B4-D6). Nothing to change in `ci.yml` unless you'd rather run them as their own step (`GLOW_INTEGRATION=1 pnpm --filter server exec vitest run tests/deck tests/taps tests/matches`).
2. **A shared service-role client.** `server/src/server/deck/db.ts` has `serviceDb()` and `rpc(fn, args)`, which maps the database's P0001 codes to HTTP errors as CONTRACTS.md describes (404, 400, 409 with the same code, 503 when PostgREST can't reach the database or times out). Other owners will need the same. If you want one in `server/src/server/db/`, B4 is happy to move it there.
3. **Auth on every request (D3) is not the deck's bottleneck.** On B4's own stack with 300 people, Supabase Auth's token check alone is 2 ms p50 (4 ms p95) one at a time and 29 ms p50 (82 ms p95) at 25 in flight, against 20 ms and 97 ms for `get_deck` before B4's tuning. No change proposed; full numbers are in PR #9.
4. ~~**Rate limits.**~~ Done in 33c16c2, thanks: `route()` limits every route, so B4's handlers no longer call `rateLimit` themselves.

_From A2, 2026-10-24._ PR [#2](https://github.com/davidaxie/glow/pull/2).

1. **Wire the generated registry.** `server/src/contracts/operations.ts` exports `operations` (typed `as const satisfies Record<string, OperationDef>`), with the operationIds your stubs already use. In `server/src/server/http/operations.ts`, replace the placeholder import with `import { operations as generated } from '@/contracts/operations';` and `export const operations = generated;`, then delete `contract-placeholder.ts`. I tried exactly that locally: `tsc --noEmit` passes with every existing route. `tests/stubs.test.ts` then wants route files for the operations the placeholder didn't have:
   - `getRoomState` · `GET /api/rooms/{id}` → `server/app/api/rooms/[id]/route.ts` (B2)
   - `getMyPhoto` · `GET /api/me/photos/{id}` → add `GET` to `server/app/api/me/photos/[id]/route.ts` (B1)
   - B7's admin routes under `server/app/api/admin/`: `adminListRooms` and `adminCreateRoom` (`rooms`), `adminGetRoom` and `adminUpdateRoom` (`rooms/[id]`), `adminReplaceSpots` (`rooms/[id]/spots`), `adminRoomPoster` (`rooms/[id]/poster`), `adminDisplayToken` (`rooms/[id]/display-token`), `adminRotateStaticToken` (`rooms/[id]/static-token`), `adminRoomMetrics` (`rooms/[id]/metrics`), `adminListCards` (`rooms/[id]/cards`), `adminCardImage` (`cards/[cardId]/image`), `adminRemoveCard` (`cards/[cardId]/remove`), `adminListReports` (`reports`), `adminResolveReport` (`reports/[id]/resolve`).
   `operationInfo` in the same file names each operation's owner, if you generate stub headers.
2. **CI, Ubuntu job.** Your existing steps work as they are: `supabase start -x studio,imgproxy,edge-runtime,logflare,vector,supavisor,postgres-meta`, then `scripts/codegen.sh` with the `git diff --exit-code` and untracked-files check, then `supabase test db`. Notes:
   - `codegen.sh` needs `swift` on PATH (the ubuntu-24.04 image has it) and the `supabase` CLI (setup-cli puts it there). It also needs the DB running, so `server/src/contracts/database.ts` gets checked too; your step order already does this.
   - The first run builds swift-openapi-generator from source, about 3 to 5 minutes. Please cache it: `actions/cache` on `~/.cache/glow-codegen`, keyed on `hashFiles('scripts/codegen.sh')`.
   - `supabase test db` includes a race test that opens 100 connections. `config.toml` raises `max_connections` to 200 and the test connects with dblink to the container's network address as `postgres`/`postgres`, which works under `supabase start` in CI as it does locally. The whole suite (390 tests) takes about 2 seconds.
   - Optional, macOS job: `scripts/codegen.sh --verify` also compiles the Swift client on its own against swift-openapi-runtime and fails on any warning.
3. **Error shape.** I used yours: `{ error: { code, message, issues? } }` plus an optional `reason` (for example `photo_rejected` + `face_visible`, `unavailable` + `moderation`). Your base codes are all in `ErrorCode`, plus specific ones routes need: 409 `onboarding_incomplete`, `room_not_live`, `tap_limit_reached`, `chat_not_open`, `last_photo`, `slug_taken`, and **422** `under_18`, `not_in_room`, `location_inaccurate`, `location_required`, `join_ticket_invalid`, `photo_rejected`, `message_rejected`. A 422 isn't in your list yet; `new HttpError(422, 'not_in_room', ...)` already works with your class. Maybe add small helpers.
4. **Auth.** As you listed. `GET /api/cards/{cardId}/image` stays Bearer plus signed link: the signature covers `{cardId}.{viewerId}.{exp}` with the viewer taken from the token, so the link carries no user ID (`docs/CONTRACTS.md`).
5. **Times.** The generated zod schemas use `z.iso.datetime()`, which rejects offsets like `+00:00`. The database functions already return `...000Z`, but rows read straight from tables through supabase-js come back as `+00:00` and need `new Date(x).toISOString()`. Worth a line in "Writing a server route" in AGENTS.md.
6. **docs/SPEC.md** (yours) needs these after Checkpoint 1: endpoints `GET /api/rooms/:id` and `GET /api/me/photos/:id`, event `match.ended`, and the extra database functions (`glow_met`, `cancel_glow`, `unmatch`, `block_user`, `create_report`, `send_message`, `get_match`, `list_matches`, `match_photo_path`, `get_room_state`). See D16 to D19.
7. **Root package.json.** I added `@hey-api/openapi-ts` 0.99.0, `typescript` 6.0.3 (its peer, same version as `server`) and `yaml` 2.9.1 as devDependencies, as pre-approved. `pnpm-lock.yaml` is updated.
8. **Password sign-in** stays on: `config.toml` keeps the defaults `scripts/dev-token.sh` uses.

_From A3, 2026-10-24._

1. **Two ownership rows in `AGENTS.md`**, changed in PR #3 (labeled `cross-owner`) because `agents-md.test.ts` needs every module folder named: B5's module is `GlowRealtime` (supabase-swift already has a target named `Realtime`), and C3 owns a new `LiveActivityShared` module that holds the Live Activity attributes (D41). Please keep or reword them.
2. **Service protocol ownership** (D40): please add to the iOS table that from Wave 1 each service owner owns its protocol and mock in AppCore: `AppCore/Services/SessionService.swift` and `AppCore/Mocks/PreviewSessionService.swift` (B1), `LocationService` (B2), `ImagingService` (B3), `PushService` and `RealtimeService` (B5). The rest of AppCore stays A3's (A1's, once A3 is done).
3. **Who owns `Package.swift` and `project.yml` after Wave 0.** Owners will ask under A3 for dependencies and routes. With A3 finished, those requests land on you. The how-tos are in A3's Status section below.
4. **macOS CI.** `scripts/sim.sh setup`, `build` and `test` run unattended with `GLOW_CI=1` (or `CI`): no signing, no prompts, exact package versions from `ios/Package.resolved`, non-zero exit on any failure, result bundles in `ios/build/results/`. Two suggestions for `ci.yml`: cache `ios/build/SourcePackages` keyed on `hashFiles('ios/Package.resolved')` (it saves the package clones on every run), and point the failure artifact at `ios/build/results/*.xcresult` (already covered by your `ios/build/**/*.xcresult` glob). `scripts/sim.sh lint` runs exactly your SwiftLint and SwiftFormat steps, and `scripts/sim.sh verify-project` checks that xcodegen is deterministic and no `.xcodeproj` is in git, if you want a step for it.

_A1's answers, 2026-10-24._

- A2 1: done in #13. `server/src/server/http/operations.ts` re-exports the generated registry, the placeholder is deleted, and `pnpm stubs` (`scripts/stub-routes.mjs`) adds a 501 stub for any operation without a route file, using `operationInfo` for the owner. 2: the codegen cache is in `ci.yml` (A1-D2). `codegen.sh --verify` on macOS is left out to save macOS minutes. 3: adopted (A1-D3). 4: as listed. 5: in "Writing a server route" in `AGENTS.md`. 6: done in #13 and #14. 7 and 8: thanks. Checkpoint 1 fixes: merged as #14, with stubs for the four new operations and the spec updated in the same PR.
- A3 1: kept, lightly reworded, with D41. 2: done in #4 (D40 rows). 3: accepted; ask under **For A1**. 4: done, the macOS job caches `ios/build/SourcePackages` on `ios/Package.resolved`, runs `sim.sh lint` and `sim.sh verify-project`, and keeps `ios/build/results/*.xcresult` on failure.

### For A2

_From D2, 2026-10-25._ Two small SQL changes for a later migration, both info: `match_json`'s `lastMessageAt` should ignore messages B8 flagged (`moderation <> 'flagged' or sender_id = viewer`), and `private.location_fresh` should use the person's latest check in the room rather than any pass in the last 2 minutes. Also see D2-D2 in `docs/DECISIONS.md` (a ban list), which needs David's yes first.

_From B4, 2026-10-24._ PR [#9](https://github.com/davidaxie/glow/pull/9).

1. **`0004_b4_deck_set_based.sql` replaces three of your helpers.** `private.open_checkin`, `private.active_checkin` and `private.pair_eligible` keep their names, arguments and answers, but now read three views, `private.open_checkins`, `private.active_cards` and `private.eligible_pairs`, which `get_deck` joins for the whole room at once (B4-D5). Every pgTAP test passes on top of it. Please put any future change to who sees whom in those views, so the deck, taps, `card_visible_to`, Realtime and glow all follow.
2. **Lockdown for views.** `010_lockdown` checks tables (`relkind` r and p). The new views are closed to `anon` and `authenticated` (revoked explicitly, plus your default privileges), but a check over `relkind = 'v'` too would keep it that way.

_A2's answers, 2026-10-24:_ 1 done (`server/src/contracts/operations.ts`, your shape). 2 done (your names; admin operations defined). 3 adopted (see For A1, item 3). 4 as listed. 5 done. 6 as listed. 7 done.

_From A1, 2026-10-24._

1. **Generated server registry.** The route helper needs one entry per `operationId`, exported from `server/src/contracts` (say `server/src/contracts/operations.ts`) in this shape, which today's placeholder in `server/src/server/http/contract-placeholder.ts` copies:

   ```ts
   export const operations = {
     getMatch: {
       method: 'GET',                       // HttpMethod
       path: '/api/matches/{id}',           // the OpenAPI path
       auth: 'user',                        // 'user' | 'public' | 'cron', from `security`
       params: z.object({ id: z.uuid() }),  // path params, when there are any
       query: z.object({ ... }),            // when there is a query
       body: z.object({ ... }),             // JSON body, or the string 'multipart' for uploads
       maxBodyBytes: 65536,                 // optional
       responses: { 200: MatchSchema, 404: ErrorSchema },  // zod schema, null for no body, 'raw' for images, HTML and the link file
     },
   } as const;
   ```

   The type is `OperationDef` in `server/src/server/http/operation.ts`; import it or match it. Use zod 4 (the workspace has `zod@4.6.7`). Plain `z.object` is fine: the helper sends the parsed reply, so undeclared fields never leave the server.
2. **operationIds.** The stubs use the names in the placeholder (`getMe`, `updateProfile`, `addProfilePhoto`, `deleteProfilePhoto`, `testLogin`, `setPaused`, `deleteAccount`, `registerDevice`, `deleteDevice`, `resolveRoom`, `joinRoom`, `leaveRoom`, `getAppSiteAssociation`, `getRoomWebPage`, `createCheckin`, `getCardImage`, `getMatchPhoto`, `getDeck`, `createTap`, `listMatches`, `getMatch`, `setChoice`, `getGlow`, `markGlowMet`, `cancelGlow`, `listMessages`, `sendMessage`, `unmatch`, `createBlock`, `createReport`, `logCapture`, `runPurge`). Use whatever names you like in `openapi.yaml`; A1 renames the stubs when wiring codegen. Please also define the `/api/admin/*` operations so B7 gets stubs.
3. **Error shape.** The server sends `{ "error": { "code": string, "message": string, "issues"?: [{ "path": string, "code": string, "message": string }] } }` for 400, 401, 404, 409, 413, 415, 429, 500, 501 and 503 (see `server/src/server/http/errors.ts`). Codes: `bad_request`, `unauthorized`, `not_found`, `conflict`, `payload_too_large`, `unsupported_media_type`, `rate_limited`, `internal`, `not_implemented`, `unavailable`. Please use this as the `Error` schema, or tell A1 yours and A1 will match it. There is no 403 anywhere (P11).
4. **Auth in the contract.** Every operation is Bearer-authenticated except: `POST /api/dev/test-login`, `GET /.well-known/apple-app-site-association` and `GET /r/{slug}` (public), and `GET /api/cron/purge` (cron secret, sent as `Authorization: Bearer`). A1 marked `GET /api/cards/{cardId}/image` as Bearer plus B3's signed link; tell A1 if you'd rather it be signed-link only.
5. **Codegen in CI.** The Ubuntu job runs `scripts/codegen.sh` after `supabase start`, then fails if `git diff` shows changes or new untracked files. Please make the script deterministic and runnable on Ubuntu (Swift is on the runner image; tell A1 if you need it on the macOS job instead). Add your codegen devDependencies to the root `package.json` in your PR; that's pre-approved, and `pnpm codegen` already calls your script.
6. **pgTAP in CI** runs `supabase start -x studio,imgproxy,edge-runtime,logflare,vector,supavisor,postgres-meta` then `supabase test db`, with CLI 2.122.0 and your `config.toml` ports. Thanks for the port note: `server/.env.example` now uses `http://127.0.0.1:54421`.
7. **Password sign-in stays on locally**, please: `scripts/dev-token.sh` creates a throwaway `@glow.test` user with the admin API and signs in with a password, so CI can smoke-test every endpoint with a real token.

_From A3, 2026-10-24._

1. **Where the Swift client goes.** Write swift-openapi-generator's output (modes `types` and `client`, `accessModifier: public`) to `ios/Packages/GlowKit/Sources/APIClient/Generated/`, as `Types.swift` and `Client.swift`. When `Client.swift` exists, `Package.swift` switches on `GLOW_GENERATED_CLIENT`, which adds `GlowAPI.client` and `GlowAPI.perform { try await $0.getMe() }`. Nothing else to wire. Keep the generator config and any other non-Swift files out of `Sources/` (SwiftPM warns about them).
2. **Paths keep the `/api` prefix** in `openapi.yaml` (`/api/me`, not `/me` under a `/api` server), matching A1's route helper. `GlowAPI` uses `API_BASE_URL` (`http://localhost:3000`) as the server URL.
3. **Swift constants** from `constants.json`: put them in the same `Generated/` folder (say `Constants.swift`), public, so every module that imports APIClient sees them.
4. **Runtime version.** The package pins `swift-openapi-runtime` 1.13.3 and `swift-openapi-urlsession` 1.4.0. Generate with a swift-openapi-generator 1.x that works with them (1.14.x does). Tell A3 or A1 if you need different pins.
5. **Demo room values.** `ios/fixtures/demo-room.env` copies the demo room from your `seed.sql` (slug `demo`, 37.8029, -122.4484, token `DEMOSTATICTOKEN2`, code `HACK26`) for `sim.sh at venue` and `sim.sh scan demo`. Tell A1 if those change.
6. **Event payload keys.** The one push fixture A3 added (`ios/fixtures/push/match_created.apns`) guesses `type` and `match_id` next to `aps`. B5 replaces it from `contracts/events.json`.

### For A3

_From A2, 2026-10-24._ PR [#2](https://github.com/davidaxie/glow/pull/2).

1. **APIClient target dependencies** in `ios/Packages/GlowKit/Package.swift`. The generated files in `Sources/APIClient/Generated/` (`Client.swift`, `Types.swift`, `GlowConstants.swift`, `GlowEvents.swift`) import `OpenAPIRuntime`, `HTTPTypes` and Foundation. Please add:
   - `.package(url: "https://github.com/apple/swift-openapi-runtime", exact: "1.13.3")` → product `OpenAPIRuntime`
   - `.package(url: "https://github.com/apple/swift-openapi-urlsession", exact: "1.4.0")` → product `OpenAPIURLSession` (the transport for your wrapper)
   - `.package(url: "https://github.com/apple/swift-http-types", from: "1.0.0")` → product `HTTPTypes`, so the import is a declared dependency
   `scripts/codegen.sh --verify` builds exactly these files against those versions with strict concurrency, with zero warnings. Please don't use the build plugin; the generated files are committed, and CI checks they're current.
2. **SwiftLint and SwiftFormat:** please exclude `ios/Packages/GlowKit/Sources/APIClient/Generated` in `.swiftlint.yml` and `.swiftformat`. The files also start with `swiftlint:disable all` and `swiftformat:disable all`.
3. **Dates in the wrapper.** Every time is RFC 3339 with milliseconds (`2026-10-24T20:15:00.000Z`), so create the client with `Client(serverURL:configuration: .init(dateTranscoder: .iso8601WithFractionalSeconds), transport: URLSessionTransport(), middlewares: [...])`. The default transcoder rejects fractional seconds.
4. **404 mapping.** Every not-allowed answer is 404 `not_found` (P11). Errors decode as `Components.Schemas._Error` with `code` an enum (`Components.Schemas.ErrorCode`).
5. **Realtime topics** are lowercase: `GlowEvents.userTopic(userID)` and `GlowEvents.roomTopic(roomID)`. `UUID.uuidString` is uppercase and the policy refuses that. Join with `private: true`. Event payloads decode as `Components.Schemas.GlowEvent`, and `GlowEvents.EventType` and `GlowEvents.PushCategory` mirror `contracts/events.json`.
6. **Demo room for `scripts/sim.sh`** (local seed, test data):
   - `scan demo` → `glow://r/demo?t=DEMOSTATICTOKEN2` (in Release: `https://{DOMAIN}/r/demo?t=DEMOSTATICTOKEN2`)
   - `at venue` → 37.8029, -122.4484 (radius 200 m). For `at away`, 2 km north is 37.8209, -122.4484.
   - room code `HACK26`, room ID `de000000-0000-4000-8000-000000000001`
7. **Local Supabase** is `http://127.0.0.1:54421` (D10), with the publishable key in `server/.env.example`. Test people are listed under A2's status below; sign in with the email code (Mailpit at http://127.0.0.1:54424) or B1's Debug test sign-in.
8. **Test sign-in isn't in the generated client** (the `dev` tag is left out, D22), so a Release binary has no `testLogin`. B1 calls `POST /api/dev/test-login` with a hand-written Debug-only request.

_From A1, 2026-10-24._

1. **CI's macOS job** (runner `macos-26`, Xcode 26.6 default, iOS 26.5 simulators including iPhone 17 Pro) skips until `ios/project.yml` exists. Then it runs `brew install xcodegen swiftlint swiftformat`, `swiftlint lint --strict` (if `.swiftlint.yml` exists), `swiftformat --lint .` (if `.swiftformat` exists), `xcodegen generate --spec ios/project.yml`, then `scripts/sim.sh setup`, `scripts/sim.sh build` and `scripts/sim.sh test` with `GLOW_CI=1`. Please make those three work headless on a fresh runner: create Glow A and Glow B on the newest installed iPhone Pro runtime, no signing (`CODE_SIGNING_ALLOWED=NO`), and a non-zero exit on any failure. Without `sim.sh`, CI falls back to `xcodebuild test -scheme Glow -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'`, so a scheme named `Glow` that runs the unit tests helps.
2. **Local server for Debug builds.** `pnpm dev` serves `http://localhost:3000`. The local Supabase is `http://127.0.0.1:54421` with the public demo publishable key `sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH` (the same as `server/.env.example`). Debug needs an ATS exception for local networking.
3. **Server errors** reach the app as `{ "error": { "code", "message" } }`. 401 means sign in again, 404 means not found or not yours (map both to your not-found error), 503 means retry, and 429 comes with `Retry-After`.
4. **Ownership.** `AGENTS.md` gives you `ios/` for anything not listed, `ios/GlowTests/` and the package files under `ios/Packages/GlowKit/`. A server test fails if a file in git has no owner in `AGENTS.md`, so tell A1 if you add a top-level folder somewhere else.

_Answered by A3, 2026-10-24, in PR #3._ 1: done. `setup`, `build` and `test` run headless with `GLOW_CI=1` and exit non-zero on failure, and the scheme is `Glow`. Nothing is pinned newer than Xcode 26.0.1 (Swift tools 6.2, iOS 17 deployment target). 2: done. Debug uses `http://localhost:3000`, `http://127.0.0.1:54421` and that publishable key, and the ATS exception (`NSAllowsLocalNetworking`) and `glow://` scheme are added to Debug builds only (D34). 3: done. 401 is `APIError.unauthorized`, 404 is `.notFound`, 429 is `.rateLimited`, and idempotent requests retry 503 using `Retry-After`. 4: no new top-level folders. Two module rows changed (see For A1).

### For B1

_From D2, 2026-10-25._ (1) **D2-F3, low:** `updateProfile` accepts first names with control characters, bidi overrides and zero-width-only text (`"\u200B\u200B"` is stored as a blank name). Normalize to NFC, reject `\p{Cc}\p{Cf}\p{Zl}\p{Zp}`, require a letter, count graphemes. (2) **D2-F8, low:** have Session `await push.unregister()` before it clears the tokens, and retry a pending delete on the next launch. (3) Profile photos keep the JFIF header, which can hold a thumbnail: re-encode with sharp as B3 does for cards. (4) The email code lasts an hour; set `otp_expiry` to 600 and change "expires in an hour" in the email templates. (5) If you add CAPTCHA to sign-in (D2-F2), the app has to send its token. See `docs/SECURITY_REVIEW.md`.
_From D1, 2026-10-24._ The journeys sign person A in with a Debug-only launch argument, **`-GlowDebugTestLogin <email>`**: at launch, call `POST /api/dev/test-login` with that `@glow.test` address and start the session with the tokens it returns (replacing any stored session), then follow the profile's onboarding step as usual. Compiled out of Release like `GlowDebugOpenURL` (B9's gate already refuses `GlowDebug` arguments). `scripts/e2e/harness.ts person a` makes the person onboarded beforehand, so the app should land straight on the tabs. Until it exists, the four journeys that need a signed-in A (full, chat, block, expiry) can't pass; the push journey runs today on the preview session.

_From B5, 2026-10-24._ (1) Call `await dependencies.push.unregister()` before signing out, while the session can still reach the API, so this phone stops getting the person's pushes (B5-D4). (2) In the notifications onboarding step, call `try await dependencies.push.requestAuthorization()`; it shows the prompt and registers for a token if allowed. (3) `LiveRealtimeService` joins `user:{currentUserID()}` with `currentAccessToken()`, so it connects once your live Session returns both.

_From A1, 2026-10-24._ `HttpError` and `errorBody` now carry the contract's optional `reason`: `throw unprocessable('photo_rejected', 'Try another photo.', { reason: 'face_visible' })` sends 422 `{ error: { code, message, reason } }`. `conflict(code, message)` covers 409s like `onboarding_incomplete`. The route helper now validates against the generated contract, so `addProfilePhoto` takes A2's base64 JSON body, not multipart.

_From B8, 2026-10-24._ Profile photo moderation, in `@/server/moderation` (exact exports under B8 in Status):

```ts
import { moderateImage, photoRejected } from '@/server/moderation';

const verdict = await moderateImage('profile', jpegBytes); // Uint8Array, the JPEG as uploaded
if (verdict.decision === 'rejected') throw photoRejected(verdict.reason); // 422 photo_rejected
// verdict.decision is 'approved' or 'held': store it as profile_photos.moderation_status.
```

It throws `ModerationUnavailableError` (an `HttpError`, 503 `unavailable`, reason `moderation`) on a timeout or outage. Let it propagate and don't store the photo (B8-D2). Held photos (possibly under 18) are never shown until B7 approves them. Rate limits: `addProfilePhoto` and `deleteProfilePhoto` use the `photos` policy, `updateProfile` uses `account`, `testLogin` uses `signIn` (per IP). If A1 wires `limitRequest` into the route helper (For A1 below), you don't call anything; otherwise `await rateLimit(user.id, 'photos')` first thing in the handler.

_From B8, 2026-10-24, PR #22._ (1) The purge cron deletes any `profile-photos` object that has no `profile_photos` row (or whose profile is gone) once it's 2 minutes old, so upload and insert the row together, and delete the object when you delete the row (B8-D5). (2) Settings links: `navigate(.pause)` and `navigate(.deleteAccount)` open B8's screens; deleting signs the person out through `session.signOut()`. (3) Pausing calls your `session.refreshProfile()` afterwards, so `Me.profile.paused` stays current for anyone showing Visible or Paused.

### For B2

_From D1, 2026-10-24, `integration` PR._ Your two stand-ins in `server/src/server/rooms/stand-ins.ts` now call the real modules: `sendDeckChanged(roomId)` is B5's `notifyRoom(roomId, { type: 'deck.changed', roomId })` (the same Realtime request, so your leave tests pass unchanged), and `signedCardImage` is B3's `cardImageLink`. The function names stay, so `leave.ts` and `state.ts` didn't change. Rename or inline them whenever you like.

_From B7, 2026-10-24._ Two things the admin web relies on:

1. **Screen tokens.** Done: since #10, the display page uses your `displayToken` from `@/server/qr`. A live join with the display's current token through your `joinRoom` answered 200 (and a made-up token 404), and a test runs your `verifyRoomToken` on the display's token.
2. **Demo mode skips.** The room page shows how many location checks were skipped today in a demo mode room, by counting `location_checks` rows with `result = 'demo_skip'` since the start of the room's day. Please write one per skip (A2's note), with `purpose` `join` or `find`.
_From B3, 2026-10-24._ After a passed join, send `navigate(.checkIn(roomID, JoinTicket(ticket)))`. B3's check-in calls your `verifyJoinTicket(ticket, { userId, roomId })` and turns null into 422 `join_ticket_invalid` (the screen then offers "Back to rooms", `navigate(.rooms)`). Until your PR merges, `server/src/server/images/deps.ts` stubs it with your exact signature. If you export a way to issue a ticket (for tests), B3's route tests switch to it when the stub goes.
_From B3, 2026-10-24._ After a passed join, send `navigate(.checkIn(roomID, JoinTicket(ticket)))`. B3's check-in calls your `verifyJoinTicket(ticket, { userId, roomId })` from `@/server/rooms` and turns null into 422 `join_ticket_invalid` (the screen then offers "Back to rooms", `navigate(.rooms)`). B3's route tests mint tickets with your `issueJoinTicket`.
_From B1, 2026-10-24._ The live session gives the API a real access token once #6 merges, so `DebugAccessTokenFallback` in `FeatureRooms/Joining/RoomsServices.swift` can go.

_From A1, 2026-10-24._ 1: the registry is wired, and `server/app/api/rooms/[id]/route.ts` exists as a 501 stub for `getRoomState`; it's yours (listed in your `AGENTS.md` row), so replace the stub. 2: done. 3: `server/src/env.ts` has two optional variables, both validated and optional everywhere: `TESTFLIGHT_URL` (must be `https://testflight.apple.com/...`) and `APPLE_APP_ID` (`TEAMID.bundle.id`, like `ABCDE12345.com.davidxie.glow`). Please use `APPLE_APP_ID` for the link file rather than `APNS_TEAM_ID` plus `APNS_BUNDLE_ID`: the APNS variables only exist together with the push key, so a preview without push couldn't serve the link file. Read them with `getEnv()`.

_Answered by B2, 2026-10-24._ All three done in PR [#10](https://github.com/davidaxie/glow/pull/10): B2 took over the stub, and reads `APPLE_APP_ID` and `TESTFLIGHT_URL` with `getEnv()` (B2-D3, B2-D4).

### For B3

_From D2, 2026-10-25._ **D2-F6, low:** wrap the `GlowDebugCheckInPhoto` block in `FeatureCheckIn/CaptureStep.swift` (lines 52 to 61) in `#if DEBUG`, then delete its entry under `KNOWN` in `server/tests/security/release-surface.test.ts`.
_From C1, 2026-10-24._ FeatureDeck loads card photos through a stand-in (`FeatureDeck/Images/CardImageLoading.swift`, your loader's rules) until #7 merges. Nothing needed from you: C1 switches `DeckCardImage` to `PrivateImageView(.card(signedURL:))` and deletes the stand-in once it's on main. If `PrivateImageView` keeps the old photo on screen while a refreshed link loads (FeatureDeck refetches links every minute or so), tiles won't flash.

_From B2, 2026-10-24._ The join ticket, for `POST /api/rooms/{id}/checkin`. Branch `w1/b2-rooms`, file `server/src/server/rooms/ticket.ts`.

```ts
import { verifyJoinTicket } from '@/server/rooms';

verifyJoinTicket(
  ticket: string,
  expected: { userId: string; roomId: string; now?: Date },
): Promise<VerifiedJoinTicket | null>

type VerifiedJoinTicket = {
  locationCheckId: string;          // the location_checks row the join route wrote
  result: 'pass' | 'demo_skip';     // demo_skip: an admin in a demo mode room
  issuedAt: Date;
  expiresAt: Date;                  // issuedAt + JOIN_TICKET_TTL
};
```

- It never throws. It returns `null` for anything that isn't a live ticket issued to this person for this room: expired (past `exp`, or older than JOIN_TICKET_TTL), another person's, another room's, edited, malformed, or longer than 2 KB. Answer `null` with 422 `join_ticket_invalid`.
- The ticket is an encrypted JWT (JWE `dir` + `A256GCM`, key derived from `JOIN_TICKET_SECRET` with HKDF), so it's opaque: nothing in it is readable without the server's key (B2-D1). Treat it as an opaque string and never log it.
- Every join writes a `location_checks` row before the ticket is issued: `purpose = 'join'`, `result = 'pass'` (or `'demo_skip'`), plus an accuracy bucket. A ticket exists only for a passed or skipped check, so A2's 0002 `create_checkin` finds its row. If 0002 takes the check ID, pass `locationCheckId`.
_From B7, 2026-10-24._ The admin card and photo images are watermarked with the admin's own viewer code, by a stand-in, `watermarkJpeg(jpeg, viewerCode)` in `server/src/server/admin/watermark.ts` (sharp, a repeated faint code at -30°, JPEG at PHOTO_JPEG_QUALITY with no metadata). Please export your watermark from `@/server/images` (any name; tell B7 here) so admins and people in rooms get the same mark, and B7 will call yours instead.

_From A3, 2026-10-24._ `ios/fixtures/photos/` has four synthetic, faceless outfit images (D44). Add fixture photos with real faces that the people in them agreed to (or freely licensed ones) for the blur tests. `ios/fixtures/` is A3's, so add them in a `cross-owner` PR or ask A1.

_From B8, 2026-10-24._ Card photo moderation fails closed:

```ts
import { moderateImage, photoRejected } from '@/server/moderation';

const verdict = await moderateImage('card', jpegBytes); // throws ModerationUnavailableError (503) on timeout or outage
if (verdict.decision !== 'approved') throw photoRejected(verdict.reason);
// reasons: face_visible, nudity, no_outfit, no_person, possibly_minor, unreadable
```

Moderate before uploading to storage, so a rejected photo is never stored. In tests, `await moderationFixtureJpeg(['face_visible'])` gives a JPEG the local fake rejects (also `nudity`, `no_outfit`, `no_person`, `possibly_minor`, `slow` for the timeout, `error` for an outage); `moderationFixtureJpeg([])` is approved. Rate limit policy: `checkin` (10 per 10 min) for `createCheckin`, `join` for `joinRoom`, `resolveRoom` and `leaveRoom`.

_From B8, 2026-10-24, PR #22._ The purge cron deletes any `room-cards` object with no `checkins` row once it's 2 minutes old (B8-D5), so call `create_checkin` right after the upload, and delete the object yourself if `create_checkin` fails. With a real `ANTHROPIC_API_KEY`, the synthetic drawings in `ios/fixtures/photos/` are rejected `no_person`; the local fake (no key) approves them.

### For B7

_From D1, 2026-10-24, `integration` PR._ `watermarkJpeg(jpeg, viewerCode)` in `server/src/server/admin/watermark.ts` now calls B3's `watermark()` from `@/server/images/watermark`, so admin card and photo images carry the same mark people in rooms see (with the admin's own code). Your callers in `cards.ts` and `photos.ts` didn't change.

_From B3, 2026-10-24._ `watermark(jpeg, viewerCode)` from `@/server/images` draws the admin's viewer code across a photo (the same faint tiled pattern every image gets) and returns a metadata-free JPEG, for `adminCardImage` and `adminPhotoImage`. Serve with `Cache-Control: no-store`.

_From B8, 2026-10-24, PR #22._ (1) Reports: `create_report` stores the reported person, room, reason, trimmed details and, for match or chat reports, `evidence` (their last 20 messages). The reporter has already blocked them. Reports are deleted with either account (D23). (2) Capture flags: accounts with 3 or more `abuse_signals` in the last 24 hours (`select user_id, count(*) from abuse_signals where created_at > now() - interval '24 hours' group by user_id having count(*) >= 3`); the server logs `safety.capture_review` when someone reaches 3 (B8-D7). (3) Held profile photos (`moderation_status = 'held'`) are people who may be under 18, from `moderateImage('profile', …)`; they're never served until approved.

### For C1

_From D2, 2026-10-25._ On PR #25 (**D2-F9, low**): (1) only report a screenshot to `/api/abuse/capture` while the deck itself is on screen and the scene is active (the listener also fires over the mutual takeover and the report screen); (2) drop `result: "sent" | "mutual"` from the `deck_tap` analytics event, since it records a one-sided tap on the device. A UI test with a faked capture (P12) is still to come.
_From D1, 2026-10-24._ The journeys use your identifiers as published: `screen.FeatureDeck.roomHome`, `room.seeLooks`, `deck.notice.apply`, `deck.card.<id>`, `deck.detail.thatsThem`, `deck.confirm.tap`, and `deck.empty.checkInAgain` or `room.checkInAgain` after an expired check-in. `PushTapUITests` expects tapping `checkin_expiring` and `deck_changed` to open a screen whose identifier starts with `screen.FeatureDeck`. Please keep those stable, and tell D1 here if one changes. Your `DeckUITests.swift` in #39 is welcome in `ios/GlowUITests/`.

_From B3, 2026-10-24, also for C2._ Show card photos and match photos with the loader in Imaging (your modules already depend on it). It fetches through the API with the bearer token, never caches, and offers no save, share or drag:

```swift
import Imaging

PrivateImageView(.card(signedURL: card.image.url), label: "Today's look") { error in
    if error == .notFound { await model.refreshDeck() } // links last 60 s and are viewer-bound
}
PrivateImageView(.matchPhoto(matchID, index: 0), label: "Photo 1 of 3")

// Or, without the view:
let photo = try await dependencies.imaging.loadPrivateImage(.card(signedURL: url)) // PrivateImage (UIImage)
```

Errors are `PrivateImageError` (`.notFound` for expired, someone else's, ended or missing; `.invalidSource` if a link isn't a relative `/api/cards/{id}/image?exp&sig`). In previews and tests, `Dependencies.preview(imaging: PreviewImagingService(load: .placeholder))` or `.fail(.notFound)`.

_From B8, 2026-10-24, PR #22._ From a card, open `navigate(.block(.card(cardID)))` or `navigate(.report(.card(cardID)))`; both sheets are B8's. After a block the card leaves both decks on the next fetch, and the room gets `deck.changed`; drop the card locally at once too. Screenshots and recordings of the deck: `POST /api/abuse/capture` with `{ kind: 'screenshot' | 'recording', roomId }` (always 204, rate limited to 60 an hour).

### For B4

_From D1, 2026-10-24, `integration` PR._ `server/src/server/deck/dependencies.ts` now exports B3's `cardImageLink` from `@/server/images/signed-link`, and `deck/stubs/card-link.ts` is deleted. Same signature and the same links. Also, with B5's #37, `GET /api/matches` hands `list_matches`'s `settled` to B5's `notifySettled` (exported through `dependencies.ts`, still after the response), in place of `announceSettled`, which is gone. Same events to the same people; `list-matches.test.ts` and `matches.integration.test.ts` now assert on `notifySettled`.

_From B3, 2026-10-24._ Sign each deck card's image link with `cardImageLink(cardId, viewerId)` from `@/server/images`: it returns the contract's `SignedImage` (`url`, `expiresAt`), a 60-second link that only works for that viewer. `GET /api/cards/{cardId}/image` then checks `card_visible_to`, so a card serves only while the deck may show it (and only after `get_deck` has recorded the view).

### For D1

_From B3, 2026-10-24._ For the end-to-end run:

- Check in with `ios/fixtures/photos/outfit-real-*.jpg` (real people, neck down). Vision doesn't see A3's synthetic drawings as people, so those four ask for a retake, by design.
- Debug Simulator builds take `-GlowDebugCheckInPhoto <absolute path>`, which adds a **Use test photo** button (`checkin.debugPhoto`) so UI tests skip the out-of-process photo picker. Identifiers: `checkin.choosePhoto`, `checkin.usePhoto`, `checkin.retake`, `checkin.top.<color>`, `checkin.submit`, `checkin.notice`, `checkin.rejoin`. Chips for hair and extras are found by their label (`Short`, `Glasses`).
- `create_checkin` needs a passing join check from B2's join route in the last 10 minutes.

### For D4

_From B3, 2026-10-24._ Every word of check-in is in `FeatureCheckIn/CheckInCopy.swift` (retake messages per moderation reason, tag names) and the step views. No String Catalog yet.

### For C4

_From D1, 2026-10-24._ For the journeys: a root identifier starting `screen.FeatureChat` on `ChatView` (`PushTapUITests` checks `glow_ended` and `message_created` open it), and identifiers on the composer (`chat.field`), Send (`chat.send`) and the menu (`chat.menu`). The chat and block journeys use the labels "Message", "Send" and "Chat options" today.

_From B8, 2026-10-24, PR #22._ (1) From the chat menu, `navigate(.block(.chat(matchID)))` and `navigate(.report(.chat(matchID)))`. After either, B8's sheet sends the person back to the matches list. (2) Please make unmatch send exactly what a block sends: `match.ended` to both people and nothing else about why, so the other person can't tell a block from an unmatch (D18, B8-D6). Unlike a block, an unmatch also makes the pair eligible again, so `deck.changed` to the rooms either person is checked into fits too.

_C4's answer to PR #22's note, 2026-10-24:_ (1) Agreed: the chat menu sends exactly those Routes, and your sheet taking people back to the matches list is fine; the open chat also closes itself on `match.ended`. (2) Done: an unmatch now sends `match.ended` to both and `deck.changed` to every room where either has an open check-in, the same rule as `block_user`, and an integration test runs an unmatch and your `blockFor` side by side and checks the events are identical (C4-D6).

_From B8, 2026-10-24._ Chat moderation never throws and never takes more than MODERATION_TIMEOUT (2.5 s):

```ts
import { moderateText, messageRejected } from '@/server/moderation';
import { rateLimit } from '@/server/ratelimit';

await rateLimit(user.id, 'messages'); // 30 per minute; throws 429 rate_limited with Retry-After
const verdict = await moderateText(body);
if (verdict.decision === 'flagged') throw messageRejected(); // 422 message_rejected, don't store it
// verdict.decision is 'passed' or 'pending': pass it to send_message as messages.moderation.
```

`pending` means moderation was slow or down: the message goes through, and B8's purge cron reviews it later and sets `moderation = 'flagged'` if it's bad. Please hide `flagged` messages from the recipient in `listMessages`. In tests, `[glow-test:flag]`, `[glow-test:slow]` and `[glow-test:error]` in a body drive the local fake (`TEXT_FIXTURE`).

_C4's answer, 2026-10-24:_ done as written, with one difference: `send_message` has no moderation argument and stores every row as `pending`, so the chat route marks a `passed` message right after the insert (C4-D2). A failed mark leaves it `pending` for your review. Flagged messages are hidden from the recipient and still shown to their sender (C4-D3).

### For B8

_From C4, 2026-10-24._ **Report and block from chat** (agreed in PR #22's note under For C4): the chat's header menu sends `navigate(.report(.chat(matchID)))` and `navigate(.block(.chat(matchID)))`, your sheet sends `context: chat, contextId: matchID` and takes people back to the matches list. Nothing else needed.

### For B5

_From D2, 2026-10-25._ **D2-F8, low:** `LivePushService` keeps the registration only in memory, so after a relaunch or a failed delete, `unregister()` does nothing and the server keeps the device. Keep the device ID in the Keychain and retry a pending delete at launch.

_Answered by B5, 2026-10-24._ B9: done, Debug registers `sandbox` and Release `production` (`PushModule.apnsEnvironment`, B5-D5). A3: done in #15, one fixture per event from `contracts/events.json`.
_From C3, 2026-10-24._ PR [#27](https://github.com/davidaxie/glow/pull/27). Two follow-ups, neither blocking: (1) when your `notifySettled(settled)` merges, `markGlowMet` and `getGlow` (`server/src/server/glow/handlers.ts`) and `startGlow` will switch to it from C3's `settledAnnouncements`, which sends the same events (`glow_expired` → `glow.ended`, `choice_timeout` → `match.choice`). (2) Later, with an Apple account: ActivityKit push updates for the glow's Live Activity (`pushType: .token`, a `liveactivity` APNs push on `glow.ended`), so the lock screen shows how a glow ended even while the app sleeps. Until then it reads "Time's up" on time from its stale date (C3-D4).
_From C4, 2026-10-24._

1. **Realtime.** FeatureChat subscribes with `dependencies.realtime.events(for: matchID)` and refetches on any event for its match, so it needs nothing beyond #15. The "under a second on the other Simulator" check waits on your live `GlowRealtime` (`w1/b5-push`). A local stand-in built on supabase-swift's `RealtimeClientV2` (private `user:{id}` channel, never committed) already got a message onto the Simulator 42 ms after the server's broadcast.
2. **Server.** Chat calls your real `notify` and `notifyRoom` now: `message.created` to the recipient only; on unmatch, `match.ended` to both and `deck.changed` to their rooms (like a block).
3. **Optional, foreground banners.** While someone has a chat open, a "New message" banner for that same match is noise. If `PushService.foregroundPresentation(for:)` could suppress it, FeatureChat would need a way to say which chat is on screen (an AppCore value both modules can see). Low priority; nothing leaks either way.

_From B9, 2026-10-24._ Every TestFlight build is the **Release** configuration, signed for the App Store, so its entitlement is `aps-environment = production` (B9-D1); Debug builds from Xcode are `development`. So register `production` in Release builds and `sandbox` in Debug (a compile-time `#if DEBUG` is enough; there's no development-signed Release build in the pipeline). On the server, the one `.p8` key in `APNS_*` covers both environments; send to `api.push.apple.com` for `production` rows and `api.sandbox.push.apple.com` for `sandbox` ones. B9's Done-when box "Push works on a TestFlight build, through production" is checked with your sender, two iPhones and a mutual tap (docs/RELEASE.md, step 9).

_From B7, 2026-10-24._ Done: since #15, the admin module sends `deck.changed` (`notifyRoom`) when a room is paused, resumed, ended or its times change, a card is removed or someone is banned, and `match.ended` (`notify`) to both people when a ban ends their match.

_From A3, 2026-10-24._ Please replace `ios/fixtures/push/match_created.apns` (A3's stand-in: lock screen text plus a match ID) with fixtures built from `contracts/events.json`, one per event. `scripts/sim.sh push A <event>` picks up `ios/fixtures/push/<event>.apns`. The spec's Realtime module is `GlowRealtime`.

### For B6

_From A3, 2026-10-24._ The app icon (`ios/Glow/Assets.xcassets/AppIcon.appiconset`), the accent color and `LaunchBackground` (the launch screen color) are A3's placeholders; they're yours to replace. `.swiftlint.yml` has a marked spot under `custom_rules` for your "no colors or fonts in feature modules" rule.

_Answered by B6, 2026-10-24._ The icon is replaced on `w1/b6-design`. The accent color (#FF4FA3) and `LaunchBackground` (#0B0B10) already match the tokens, so they stay (B6-D5). The lint rule is in #21 (merged).

### For B9

_Answered by B9, 2026-10-24, in PRs #5 and #17._ The team stays in `DEVELOPMENT_TEAM` in `Shared.xcconfig` (David fills it in; the lane refuses to ship while it's empty). The Release Supabase values, `POSTHOG_KEY` and `SENTRY_DSN` go in from CI secrets through an `xcodebuild -xcconfig` override, never into git (B9-D2). Release `aps-environment = production` needed manual App Store signing for the archive (#17, B9-D1). The App Privacy answers are generated from the manifest and CI fails if they drift (`ios/fastlane/app-privacy.json`).

_From B2, 2026-10-24._ Two server variables, both optional and read with `getEnv()`: `APPLE_APP_ID` (`{TEAM_ID}.com.davidxie.glow`, once the Apple team exists) makes `/.well-known/apple-app-site-association` name the app, so QR links open Glow; until it's set the file lists no app (B2-D3). `TESTFLIGHT_URL` (the public `https://testflight.apple.com/join/...` link) puts the "Get Glow on TestFlight" button on the `/r/{slug}` page (B2-D4). Set both on Vercel preview and production when they exist, and keep `GLOW_WEB_DOMAIN` in the app the same host the server is on.

_From A3, 2026-10-24._ Signing lives in `ios/Glow/Config/Shared.xcconfig` (`DEVELOPMENT_TEAM` is empty, `CODE_SIGN_STYLE = Automatic`), so set the team there. `GLOW_WEB_DOMAIN` (same file) is {DOMAIN}. Release `SUPABASE_URL` and `SUPABASE_ANON_KEY` are empty in `Release.xcconfig`: pass them, and `POSTHOG_KEY` (and `SENTRY_DSN` once Sentry is back, D36), as xcodebuild settings from CI. `aps-environment` is `development` in Debug and `production` in Release. App Privacy answers should match `ios/Glow/PrivacyInfo.xcprivacy` (D43).

### For D1

_From B5, 2026-10-24._ A UI test that taps a notification would let `scripts/sim.sh push A <event>` check every event's screen headlessly: send each `ios/fixtures/push/*.apns` (`xcrun simctl push`), tap the banner through `XCUIApplication(bundleIdentifier: "com.apple.springboard")`, and assert the screen (`RealtimeEvent.destination` lists them). Today only `match_created` was tapped by hand.
### For C2

_From D1, 2026-10-24._ Two small things for the end-to-end journeys (`ios/GlowUITests/Journeys/`):

1. **A root identifier on each FeatureMatch screen**, starting `screen.FeatureMatch` (for example `screen.FeatureMatch.mutual`, `.match`, `.list`). `PushTapUITests` checks that tapping `match_created`, `match_choice`, `match_recheck` and `match_ended` opens a screen with that prefix; today it passes on the placeholder's `screen.FeatureMatch`.
2. **Identifiers on the two choices**, say `match.choose.find` and `match.choose.chat`. The journeys find them by their words ("Find each other", "Just chat") for now, which breaks the day D4 changes the copy.

_From C3, 2026-10-24._ PR [#27](https://github.com/davidaxie/glow/pull/27). **`startGlow`: agreed, exactly your signature.** `import { startGlow, type StartGlowOutcome } from '@/server/glow'`, then `await startGlow(db, matchId)`. It calls `start_glow` with the 300 words in `server/src/server/glow/words.ts` and sends every event the result implies: `glow.started` to both on `started`, `match.choice` to both on `chat`, `match.recheck` to each of `staleUserIds` on `waiting` with `location_stale`, and the `settled` entries (`glow.ended` for `glow_expired`, including other pairs' glows in the room, `match.choice` for `choice_timeout`). Events go out after the response (Next's `after()`), and notifying never throws. It throws only `notFound()` (the match ended or doesn't exist) and 503 when the database can't be reached. Swap your stand-in for it when #27 merges.
_From C1, 2026-10-24._ `ios/GlowUITests/DeckUITests.swift` is in your folder through `cross-owner` PR [#39](https://github.com/davidaxie/glow/pull/39): the P12 test (fake recording, the deck is covered, no card on screen), its control, and the timed find in a room of 200. They run on FeatureDeck's fixture rooms (`-GlowDebugDeckFixture`), so they need no server. Fold them into your suite as you like; the identifiers are in C1's status below.

### For C2

_From C1, 2026-10-24._ A mutual tap closes the enlarged card and sends `navigate(.mutual(matchID))`, as the brief asks. If FeatureMatch also opens the takeover on `match.created`, both land on the same full-screen cover, so nothing doubles up.

## Status

### D2 · Security and privacy red team

_2026-10-25, Wave 3._ PR [#41](https://github.com/davidaxie/glow/pull/41) on `w3/d2-security`. Fix PRs: [#46](https://github.com/davidaxie/glow/pull/46) (D2-F1, merged) and [#49](https://github.com/davidaxie/glow/pull/49) (D2-F4, merged). **The report is [`docs/SECURITY_REVIEW.md`](SECURITY_REVIEW.md)**, for Checkpoint 4.

**Result.** No critical finding. One high (D2-F1, anyone could take over an account before its owner signed up, through Supabase's password sign-up), fixed and retested. Two medium (D2-F2 email enumeration through Supabase Auth, D2-F5 a banned person registering again), one accepted medium (D2-F7 fake GPS), and the rest low or info, each with an owner and a fix.

**Built** (`server/tests/security/`, all in `scripts/ci-local.sh`; the "live" ones use a real Supabase and skip on the shared stack)

- A test for P1 to P11 (P12 waits for C1's deck PR), the attack list, C4's chat attack list, B7's ask (admin routes as a non-admin) and A2's D56. The table of which test holds which invariant is at the top of the review.
- `proxy.live.test.ts` plus `proxy/addon.py`: a scripted two-person journey through mitmproxy (reverse proxy on localhost, plain HTTP, no certificate installed), with every request, response and Realtime frame scanned. Opt-in: `D2_PROXY=1`, with `brew install mitmproxy`, a running server and your own Supabase (commands in the test's header).
- `0005_d2_no_passwords.sql` and its pgTAP file (D2-F1); a NUL check in the route helper (D2-F4).

**Still open**

- **The Simulator proxy run.** Needs a free Simulator slot and B1's session code on `main` (only B1's server is). The same scan then runs with Glow A as person A.
- **P12** (deck blur while recorded) needs C1's PR #25. Two notes for it are in D2-F9.
- **Fixes waiting for their owners**: see the Requests below. None is high or critical.
- **Needs David**: item 20 (cloud Auth settings), and the call on D2-D2 (keep a hash of banned people's email and Apple ID, or not).

**Next wave needs**

- **D1:** `server/tests/security/helpers/` has `World` (people, rooms, check-ins, matches on a live stack) and `call(operationId, ...)` (the real route handlers, in process), if a journey needs them. Test sign-in and the dev-token script are unchanged (`@glow.test` people can still use passwords locally).
- **Everyone:** any new text field is covered by the NUL check, and a new route needs nothing added: `fuzz.live.test.ts` and `admin.live.test.ts` walk the contract's operation list by themselves.

### B1 · Sign in and onboarding (server)

_2026-10-24, Wave 1._ The server half, split out so everything that needs a signed-in person can start (the iOS half stays on draft [#6](https://github.com/davidaxie/glow/pull/6)).

**Built** (`server/src/server/profiles`, routes under `server/app/api/me/**` and `dev/test-login`): `GET /api/me`, `PUT /api/me/profile` (18+ checked before anything is written: 422 `under_18`, and the database trigger refuses it too), `POST /api/me/photos` (base64 JPEG, metadata stripped at segment level, 4:5 and at most 1920 px, B8's `moderateImage('profile')`: rejected is 422 `photo_rejected` + reason, held is stored but shown to nobody, an outage is 503 and nothing is stored), `GET` and `DELETE /api/me/photos/{id}` (404 for anything not mine, 409 `last_photo` once finished), `POST /api/me/onboarding/complete` (A2's `complete_onboarding`, with or without push), and `POST /api/dev/test-login` (local only, `@glow.test` only, no passwords: B1-D7). The state machine is `deriveStep` in `onboarding.ts`; `GET /api/me` reconciles it every time (B1-D1). Decisions B1-D1 to B1-D7 are in `docs/DECISIONS.md`.

**Test sign-in, for D1 and the Simulator.** With `ALLOW_TEST_LOGIN=1` in `server/.env.local` (`pnpm env:setup --test-login`):

```
curl -s -X POST $GLOW_API/api/dev/test-login -H 'content-type: application/json' -d '{"email":"alex@glow.test"}'
# -> { accessToken, refreshToken, expiresIn, userId }   (404 unless the server is local with ALLOW_TEST_LOGIN)
```

Seeded people (`alex`, `blake`, `casey`, `drew`, `admin`) come back onboarded; `new@glow.test` starts at the profile step. They have no profile photos: add one with `POST /api/me/photos` (a 4:5 JPEG, base64) if a match needs something to show. Any other `something@glow.test` address is created on first use.

**For other routes**: `assertOnboardingComplete(user.id)` from `@/server/profiles` throws 409 `onboarding_incomplete`.

**Tests**: `server/tests/profiles/` (age rule, state machine, metadata stripping, and every route against a live local Supabase). They skip without a reachable Supabase and use `GLOW_SUPABASE_URL` for an own stack.

**Still mocked**: nothing in B1's server paths.

### B3 · Check-in and private images

_2026-10-24, Wave 1._ PR [#7](https://github.com/davidaxie/glow/pull/7) on `w1/b3-checkin`, plus the fixtures in PR [#18](https://github.com/davidaxie/glow/pull/18) (merged). Decisions B3-D1 to B3-D9.

**Built**

- **On the phone (Imaging).** `CardPhotoPipeline`: decode with the orientation applied and at most 1920 px, Vision face rectangles grown 30% on every side, a strong Gaussian blur then coarse pixelation in each box, a second face check that blurs any survivor and refuses to upload if one survives twice, the person check (a face or a human rectangle), and a JPEG at quality 0.8 in sRGB with every metadata segment stripped by `JPEGSanitizer` (B3-D4, B3-D5). `PrivateImageLoader` and `PrivateImageView` for card and match photos, no caching (B3-D8). `ImagingModule.live` is the real service.
- **Check-in screens (FeatureCheckIn).** Camera with a neck-down framing guide (AVFoundation, in memory only); the photo picker in Debug Simulator builds; "This is what others will see"; the tag picker (top color required, hair length, hair color, extras) with B6's chips; upload; a retake message for each moderation reason; "Back to rooms" when the join ticket has expired. The original photo is dropped as soon as the blurred copy exists, and only `PreparedCardPhoto` can be uploaded (P3).
- **Server (`server/src/server/images`).** `POST /api/rooms/{id}/checkin`: rate limit, join ticket, B8's moderation on the bytes as uploaded (fails closed), a server-side re-encode with no metadata (B3-D3), `room-cards/{roomId}/{cardId}.jpg`, `create_checkin`, replaced photos deleted at once (B3-D9). `GET /api/cards/{cardId}/image`: HMAC link bound to the viewer and 60 seconds, `card_visible_to`, a faint tiled watermark of the viewer's code drawn with a built-in pixel font (B3-D7), `no-store`. `GET /api/matches/{id}/photos/{n}`: `match_photo_path`, watermarked too (B3-D2). Every refusal is the same 404 (P11).

**Proof**

- Server: 60 Vitest tests in `server/tests/images/` (signed links, watermark incl. the [snapshot](../server/tests/images/__snapshots__/watermarked-card.jpg), upload clean-up, every route's 401/404/422/503 path). Against the local Supabase: check-in 201, own card 200 with the watermark, the same link from someone else 404, a valid link for someone the deck never showed it to 404, an expired link 404, the anon key can't read `room-cards`, and an old card's link 404 after a new check-in.
- iPhone: 22 `ImagingTests` (every face fixture comes out blurred and Vision finds no face afterwards, the detail in each face box drops by over 80%, no EXIF/GPS/TIFF survives, orientation, size, drawings refused, the loader's link checks) and 11 `FeatureCheckInTests` (the upload carries exactly the blurred, metadata-free photo; each rejection reason gives a retake; expired ticket; outage keeps the photo; tags).
- Screens on Glow A (B3), against the local server: [capture](shots/checkin-1-capture-A.png), [blur preview](shots/checkin-2-preview-A.png), [preview with no face](shots/checkin-2b-preview-no-face-A.png), [tags](shots/checkin-3-tags-A.png), [tags picked](shots/checkin-3-tags-picked-A.png), [checked in](shots/checkin-4-done-A.png), [face_visible retake](shots/checkin-5-rejected-face-visible-A.png), and at the largest accessibility text size: [capture](shots/checkin-1-capture-largest-text-A.png), [preview](shots/checkin-2-preview-largest-text-A.png), [tags](shots/checkin-3-tags-largest-text-A.png). Recording: [checkin-flow-A.mp4](shots/checkin-flow-A.mp4) (23 s). The retake shot used a local, uncommitted server change that rejects every photo, because B8's dev fake only rejects marked fixtures and the app strips the marker.

**Still mocked**: nothing. Check-in uses B2's `verifyJoinTicket` (`@/server/rooms`), B8's moderation, A1's per-route rate limit and A2's database functions; the route tests mint tickets with B2's `issueJoinTicket`.

**Next wave needs**

- **C1, C2:** `PrivateImageView` and `loadPrivateImage` (For C1 and C2, above).
- **B4:** `cardImageLink` for deck cards (For B4).
- **B7:** `watermark()` for the admin image routes (For B7).
- **D1:** the test-photo launch argument and identifiers (For D1).
- **D2:** to try: a link replayed by another account, an expired or stretched `exp`, a forged `sig`, a link for a card the deck never showed, `room-cards` with the anon key, EXIF or GPS in an upload (the server strips it), and a face that survives the phone's blur (moderation's `face_visible`).
### C3 · Glow mode

_2026-10-24, Wave 2._ PR [#27](https://github.com/davidaxie/glow/pull/27) on `w2/c3-glow`, plus the `cross-owner` PR [#38](https://github.com/davidaxie/glow/pull/38) for A1 (a Debug-only `GlowDebugRoute` launch argument, For A1 item 2).

**Built**

- **Server, `server/src/server/glow/`.** `startGlow(db, matchId)` for C2 (see For C2): it calls `start_glow` with the 300 code words and sends every event the result implies through B5's `notify`. The three routes: `GET /api/matches/{id}/glow` (through `get_match`, so the glow's timeout applies first), `POST …/glow/met` and `POST …/glow/cancel` (Cancel and Switch to chat). Replies carry only the contract's Glow fields (P1). Anything that isn't mine, or has ended, is 404 (P11). An ended glow shows for `GLOW_ENDED_RETENTION`, then it's gone (C3-D2). `glow.ended` goes out once, from the call that ended the glow, plus whatever that call settled (C3-D3).
- **`words.ts`**: 300 hand-picked code words, with tests for every rule they were picked by (C3-D1).
- **FeatureGlow**: `GlowView(matchID:)` on B6's `GlowSurface` in the match color. It shows the code word huge (`GlowCodeWord`), the color's name, the meeting spot, "Hold your phone up" and a 15-minute countdown, with We met, Switch to chat, End glow (confirmed) and Hide glow. We met stays on screen at every text size. Full brightness and keep-awake are on only while the glow is on and showing (`GlowModel.wantsFullBrightness`); every way out puts the person's own brightness back. B6's three-beat haptic plays when the glow starts and when they tap We met. Under Reduce Motion it's B6's slow fade. The ended, gone, offline and loading screens use the dark background. While open, the glow refetches every 5 seconds, and at once on `glow.ended` (C3-D5).
- **Live Activity**: `LiveActivityShared` holds `GlowActivityAttributes` and `GlowActivityDisplay` (the words for every moment, unit-tested). `ios/GlowLiveActivity/` draws the lock screen on the glow color, plus the Dynamic Island compact, expanded and minimal views. It shows only the color, the code word, the spot and the time (P6). Its stale date is the glow's end, so it reads "Time's up" on time even while the app sleeps, and it leaves the lock screen a minute after the glow ends (C3-D4).

**Done when**

- [ ] Glow A and Glow B show the same color, code word and meeting spot. **Server: proven. Two Simulators side by side: not captured yet.** Against a real local database, `GET …/glow` gave both people the identical glow (same id, color, word, spot and end time; contract fields only), in `glow.integration.test.ts` and by hand on port 3113 (aqua, "circus", Food line). Both phones render that reply through the same screen (snapshots). The two-Simulator screenshot needs a way to open `.glow` without a tap: #38, or B5's push taps or C2's matches list once live. Then: set `GlowDebugAccessToken` per Simulator (`xcrun simctl spawn <udid> defaults write com.davidxie.glow GlowDebugAccessToken <token>`), launch with `-GlowDebugRoute glow/<matchID>`, and `scripts/sim.sh shot glow-same`. The Simulator slots had to go back before that ran.
- [x] A database test proves no two active glows in a room share a color and code word. `server/tests/glow/glow.integration.test.ts` starts 40 glows in one room at the same moment through `startGlow` with the real 300 words. It checks that every active color plus word is unique (5 of each color, 40 different words, spots shared evenly), and that the unique index refuses a duplicate. It runs in `ci-local` and CI (`CI` set); locally, `GLOW_INTEGRATION=1`.
- [ ] The Live Activity appears, counts down and ends on time in the Simulator. **Built and unit-tested, not yet shown in the Simulator.** "Ends on time" is in `LiveActivitySharedTests` (expired at `endsAt` or when stale, with no countdown) and in `GlowModelTests`. The app and extension build. To show it: open a glow seeded to end in about 90 seconds, background the app, and screenshot the Dynamic Island before and after the end.
- [x] The Reduce Motion version works, and brightness is always restored. `BrightnessTests` covers six ways out (both met, End glow, Switch to chat, time ran out, the match ended, leaving the screen), and each one restores the person's own level with B6's controller. Reduce Motion: the pulse only fades, slower than once a second, never dimmer than 70% (`GlowSnapshotTests`). Snapshots cover every state at default and AX5.

**Still mocked**: the session token in Debug builds (`GlowDebugAccessToken`, as B2 does, until B1's live session lands; compiled out of Release). Live Activity push updates (For B5).

**Next wave needs**

- **D3, on real iPhones**: (1) Brightness: the glow screen goes to full brightness, and the person's own level comes back after We met, End glow, Switch to chat, time running out, Hide glow, going home, Control Center and a phone call. Try auto-brightness on and off. (2) Haptics: three soft beats when the glow starts, and again when they tap We met; nothing harsh. (3) In a bright, loud hall: can two people 10 to 20 m apart spot each other's color and read the word? Check all eight colors, especially Pearl and Sun under white lights, and the lock screen Live Activity at arm's length. (4) The screen never locks during a 15-minute glow, and does lock normally after it. (5) The pulse with Reduce Motion on and off: no flashing.
- **D4, strings**: "Your code word", "{Color} glow", "Meet at {spot}", "Hold your phone up. They're looking for this color too.", "We met", "Waiting for them", "Waiting for them to tap We met too.", "They tapped We met. Tap it when you've found each other.", "Couldn't reach Glow. Try again.", "Switch to chat", "End glow", "End the glow for both of you?", "Keep glowing", "You can still talk in the chat.", "Hide glow", "The glow keeps going. Find it again in Matches.", "Time left", "Getting your glow ready", "You found each other.", "The chat stays open.", "The glow has ended.", "Time's up.", "No rush. The chat is still open.", "This glow has ended.", "Your matches are where you left them.", "Can't reach Glow right now.", "Check your connection and try again.", "Something went wrong.", "Try again in a moment.", "Open chat", "Back to matches", "Try again". Live Activity: "Find each other", "Waiting for them to tap We met", "They tapped We met", "You found each other", "The glow has ended", "Time's up", "The chat is still open.", "Meet at {spot}", "Look for this color", "Code word: {word}".
- **D1**: `GlowView(matchID:)` refetches by ID. For end to end, start the glow via C2's `setChoice`, then drive We met or End glow with the API as person B.
### D5 · Demo and launch kit

_2026-10-24, Wave 3._ PR [#42](https://github.com/davidaxie/glow/pull/42) on `w3/d5-demo`. Everything is in [`docs/DEMO.md`](DEMO.md): the 3-minute script with timings, the fallback plan, the two rooms, stage setup, the dry-run checklist, the backup video's shot list, the first-50 plan with a Discord draft, pitch points and the Devpost draft.

**Built**

- `scripts/seed-demo.ts`: seeds a realistic room (default `demo`) on a local Supabase, or any with `--remote`: the room at `VENUE` with its meeting spots, 12 test people (`{slug}-{name}@glow.test`, "Test …" names, `test_data` metadata, adults, no profile photos, no taps), and a card each from the public-domain `outfit-real-*` crops, varied with sharp and stripped of metadata. Idempotent; `--refresh`, `--remove`, `--demo-mode`, `--slug`, `--print-venue`. Refuses non-local URLs without `--remote`, and any room not named "(test data)" (D5-D1).
- `server/tests/seed-demo/`: 14 unit tests (where it may run, options, the people are test data and adults, valid tags, cards for every gender and show me, fixed IDs, the venue fits the contract and matches `demo-room.env`, cards are small metadata-free JPEGs) and 6 integration tests on a local Supabase (`GLOW_INTEGRATION=1`, and CI).
- Decisions D5-D1 to D5-D9, including running the stage demo in its own test-data room (D5-D2).

**Proof** (D5's own stack, port 55351): both test files pass, 20 of 20 with integration on; `pnpm typecheck` and ESLint pass. A second seed run made 0 people and 0 cards. Through the real API on port 3125, the deck for Test Rowan and Test Quinn returned 5 cards each with only `id`, `image`, `tags`, `tappedByMe` (no names, emails or user IDs, P1), and `GET /api/admin/rooms/{demo}/metrics` answered `activeCheckins: 12`.

**Done when**

- [ ] Two full dry runs on real phones, on venue Wi-Fi. **Blocked**: needs the Apple Developer account, a TestFlight build, the cloud project and the venue. David's checklist: [`docs/DEMO.md`](DEMO.md#dry-runs-on-real-phones).
- [ ] The backup video is recorded. **Blocked**: needs the full loop on `main` (B1 #6, B3 #7, C1 #25, C2 #26, C3 #27, C4 #23). Shot list and commands in DEMO.md; D5 asks main before taking two Simulator slots.
- [x] The Devpost draft is ready (in DEMO.md, with what's real and what's simulated; not posted).

**Still mocked**: nothing. Card images in the seeded deck answer 501 until B3's #7 merges; the seed already stores them where B3's route reads them (`room-cards/{roomId}/{cardId}.jpg`).

**Next wave needs**

- **D1:** `scripts/seed-demo.ts --slug <yours>` gives an end-to-end run a crowd in a few seconds; `--remove` cleans it up.
- **D2:** the seed's guards are worth a look: non-local URLs, rooms not marked test data, `--remove` only deleting users with the seeded email and `test_data`.
- **Whoever records the backup video or runs the stage:** read "Rules on stage" and "Between runs" in DEMO.md (unmatch after each run; a fresh stage room slug per run, so the 3-tap cap can't bite).
### C4 · Chat

_2026-10-24, Wave 2._ PR [#23](https://github.com/davidaxie/glow/pull/23) on `w2/c4-chat`. Decisions C4-D1 to C4-D7.

**Built**

- **Server** (`server/src/server/chat`, routes in `server/app/api/matches/[id]/messages/` and `unmatch/`):
  - `GET /api/matches/{id}/messages`: a page oldest to newest (at most MESSAGES_PAGE_SIZE), paging back with `before` and `nextBefore`; pages never end inside a millisecond, so nothing is skipped or repeated (C4-D4). `fromMe`, never a sender; `clientId` only on my own messages. Messages B8's review flagged are hidden from the recipient (C4-D3). 409 `chat_not_open` while choosing.
  - `POST /api/matches/{id}/messages`: rate limit (A1's `route()`, B8's `messages` policy), 400 for a blank body, then `get_match` (404, or 409 while choosing) before the text goes anywhere, then B8's `moderateText`, then `send_message` (idempotent on `clientId`), then `message.created` to the recipient only (C4-D1, C4-D2). Timeouts `get_match` applies are announced (`settled`).
  - `POST /api/matches/{id}/unmatch`: `unmatch` ends the match and deletes the thread for both; then exactly what a block sends, `match.ended` to both and `deck.changed` to their rooms (C4-D6). 404 for anyone else and the second time.
- **FeatureChat** (`ChatView(matchID:)` for `Route.chat`): the thread with times after a pause and "Sent" under my latest message; instant sending (the message shows at once, then sent, or failed with "Tap to try again", resent with the same client ID so it can't arrive twice; a rejected message can be edited or deleted, not resent); a composer that counts like the server (UTF-16, MESSAGE_MAX_CHARS) with a counter near the limit; live updates from `events(for: matchID)` plus a refetch on foreground (C4-D7); paging back; a header menu with Report and Block (B8's sheets, `.report(.chat(id))` and `.block(.chat(id))`) and Unmatch (confirmed, then the Matches tab); states for loading, not open yet, ended ("This chat has ended.", no reason) and failed to load. Text shows verbatim: no Markdown, links, previews or suggestions (C4-D5). The tab bar hides inside a chat.
- **Tests**: server, 16 unit (paging edges, what each person sees, check order, flagged and pending, text never logged) and 15 integration against a real local Supabase (`GLOW_INTEGRATION=1`, `server/tests/chat/`): sign-in, 404 for strangers, blocked and unmatched people, 409 while choosing and the timeout that opens it, idempotent retries, moderation flagged and slow, review-flagged hiding, paging with several messages per millisecond, the rate limit, and an unmatch and a block sending identical events. iOS, 24 Swift Testing tests (model, layout, contrast, the `nextBefore` round trip for all 1,000 milliseconds) and 14 snapshots (7 screens at the default and largest text size).

**Done when**

- [ ] A message shows up on the other Simulator in under a second with the app open. **Waiting on B1/B5**: needs B1's live session (#6) and B5's live GlowRealtime (`w1/b5-push`). With local stand-ins for those two only (never committed: a test token, and supabase-swift `RealtimeClientV2` on the private `user:{id}` channel), the receiving Simulator had each message 21 to 79 ms after the server's broadcast ([recording](shots/c4-chat-live-and-unmatch-A.mp4)).
- [x] Someone blocked or unmatched can't send: 404 for both people after a block or an unmatch, tested against the real database (`chat.integration.test.ts`), and the app closes the thread.
- [x] Unmatching removes the thread for both people: `unmatch` deletes every message; both get `match.ended`; the other person's open chat cleared to "This chat has ended." 44 ms after the event in the recording.

**Proof**: [thread](shots/c4-chat-thread-A.png), [largest text](shots/c4-chat-thread-largest-text-A.png), [after the other person unmatched](shots/c4-chat-ended-after-unmatch-A.png), and a [16-second recording](shots/c4-chat-live-and-unmatch-A.mp4) of three messages arriving live and then the unmatch. Every state at both text sizes is in `ios/Packages/GlowKit/Tests/FeatureChatTests/__Snapshots__/`.

**Notes for D2: how messages are moderated and stored**

- **Path.** `POST /api/matches/{id}/messages` → A1's `route()` (Supabase token check, B8's rate limit of 30 a minute keyed by an HMAC of the user ID, body 1 to 1,000 UTF-16 units) → blank check → `get_match` (404 unless the sender is in a match that hasn't ended; 409 while choosing) → B8's `moderateText` (2.5 s; flagged is 422 and never stored; no answer is `pending` and goes through) → `send_message` (re-checks the match `FOR SHARE` in the insert's transaction, so a block or unmatch landing in between wins) → mark `passed` if it passed and the body is the one checked → `message.created` to the recipient (Realtime on their private channel, push text "New message").
- **Storage.** `public.messages` (id, match_id, sender_id, body, moderation `pending | passed | flagged`, client_id, created_at). Row level security with no policies: only the server's service role reads it, and the app has no Supabase client for tables. Every message of a match is deleted when it ends (unmatch, block, account deletion: `private.end_match`), except that a report first copies the reported person's last 20 into `reports.evidence` (D23). The app keeps messages in memory only, over an ephemeral, no-cache URLSession (D42).
- **Review.** B8's purge cron re-checks `pending` messages older than 15 s and sets `flagged` or `passed`; flagged ones then disappear for the recipient on the next fetch. The sender is never told (C4-D3).
- **Never logged.** No message text, user ID or match ID in server logs (a unit test spies on the logger), and app analytics carry only names, flags and counts (a test checks no text gets through).
- **Worth attacking.** Reading or sending with another pair's match ID (404); sending after a block or unmatch, or racing one (404, the lock); `clientId` replay across matches (the unique key is match, sender and client ID); `before` values at millisecond edges; Markdown or link text (shown verbatim); a flagged body to a closed or foreign chat (404 or 409 before moderation, so no 422 timing signal); the `pending` window, which by design delivers a message before its review.

**Still mocked**: nothing in C4's paths. The header shows "Chat" until C2's `GET /api/matches/{id}` is merged, then the first name. The live session and Realtime in the app are B1's and B5's, not merged yet.

**Next wave needs**

- **D1:** open a chat with `Route.chat(matchID)`; the model is `ChatModel` and `PreviewChatAPI` makes made-up threads for UI tests. A thread refetches on any Realtime event for its match.
- **D3:** on devices, check the composer above the keyboard, interactive keyboard dismissal, and the "New message" push opening the chat (B5's routing).
- **D4:** strings are in `ChatView.swift`, `ChatBubble.swift` and `ChatComposer.swift`; VoiceOver reads each message as "You, 8:15 PM: …" or "Sam, 8:15 PM: …", and failed ones offer Try again, Edit and Delete as actions.
### For B8

_From C2, 2026-10-24._ `setChoice` with Find runs a location check, like `joinRoom`. The route helper counts every `setChoice` against `api`; C2's handler also counts a Find against `join` itself (`rateLimit(user.id, 'join')`), so the Find check can't be used to probe a room's edge (C2-D5). If you'd rather map `setChoice` to `join` in `OPERATION_POLICIES`, say so here and C2 drops its own call. Nothing else needed.

### For C3

_From D1, 2026-10-24._ For the journeys: a root identifier starting `screen.FeatureGlow` on `GlowView` (`PushTapUITests` checks `glow_started` opens it), and identifiers on the code word (`glow.codeWord`) and We met (`glow.met`). The full loop finds them by text today: it checks A's screen shows the code word person B got from `GET /api/matches/{id}/glow`, and taps "We met".

_From C2, 2026-10-24._ **`startGlow`, proposed signature.** C2's `setChoice` calls it when `set_choice` answers `next: glow` with `reason: both_find`. Until yours lands, C2 calls `start_glow` through a thin stand-in, `server/src/server/choice/glow-start.ts`, with the same signature, and swaps in yours when it merges. Tell C2 here if you want it different.

```ts
// server/src/server/glow/index.ts (C3)
export type StartGlowOutcome =
  | { readonly result: 'started' }
  | { readonly result: 'chat'; readonly reason: 'not_checked_in' | 'no_code_word' | 'already_decided' }
  | { readonly result: 'waiting'; readonly reason: 'location_stale' | 'not_both_find' };

/** Calls start_glow with the word list, sends every event its result implies, and never throws
 *  for a match it can't start. Throws HttpError 404 for not_found. */
export async function startGlow(db: SupabaseClient<Database>, matchId: string): Promise<StartGlowOutcome>;
```

_Answered by C3, 2026-10-24:_ accepted as proposed, in `@/server/glow` (#27, merged). `set-choice.ts` imports it; C2's stand-in is gone.

The split C2 assumes: **`startGlow` sends every event `start_glow`'s result implies** (CONTRACTS.md, "start_glow results" and "Settled timeouts"): `glow.started` to both on `started`, `match.choice` to both on `chat`, `match.recheck` to each of `staleUserIds` on `waiting` with `location_stale`, and the `settled` entries (`glow.ended` for `glow_expired`, including other pairs' glows in the room, and `match.choice` for `choice_timeout`). C2's `setChoice` sends only what `set_choice` itself implies. After `startGlow`, C2 refetches the match with `get_match` and answers `next: glow` for `started`, `next: chat` for `chat`, and `next: waiting` (`other_location_stale`) for `waiting`.

## Status

### C2 · Mutual moment and reveal

_2026-10-24, Wave 2, in progress._ Draft PR [#26](https://github.com/davidaxie/glow/pull/26) on `w2/c2-match`.

**Routes into glow and chat (for C3 and C4).** FeatureMatch only ever passes a `MatchID`. Refetch everything else (`getGlow`, `listMessages`).

| When | FeatureMatch sends | Presented as |
| --- | --- | --- |
| The glow started: `setChoice` answered `next: glow`, or a refetch (after `match.choice` or `glow.started`) shows `status: glowing` | `navigate(.glow(matchID))` | Full screen. It replaces the mutual takeover. |
| The chat opened: `next: chat` (Just chat, they chose chat, the window ran out, someone left the room, no free code word), or a refetch shows `chatting` or `met` | `navigate(.chat(matchID))` | Closes any takeover and pushes onto the Matches tab |
| A row in the matches list | `choosing` → `.match(id)`, `glowing` → `.glow(id)`, `chatting` and `met` → `.chat(id)` | |

- **C3:** when a glow ends (We met, Cancel, Switch to chat, or time), FeatureGlow decides where to go; `navigate(.chat(matchID))` is the natural next screen. FeatureMatch doesn't listen for `glow.ended`.
- **C4:** a chat can open while the other person is still on the match screen; they get `match.choice` and FeatureMatch sends them to `.chat` too.
- **Notification taps** (B5's `RealtimeEvent.destination`): `match.created` → `.mutual`, `match.choice` and `match.recheck` → `.match`, `glow.started` → `.glow`. FeatureMatch's `.match` screen forwards to `.glow` or `.chat` if the match has already moved on, so a stale notification still lands in the right place, and it sends a stale Find again when both are on Find (the `match.recheck` push).

**Built**

- **`GET /api/matches/{id}`** (`server/src/server/choice/get-match.ts`): `get_match`, then the events for every `settled` timeout (`match.choice` or `glow.ended` to both). The reply is rebuilt from the contract's fields by name, so no user ID leaves (P1, D20); 404 for missing, not mine or ended (P11).
- **`POST /api/matches/{id}/choice`** (`set-choice.ts`, `find-check.ts`): Find checks a fresh fix with B2's `checkFix` and records pass or fail with `recordLocationCheck(… purpose: 'find')`, only after the match is known to be the caller's and only while the choice can still matter (C2-D1). Then `set_choice`, the events it implies (C2-D4), and on both Find, `startGlow` and a refetch. 422 `not_in_room`, `location_inaccurate` or `location_required`. Find also counts against B8's `join` limit (C2-D5).
- **FeatureMatch**: `MutualMomentView` (B6's `GlowTakeover(.bloom)`: two cards drift together with `.glowHaptic(.mutual)`, then the name, photos and the choice; Reduce Motion fades), `MatchView` (the same without the intro), the choice with one line each, the waiting panel with the 10-minute countdown and "Just chat instead", calm notes for outside the room, location off and offline, and `MatchesListView` (Now and Earlier, live). `.opensMutualMoments()` for the app root. `MatchModel` and `MatchesListModel` hold the logic; `APIMatchClient` is the API, `FixtureMatchClient` the Debug fixtures (C2-D9).
- **Tests**: server `tests/choice/routes.test.ts` (26, database faked: every reply, event and location row, P1, P2, P11) and `tests/choice/live.test.ts` (11, against the real `get_match`, `set_choice` and `start_glow`: Find and Find, Find and Chat, Chat and Find, Chat and Chat, both timeouts, a stale check, someone leaving, outside the room, 404s). iOS `FeatureMatchTests` (35: the model for every combination, rechecks, location denied, photos only after the match loads (P1), the API client's requests and errors, and snapshots of 6 screens at default and the largest text size).

**Proof**: two Simulators, Debug fixtures, the other person played by the fixture: [recording A](shots/c2-mutual-moment-A.mp4) (Find and Find, to the glow) and [B](shots/c2-mutual-moment-B.mp4) (Find, then they chose chat). Screens: the reveal ([A](shots/c2-reveal-A.png), [B](shots/c2-reveal-B.png)), waiting ([A](shots/c2-waiting-A.png)), after the choice ([glow](shots/c2-after-choice-A.png), [chat](shots/c2-after-choice-B.png)), the matches list ([A](shots/c2-matches-list-A.png)) and empty ([A](shots/c2-matches-empty-A.png)). Snapshots at both text sizes in `ios/Packages/GlowKit/Tests/FeatureMatchTests/__Snapshots__/`.

**Still mocked**

- Nothing in C2's paths is mocked any more: `startGlow` is C3's (`@/server/glow`, #27), match photos load through B3's `PrivateImageView(.matchPhoto(matchID, index:))` (watermarked, no cache, P4), and `settled` events go through B5's `notifySettled`.
- **The real two-phone reveal** needs B1's live session (not merged yet). The recording shows both phones from Debug fixtures. FeatureMatch opens the takeover the moment `match.created` arrives from B5's live Realtime.

**Next wave needs**

- **D1**: launch a Debug build with `-GlowMatchFixtures reveal` (and `-GlowMatchFixturesChoose find`) to drive the takeover without a server; `reveal-chat`, `waiting`, `list` and `empty` too.
- **D4**: every string is in `MatchViews.swift`, `Match/ChoicePanel.swift`, `Match/MatchPhotoCarousel.swift` and `List/MatchesListView.swift`. Names are `Text(verbatim:)`, never localized.
- **D2**: `getMatch` and `setChoice` replies never carry `userIds`, `recheckUserIds`, `settled`, `lastMessageAt` or the glow's `matchId` and `roomId` (`publicMatch` in `shapes.ts`).

**Decisions**: C2-D1 to C2-D9 in `docs/DECISIONS.md`.
_From B1, 2026-10-24, PR #6 (cross-owner in `ios/GlowUITests/`)._ (1) `LaunchUITests` now launches with `-GlowPreviewSession ready`: with the live session a fresh app starts signed out, so the shell tests use the preview session. (2) New `OnboardingUITests`: P10's UI test (an under-18 birthday stops at the kind message, and stays stopped after a relaunch; no backend needed) and a test sign-in run to the tabs (skips without a local server with `ALLOW_TEST_LOGIN`). They're yours from Wave 3; the launch arguments they use are listed under B1 in Status.

## Status

### B1 · Sign in and onboarding (iOS)

_2026-10-24, Wave 1._ PR [#6](https://github.com/davidaxie/glow/pull/6) on `w1/b1-onboarding` (the session interface went first in [#8](https://github.com/davidaxie/glow/pull/8); the code-only email template is cross-owner [#11](https://github.com/davidaxie/glow/pull/11) for A2). From first launch to a finished 18+ profile: welcome, sign in, about you, photos, notifications.

**Built**

- **Server**: merged in #50 (see "B1 · Sign in and onboarding (server)" above).
- **iOS Session**: `LiveSessionService` on supabase-swift Auth. Email code (`signInWithOTP` + `verifyOTP(.email)`), Sign in with Apple through the ID token (no scopes, B1-D3), Debug-only test sign-in (`#if DEBUG`, hand-written request), restore at launch with `GET /api/me`, offline fallback to the last step only, 401 signs out, Supabase ending the session signs out. The session is in the Keychain on this device only, and a fresh install starts signed out (B1-D5). Shared by onboarding and Settings: `ProfileClient` (every `/api/me` call, mapped to `ProfileError`), `ProfileForm` (fields, the neutral 18+ check, `AgeGateLock`), `PhotoSlots` and `ProfilePhotoPreparer` (4:5 crop, 1920 px, sRGB, JPEG 0.8, no metadata), `AgeGate` (the same UTC-12 rule as the server, D24).
- **iOS FeatureOnboarding**: Welcome (three lines, the last the privacy promise), Sign in (Apple, or email), email and code entry (paste or the keyboard's suggestion signs in), About you (step 1), the under-18 screen (kind, no way forward but Sign out, B1-D2), photos (step 2, "Being checked" for held photos), notifications (step 3: `push.requestAuthorization()`, and "Not now" finishes too).
- **iOS FeatureSettings**: Settings (name and viewer code, Edit profile, Edit photos, Pause and Delete account open B8's screens, Sign out calls `push.unregister()` first), Edit profile, Edit photos.
- **Supabase** (cross-owner, #11): magic link and confirmation emails send the 6-digit code and no link (B1-D4).

**Proof**: Simulator screenshots from `OnboardingUITests` (Glow A (B1), local server on 3101 and B1's own stack, email code and test sign-in both reaching the tabs): [welcome](shots/b1-welcome.png), [sign in](shots/b1-sign-in.png), [email](shots/b1-email.png), [code](shots/b1-code.png), [about you, empty](shots/b1-profile-empty.png) and [filled](shots/b1-profile-filled.png), [under 18](shots/b1-under-18.png), [photos](shots/b1-photos-empty.png) and [one added](shots/b1-photos-added.png), [notifications](shots/b1-notifications.png), [the tabs](shots/b1-tabs.png), [Settings](shots/b1-settings.png), [Edit profile](shots/b1-edit-profile.png), [Edit photos](shots/b1-edit-photos.png), and the largest text size ([welcome](shots/b1-welcome-largest-text.png), [about you](shots/b1-profile-largest-text.png)). Snapshot tests cover every screen at the default and largest text size. To redo the screenshots: `TEST_RUNNER_GLOW_SHOTS_DIR=$PWD/docs/shots TEST_RUNNER_GLOW_MAILPIT_URL=http://127.0.0.1:<your Mailpit port> scripts/sim.sh test ui`.

**Tests**: server `tests/profiles/` (age rule, state machine, metadata stripping, and every route against a live local Supabase: 401, 404 for someone else's photo, under-18 stores nothing, held photos never finish, rejected and outage store nothing, last photo, replace, test sign-in's locks); iOS `SessionTests` (sign-in input, the session's states, 401, offline, sign-out, the profile client's error mapping, the form's 18+ check never calling the API, the photo preparer dropping GPS and camera data), `AppCoreTests/SessionServiceTests`, and snapshot tests of every onboarding screen at the default and largest text size (`FeatureOnboardingTests`), plus Settings' forms.

**Still mocked**: nothing in B1's paths. Sign in with Apple is built but **blocked: needs Apple Developer account** (and the Supabase Apple provider, below); it can't complete in the Simulator. Rate limits come from A1's route helper (B8's policies).

**How other modules get the signed-in person and their profile**

```swift
@Environment(\.dependencies) private var dependencies

for await me in dependencies.session.profiles() {     // the current value first, then every change
    // me?.profile.firstName, me?.profile.paused, me?.isAdmin, me?.onboardingStep; nil when signed out
}
let me = await dependencies.session.currentProfile()
try await dependencies.session.refreshProfile()        // after changing something about yourself
let id = await dependencies.session.currentUserID()    // only for Realtime's user:{id}
for await state in dependencies.session.states() { … } // .signedOut, .onboarding(step), .ready
```

`Me` is `Components.Schemas.Me`. In previews and tests: `PreviewSessionService(state: .ready, profile: .preview(step: .complete, paused: true))`. On the server, `assertOnboardingComplete(user.id)` from `@/server/profiles` answers 409 `onboarding_incomplete` until onboarding is done.

**Running it on the Simulator**

- `ALLOW_TEST_LOGIN=1` in `server/.env.local` (`pnpm env:setup --test-login`), then launch with `-GlowDebugTestLogin alex@glow.test` (onboarded) or `new@glow.test` (starts at the profile step), or use the Debug test sign-in panel on the sign-in screen. `-GlowSignOutAtLaunch YES` starts signed out; `-GlowResetAgeGate YES` reopens the profile step after an under-18 answer on that Simulator.
- The email code: on a stack started with this branch's `supabase/` (`scripts/agent-env.sh <ID> --own-db`), the code is in that stack's Mailpit. The shared `glow` stack keeps sending links until it restarts with #11.

**Next wave needs**

- **B2:** delete `DebugAccessTokenFallback`: the live session gives the API a real token now.
- **C1 to C4:** sign each Simulator in with `-GlowDebugTestLogin alex@glow.test` and `-GlowDebugTestLogin blake@glow.test` (both onboarded, but seeded with no photos: add one through Settings → Edit photos or `POST /api/me/photos` so matches have something to show).
- **D1:** UI test hooks: `onboarding.getStarted`, `signIn.email`, `signIn.apple`, `signIn.test.email`, `signIn.test.button`, `email.field`, `email.send`, `code.field`, `code.verify`, `profile.firstName`, `profile.birthday`, `profile.gender.<woman|man|nonbinary>`, `profile.showMe.<…>`, `profile.continue`, `underAge.signOut`, `photos.slot.<0-2>`, `photos.remove.<n>`, `photos.continue`, `notifications.allow`, `notifications.skip`, `settings.editProfile`, `settings.editPhotos`, `settings.signOut`, `settings.signOut.confirm`.
- **B9:** sign-in works on `main` once #6 merges (email code and test sign-in); Apple waits on the account.
### D1 · Integration and end-to-end tests

_2026-10-24, Wave 3._ PR [#43](https://github.com/davidaxie/glow/pull/43) on `w3/d1-e2e` (draft until B1's session is in). `integration` PRs: [#44](https://github.com/davidaxie/glow/pull/44) (merged: the last stand-ins swapped for B3's and B5's modules, and `GET /api/matches` sends `settled` through B5's `notifySettled`) and [#47](https://github.com/davidaxie/glow/pull/47) (merged: a tapped notification crashed the app). Decisions D1-D1 to D1-D6.

**Run any journey with one command** (after `eval "$(scripts/agent-env.sh <ID>)"`, with `pnpm env:setup --force --test-login` done once):

| Journey | Command | What it proves |
| --- | --- | --- |
| Full loop | `scripts/e2e/run.sh full` | A checks in, B taps first (secret), A's tap is mutual, both choose Find, A shows the code word B got, both tap We met |
| Chat | `scripts/e2e/run.sh chat` | mutual, Just chat, a message each way (B's shows on A's screen; A's reaches B) |
| Block | `scripts/e2e/run.sh block` | mutual, chat, A blocks from the chat menu; B's match leaves the list and answers 404 (P7) |
| Check-in expiry | `scripts/e2e/run.sh expiry` | A checks in, the check-in runs out (harness + purge cron), the deck says so and offers Check in again |
| Push taps | `scripts/e2e/run.sh push` | every `ios/fixtures/push/*.apns` banner, tapped, opens its screen (B5's request) |
| All of them | `scripts/e2e/run.sh all` | |
| 10 in a row | `scripts/e2e/run.sh full --repeat 10` | stops at the first failure |
| Two-Simulator recording | `scripts/e2e/record.sh [journey]` | Glow A driven by the journey, Glow B signed in as person B; `docs/shots/d1-e2e-<journey>.mp4` side by side |

`run.sh` builds the app for your API (`--no-build` to skip), starts `pnpm dev` on your port if nothing answers there, boots Glow A (and Glow B only with `--record`), stands it at the venue, makes a room and person A of the run's own, starts person B and the harness, runs the journey's XCUITest class, and ends the room. Logs per run in `.agent-state/e2e/`. Person B on their own: `node scripts/e2e/player-b.ts --help`.

**Built**

- `scripts/e2e/player-b.ts`: person B through the API. Test sign-in (B1's route), join with a fix at the room's centre, check in with an `outfit-real-*` fixture, wait for a card and fetch its signed image (P4), tap, wait for the match, Find or Just chat, wait for the glow, We met, wait for both, say, read, block, unmatch, wait for the end, leave. Runs a list of steps (`--steps`), or takes them one at a time from a UI test (`--control PORT`). Every reply is checked for A's user ID and, outside the match routes, A's first name (P1, D1-D3).
- `scripts/e2e/harness.ts`: a fresh room (`room`, through B7's admin API), a fresh onboarded person (`person`), the end of a room, a check-in expiry plus the purge cron (`expire`), and `serve`, the Mac-side helper UI tests call for `simctl push` and expiry.
- `scripts/e2e/glow.ts`: the shared client, typed from the generated contract (`server/src/contracts/openapi/types.gen.ts`), local servers only.
- `scripts/e2e/run.sh` and `scripts/e2e/record.sh`, above.
- `ios/GlowUITests/E2E/` (config, player B and harness clients, the Glow A driver) and `ios/GlowUITests/Journeys/` (one class per journey). Without run.sh's environment each journey skips with a note, so `scripts/sim.sh test` stays green (D1-D5).
- Tests: `node --test scripts/e2e/glow.test.ts` (the privacy watch, local-only guard, addresses, steps); `(cd server && node_modules/.bin/tsc -p ../scripts/e2e)`.

**Found and fixed**

- Tapping any notification crashed the app (SIGABRT in UIKit, from the async `userNotificationCenter(_:didReceive:)`): fixed in #47. `PushTapUITests` passes on all nine fixtures with it.

**Proof**: each journey has passed once, on Glow A (D1) against a local server, with B1's iOS session on main: `full` (61 s), `chat` (64 s), `block` (72 s), `expiry` (51 s) and `push` (87 s, nine banners). The full loop drives the real screens: check in with the test photo, the deck, That's them, the secret tap, mutual, Find each other, the same code word as person B's, We met, and B sees `met`. Person B is another API client, and its privacy watch saw no user ID or name. **Ten in a row**: `scripts/e2e/run.sh full --repeat 10` passed 10 of 10 on a fresh build of main 402aaf9 (20 minutes). **Recording**: [`docs/shots/d1-e2e-full.mp4`](shots/d1-e2e-full.mp4), 54 seconds, Glow A (driven by the journey) on the left and Glow B (signed in as person B) on the right, from check-in to the same glow on both phones to We met; recorded headless with `simctl` (`scripts/e2e/record.sh full`).

**Still mocked or blocked**

- Nothing is mocked. Setup uses only B1's real routes; the service role is used only to end a check-in early for the expiry journey (D1-D2).
- Push taps are judged by `screen.<Module>` identifiers where they exist and by the screen's words where they don't (C2, C3 and C4 haven't added identifiers; For C2, C3 and C4).
- Actions is down, so nothing runs in CI yet (For A1: `--e2e`).
- **Not run by anyone: the denied-location path.** Every journey grants location (`run.sh` installs the app, then `simctl privacy grant`, D1-D8), so the "Don't Allow" answer and the approximate-only path have never been run against the app. B2's unit tests cover the failure screens; nothing drives them end to end.

**Done when**

- [x] The full loop passes 10 runs in a row, locally (10 of 10). In CI: blocked, Actions is down (A1's `--e2e`, For A1).
- [x] No flaky tests. One flake found and fixed (the third run of a ten-run check got 429 on test sign-in, D1-D7). Journeys wait on conditions, never on time, and each run has its own room and people.
- [x] A recording of the two-Simulator run is in `docs/shots/d1-e2e-full.mp4`.

**Next wave needs**

- **Everyone with a screen in a journey:** keep the identifiers the journeys use stable (For C1 to C4), or tell D1.
- **D2:** player B's privacy watch runs on every journey; `--watch-user` and `--watch-name` take more values if you want other strings watched.
- **D3, D5:** `scripts/e2e/record.sh` makes the side-by-side clip for the demo once the loop runs.

### B9 · Release and TestFlight

_2026-10-24, Wave 1._ PR [#5](https://github.com/davidaxie/glow/pull/5) on `w1/b9-release`, plus the `cross-owner` signing change in `ios/project.yml` (PR [#17](https://github.com/davidaxie/glow/pull/17), merged). The manual is [`docs/RELEASE.md`](RELEASE.md).

| | |
| --- | --- |
| Public TestFlight link | none yet (blocked: needs Apple Developer account) |
| Latest build | none yet. Update this row after every release. |
| External beta review | not submitted (blocked: needs Apple Developer account, then sign-in from B1 and room joining from B2 on `main`) |

**Built**

- `ios/fastlane/`: the `beta` lane (TestFlight build number + 1, archive the Release configuration with manual App Store signing, check the exported app, upload with the App Store Connect API key, set What to Test), plus `external` (Public group, beta review submission with the review notes and test information), `status` (latest build, review state, public link), `check` and `verify_release` (no Apple account needed), `privacy` and `privacy_answers`. Helpers are plain Ruby in `glow_release.rb` with 33 unit tests in `test/`.
- `ios/fastlane/ship`: one command for all of it. `ios/fastlane/ship release` tags `main` and CI ships it.
- `.github/workflows/release-ios.yml`: `beta` on `beta-*` and `wave-*-done` tags or by hand (also `external` and `status`). It skips cleanly, with a notice and a job summary saying "blocked: needs Apple Developer account", while the API key secrets are missing. PRs touching release files run the tests and `fastlane check` on Ubuntu.
- The release gate (B9-D3): `beta` refuses non-anon Supabase keys, PostHog personal keys, local endpoints and the placeholder domain before building, and after building refuses an app with Debug-only Info.plist keys, ATS exceptions, non-production push, wrong Associated Domains, secrets, the test sign-in route or `GlowDebug` launch arguments in any file.
- App Privacy answers from `ios/Glow/PrivacyInfo.xcprivacy`, as data (`ios/fastlane/app-privacy.json`, checked against the manifest in CI) and as a click-through table in RELEASE.md. Beta texts in `ios/fastlane/testflight/`. A privacy policy draft in RELEASE.md.
- `docs/RELEASE.md`: shipping with one command, what the lane refuses, David's Apple setup click by click (bundle IDs, capabilities, APNs key and where it goes, certificate, profiles, app record, API key, secrets, internal group, external review, public link, Associated Domains on a device), where the web domain goes, signing, adding Sentry back, and fixes for common failures.

**Proof (local, Xcode 26.0.1, no Simulators used).** `ios/fastlane/ship test`: 33 runs, 114 assertions, 0 failures, 0 skips. `ios/fastlane/ship check`: passes and lists what `beta` still needs. `ios/fastlane/ship verify_release`: an unsigned Release device build passes every check that doesn't need signing (placeholder domain and empty Supabase values show as warnings). A Release build with a test `-xcconfig` override put build 42 in both the app and the Live Activity and the hosted Supabase URL in the Info.plist. `ios/fastlane/ship beta` and `status` without credentials stop with the list of blocked items. With #17: `-showBuildSettings` gives Manual + Apple Distribution + both profiles for Release device builds only, a Release Simulator build succeeds, and a signed Release device build asks for the team and the "Glow App Store" profile.

**Done when**

- [ ] `fastlane beta` uploads a build that installs from TestFlight on a real iPhone. Blocked: needs Apple Developer account (Needs David, item 11, steps 1 to 9). The lane, workflow and checks are built and tested up to the first Apple call.
- [ ] Push works on a TestFlight build, through production. Blocked: needs Apple Developer account (the APNs key, step 3) and B5's sender. Release builds carry `aps-environment = production` (#17).
- [ ] The public TestFlight link is approved, or the review status is in `docs/HANDOFFS.md`. Blocked: needs Apple Developer account. Status is in the table above; the `external` lane submits the review.
- [x] `docs/RELEASE.md` explains how to ship a new build with one command: `ios/fastlane/ship release`.

**Still mocked or blocked**: nothing in B9's paths is mocked. Everything that talks to Apple is blocked on the account; the hosted Supabase values on the Supabase cloud project; the domain on David's choice.

**Next wave needs**

- **Everyone:** to get a build onto phones, merge to `main` and run `ios/fastlane/ship release` (once the account exists). Testers get it in TestFlight minutes later.
- **B1, B2:** tell B9 here when sign-in and room joining work on `main`, so the first external review goes in (Build plan: Apple's review runs while everyone keeps building).
- **B2:** the `/r/{slug}` page shows `TESTFLIGHT_URL` and the link file lists `APPLE_APP_ID` (A1's variables); David sets both in Vercel (RELEASE.md steps 11 and 12).
- **D2, D3:** TestFlight builds go through the release gate above; `ios/fastlane/ship verify_release` reproduces it locally on an unsigned build.
- **Anyone changing `project.yml`, `Info.plist`, entitlements, the xcconfigs or the privacy manifest:** run `ios/fastlane/ship check` and `ios/fastlane/ship verify_release`.

### B2 · Rooms and joining

_2026-10-24, Wave 1._ PR [#10](https://github.com/davidaxie/glow/pull/10) on `w1/b2-rooms`. From a QR code to a verified spot in the room: on the Simulator, `scan demo` to check-in takes about a second.

**Built**

- `server/src/server/rooms`: `resolveRoom` (code, or slug plus token, to the room's summary; 409 `onboarding_incomplete`, 404 for anything wrong), `joinRoom` (the location check, then a JOIN_TICKET_TTL join ticket), `leaveRoom` (ends my check-in, deletes my card photo, sends `deck.changed`), `getRoomState` (`get_room_state` plus a fresh signed link to my own card), the link file and the `/r/{slug}` page. Join checks in an order that leaks nothing (B2-D5), and a live room past its end reads as ended.
- `server/src/server/geo`: `checkFix` (distance minus the smaller of accuracy and GEO_ACCURACY_CREDIT, within the radius; edge counts as inside; worse than GEO_MAX_ACCURACY is `inaccurate`), `accuracyBucket`, and `recordLocationCheck`, which keeps only person, room, purpose, result and bucket (P2).
- `server/src/server/qr`: poster tokens (only with `allow_static_qr`) and rotating screen tokens, constant time, current and previous window, no early exit (B2-D2). `displayToken(qrSecretHex, nowMs)` for B7.
- `server/src/server/rooms/ticket.ts`: encrypted join tickets (B2-D1), `issueJoinTicket` and `verifyJoinTicket` (For B3 above).
- iOS **Location**: `LiveLocationService` (CoreLocation, When In Use, temporary full accuracy with the `RoomCheck` purpose key, one fresh fix within LOCATION_FIX_TIMEOUT, updates off straight after) and `FixSelector` (takes 25 m at once, 65 m from 3 s, 100 m from 6 s, else the best usable fix at the limit; ignores cached and invalid fixes). `LocationError` gained `.approximateOnly`; `PreviewLocationService` takes an error, a delay and what a permission request grants.
- iOS **FeatureRooms**: `RoomsHomeView`, `RoomScannerView` (AVFoundation QR only, torch, "type the code" fallback, camera-off and no-camera screens), `RoomCodeEntryView` (6 characters, look-alikes dropped as you type), `RoomJoinView(link:)` and `JoinFlowView`, driven by `JoinModel`: resolve, then location, then join, then `navigate(.checkIn(roomID, ticket))`. Failure screens for not in the room, weak signal, room ended, paused or not open yet, wrong code, screen code changed, location off, precise off, offline and rate limited, all in DesignSystem type and colors.
- Tests: server, 5 files and 123 tests (`tests/geo`, `tests/qr`, `tests/rooms`) including the radius edge to the millimeter, both token windows and their boundaries, tickets, every route's 401, 404, 409 and 422, and `p2-no-coordinates.test.ts` (logger spy before redaction, console, error reports, database writes and replies, plus a column audit of the database types). iOS: `FeatureRoomsTests`, 28 tests (join flow, server answer mapping, codes, screens) and `LocationTests`, 13 tests (FixSelector, redaction, the mock).

**Proof** (Glow A (B2), local server on 3102, shared database): [at venue then scan demo reaches check-in](shots/b2-venue-reaches-checkin-A.png), [at away shows not in the room](shots/b2-away-not-in-room-A.png), [wrong code](shots/b2-wrong-code-not-found-A.png), [a link with no code](shots/b2-link-without-code-A.png), [Rooms home](shots/b2-rooms-home-A.png), [the code typed](shots/b2-room-code-typed-A.png) then [check-in](shots/b2-room-code-reaches-checkin-A.png), [the scanner on a device with no camera](shots/b2-scanner-no-camera-A.png), the largest text size ([not in the room](shots/b2-away-not-in-room-largest-text-A.png), [home](shots/b2-rooms-home-largest-text-A.png)), and a [recording of both flows](shots/b2-join-venue-then-away-A.mp4).

**Running it on the Simulator** until B1's session lands: the preview session has no access token, so Debug builds of FeatureRooms fall back to a `GlowDebugAccessToken` user default. Make an onboarded `@glow.test` person on the local Supabase, sign in with a password to get a token, then `xcrun simctl spawn <udid> defaults write com.davidxie.glow GlowDebugAccessToken <token>`. Answer the location prompt once (or `xcrun simctl privacy <udid> grant location com.davidxie.glow`). Then `scripts/sim.sh at venue A` and `scripts/sim.sh scan demo A`.

**Still mocked**

- `server/src/server/rooms/stand-ins.ts`: `sendDeckChanged` broadcasts straight to Realtime (B5's `notifyRoom` replaces it when #15 merges) and `signedCardImage` signs per CONTRACTS.md (B3's signer replaces it). Rate limits are real: A1's route helper limits resolve, join and leave with B8's `join` policy.
- `DebugAccessTokenFallback` in `FeatureRooms/Joining/RoomsServices.swift`, Debug only, until B1's Supabase session exists. B2 deletes it then.

**Next wave needs**

- **C1 (room home):** the current room and my check-in come from `try await dependencies.api.perform { try await $0.getRoomState(path: .init(id: roomID.rawValue)) }`: `room` (name, status, times), `checkin` (card ID, tags, `visible`, `expiresAt`, a 60-second image link to my own card) when I'm checked in, and `tapsLeftToday`, `viewsLeftToday`. A 404 means the room is gone. The Leave button calls `leaveRoom(path: .init(id:))` (always 204 for a room that exists), and the server sends `deck.changed` to everyone else. `RoomInfo` (FeatureRooms) isn't shared: features don't import each other, so map the generated `RoomSummary` yourself. If the room home should survive a relaunch, keep only the room ID, and only until the check-in's `expiresAt` (a room ID is a place someone was).
- **B3:** `CheckInView(roomID:ticket:)` gets the ticket from the join flow; send `ticket.rawValue`. A 422 `join_ticket_invalid` should send the person back through `.joinRoom` (the ticket lasts 10 minutes).
- **C2 (Find):** on the server, `checkFix` then `recordLocationCheck(db, { …, purpose: 'find' })` from `@/server/geo`, before `set_choice`. In the app, `dependencies.location.requestAuthorization()` then `currentFix(timeout: .seconds(GlowConstants.locationFixTimeout))`, and map `LocationError` the way `JoinFailure.init(_: LocationError)` does.
- **B7:** the display page's token is `displayToken(room.qr_secret, Date.now())` from `@/server/qr`; posters use `static_qr_token` and need `allow_static_qr`.
- **B9:** B2 tells you under For B9 once room joining is on `main` (Build plan's first external review).
- **D1:** UI test hooks: `rooms.home.scan`, `rooms.home.code`, `rooms.code.field`, `rooms.code.join`, `rooms.join.progress`, `rooms.join.passed`, `rooms.join.failure.<reason>` (for example `rooms.join.failure.not_in_room`), `rooms.scanner`, `rooms.scanner.torch`. `LaunchUITests.testRoomLinkOpensTheJoinScreen` still finds "Room: demo": the join screen shows the slug until the room's name arrives, and keeps it on failure screens.
### B7 · Admin and room ops

_2026-10-24, Wave 1._ PR [#16](https://github.com/davidaxie/glow/pull/16) on `w1/b7-admin`.

**Built**

- **Admin sign-in** (`/admin/sign-in`): a 6-digit email code from Supabase Auth, the session in httpOnly cookies, checked against `admins` on every page and action. Anyone who isn't a signed-in admin gets the same 404 page as a missing address, everywhere under `/admin`, on `/display/{slug}` and on `/api/admin/*` (B7-D1). Locally, with `ALLOW_TEST_LOGIN`, a "Sign in as admin@glow.test" button skips the email (B7-D9).
- **Rooms** (`/admin`, `/admin/rooms/new`, `/admin/rooms/{id}`): create from a phone with a name (the link name follows it), "Set center to my location", a radius slider on a MapLibre map with OpenStreetMap tiles and full attribution, three meeting spots filled in (3 to 5, editable), and start and end times (now to 12 hours from now). Room page: pause, resume, end, reopen, demo mode (with today's count of skipped location checks), printed posters on or off, a new poster code, meeting spots renamed in place (an active glow keeps its spot), and every detail editable.
- **Poster** (`Poster (PDF)` on the room page, `GET /api/admin/rooms/{id}/poster`): US Letter, a 4.4-inch QR code of `https://{DOMAIN}/r/{slug}?t={static token}`, the room code, three steps, and two lines of reassurance. Black on white, no location, no metadata about who printed it.
- **Display screen** (`/display/{slug}`, admins only, B7-D2): one full-screen QR code that changes on every QR_ROTATION boundary by the server's clock, a bar counting down to the next code, the room code underneath, keeps the screen awake, a Full screen button. Paused, ended and not-yet-started rooms show a sentence, never a code.
- **Cards** (`/admin/rooms/{id}/cards`): open check-ins newest first, by tags and watermark code; "Show photo" loads it watermarked with the admin's own code (B7-D6); Remove card (hides it, deletes the photo, they can check in again) or Remove from room (also ends the check-in).
- **Reports** (`/admin/reports`): open, acted on and dismissed tabs, oldest first, people named only by watermark code, details and the kept chat evidence. Dismiss, Remove card (the card reported, or the reported person's card in that room for chat and match reports), Ban (B7-D5).
- **Screenshot flags** (top of `/admin/reports`): people with B8's CAPTURE_REVIEW_THRESHOLD (3) or more deck screenshots or recordings in 24 hours (B8-D7), by watermark code and count, with Ban. The ban is looked up by watermark code on the server, so no user ID reaches the browser.
- **Held profile photos** (`/admin/photos`): photos moderation held back (often a possible minor), oldest first, by watermark code; "Show photo" with the admin's watermark; Approve, Reject (deletes the image and row), Ban (also bans the owner). Only held and pending photos are ever listed or opened (B7-D11).
- **Live numbers** (`/admin/rooms/{id}/metrics`): checked in now, joins, cards viewed, matches, glows started, We met, reports, since the start of the room's day, refreshed every 10 seconds. No taps, ever (B7-D7).
- **API**: all 17 `/api/admin/*` operations (including A2's three held-photo ones), through A1's route helper, with the logic in `server/src/server/admin/` shared with the admin web's server actions.
- **Tests** (`server/tests/admin/`, 113): every admin route answers the same 404 to a signed-in non-admin, before reading anything and whatever they send, and works for an admin; room rules (409 `slug_taken`, spots, times, timezones, ending and clamping check-ins, deck.changed); screen tokens against an independent HMAC; the QR decodes back to the link; the poster; the room day across time zones and DST; card removal, reports, the ban order, screenshot flags, held photos; the watermark strips metadata; and the server's web domain equals the app's.

**Proof** (all in `docs/shots/`): [printed poster](shots/b7-poster.png) and [its QR opening the app](shots/b7-poster-opens-app-A.png) on "Glow A (B7)" (PDF rasterized, QR decoded, link handed to the app as `sim.sh scan` does; run once before the Simulator cap, and re-checked in the coordinator's Checkpoint 2 run), [display screen](shots/b7-display-screen.png) and [its QR opening the app](shots/b7-display-opens-app-A.png), [new room on a phone](shots/b7-admin-new-room-phone.png), [rooms](shots/b7-admin-rooms.png), [room](shots/b7-admin-room.png), [room controls](shots/b7-admin-room-controls.png), [cards](shots/b7-admin-cards-phone.png), [reports](shots/b7-admin-reports-phone.png), [live numbers](shots/b7-admin-metrics.png), [held photos](shots/b7-admin-photos.png). Checked live on port 3107 against the shared stack: admin 200, signed-in non-admin 404 (also with `scripts/smoke.sh` and a throwaway token), no token 401 on every route; every `/admin/*` address, real or not, gives a non-admin the identical 404 page; the display's code changed exactly on the 30-second boundary; a live `joinRoom` with the display's current token answered 200 (a made-up token, 404), and B2's `verifyRoomToken` accepts the display's token now and in the next window and refuses it after.

**Still mocked**: B3's watermark (#7), in `admin/watermark.ts`; B7 swaps to B3's when #7 merges. The display uses B2's real `displayToken` from `@/server/qr`.

**Room setup at the venue (for D5)**

1. On your phone, open `https://{DOMAIN}/admin/sign-in`, enter your email, then the 6-digit code from the email. (You must be in `admins`; see Needs David.)
2. Rooms, then **New room**. Type the room's name. Stand in the middle of the venue and tap **Set center to my location**; drag the pin if it's off. Slide the radius until the circle covers the venue and no more. Check the three meeting spots (rename them to real places: "Main entrance", "Bar", "Stage left"). Times default to now until 12 hours from now. Turn on **Printed posters** if you'll print any, and **Demo mode** if stage phones will join from somewhere other than the venue. Tap **Create room**. About a minute.
3. On the laptop by the stage: sign in there too, open the room, tap **Open display screen**, then **Full screen**. The code changes every 30 seconds by itself; leave the tab open and the laptop plugged in.
4. Posters: on the room page tap **Poster (PDF)** and print at 100%. If a poster is lost or photographed and shared, tap **Make a new poster code** and reprint (old posters stop working).
5. During the event: **Live numbers** for the room, **Reports** for the queue, **Cards in the room** to remove a card or a person. **Pause room** hides every card until you resume; **End room** ends every check-in and deletes every card photo at once.
6. Afterwards: End the room, then **Sign out** on every device, including the display laptop.

**Next wave needs**

- **D1:** the room for an end-to-end run can be made with `POST /api/admin/rooms` and an admin token (locally, `admin@glow.test`). `GET /api/admin/rooms/{id}/display-token` returns the current screen token and link.
- **D2:** please try the admin area as a non-admin: every page, action and `/api/admin` route should be the same 404. Server actions are public POST endpoints; each one checks the session itself (`adminAction()` in `server/src/server/admin/web.ts`).
- **D5:** room setup steps above. The demo room for the stage needs Demo mode on.
- **Whoever owns {DOMAIN}:** change `WEB_DOMAIN` (`server/src/server/admin/links.ts`) together with `GLOW_WEB_DOMAIN` in the app, or `WEB_DOMAIN` in env.ts once A1 adds it.

**Decisions**: B7-D1 to B7-D11.
### C1 · Deck experience

_2026-10-24, Wave 2._ PR [#25](https://github.com/davidaxie/glow/pull/25) on `w2/c1-deck` (FeatureDeck only). The Debug launch route and the deck UI tests are in a small `cross-owner` PR for A1 and D1, [#39](https://github.com/davidaxie/glow/pull/39) (see For A1 and For D1).

**Built** (`ios/Packages/GlowKit/Sources/FeatureDeck`)

- **Room home** (`RoomHomeView(roomID:)`): the room's name, my check-in and time left (refreshed every 30 s and on `checkin.expiring`), a Visible toggle (`POST /api/me/pause`, which pauses me in every room, C1-D9), See today's looks, Check in again (`.joinRoom(RoomLink(slug:, token: nil))`, C1-D8), and Leave (confirm, `POST /api/rooms/{id}/leave`, leave the room channel, back to Rooms). States: checked in, card removed by hosts, check-in ended, room ended or paused, loading, failed.
- **What did you notice** (a sheet the deck opens first): who (only genders in my show me; left out when there's one), top color, hair length, hair color and extras, B6's `GlowTagPicker`, all optional. Show looks, Skip (show everyone), Clear. Nothing is fetched until it's answered (C1-D1).
- **The deck** (`DeckView(roomID:)`): a two-column grid of B6's `GlowCardTile` (one column at accessibility text sizes), my viewer code drawn over every photo as well as the server's watermark (C1-D10), pull to refresh, paging as you scroll (DECK_PAGE_SIZE), "N new looks left today" at the end, and What did you notice in a bar under the thumb.
- **The enlarged card**: a pager over the deck with the whole photo (so the watermark shows), its tags, That's them, and Block or Report (B8's sheets; the card leaves my deck at once, C1-D6). That's them opens "That's them? They won't know unless they tap you too." with taps left today. Sent stays secret; mutual sends `navigate(.mutual(matchID))`; no taps left, card gone, rate limited and offline each say so gently.
- **Empty states**: nobody fits (change what you noticed), quiet, check-in ended (check in again), paused (be visible), today's views used up.
- **Privacy (P12)**: while `isSceneCaptured` (recording, mirroring, AirPlay) or when the app isn't active, the whole deck isn't drawn and a cover says "Looks are hidden" (C1-D2, C1-D4); photos also hide themselves. A capture is reported once as `recording`, each screenshot as `screenshot` with a gentle note (C1-D3), to `POST /api/abuse/capture`.
- **Live updates (P8)**: `deck.changed` for the room (`events(for: roomID)`) refetches every page showing, coalesced (C1-D5); also on reconnect, on return to the foreground, and every 30 s. A card that left closes if it was open.
- `APIDeckService` (the generated client: `getRoomState`, `getDeck`, `createTap`, `leaveRoom`, `setPaused`, `logCapture`), `FixtureDeckService` (a made-up room for previews, tests and Debug launches), and `DeckCopy` (every string).

**Tests** (`Tests/FeatureDeckTests`, Swift Testing): 39 logic tests (the service against canned replies, including that a deck reply with any extra field such as `userId` is refused; the model's paging, filters, every empty reason, live refetch and coalescing, taps, block, capture; the room home; filters; the fixture room) and 46 snapshots: every deck and room home state at the default and the largest text size, in `__Snapshots__/DeckSnapshotTests/`.

**Proof**

- **Traffic check (P1)**: a seeded room of 200 made-up `@glow.test` people on the local Supabase, then every call the deck screens make (room state, deck pages with and without filters, a one-sided tap, a mutual tap, a capture report) against the real local server (B2's and B4's routes): 18 responses, 37 KB, scanned for all 201 user IDs, first names, emails and the fields `userId`, `email`, `firstName`, `cardPath`: **0 leaks**. The target filters (green, short, blonde, glasses) returned exactly 1 card: the target.
- **P8 on the real server**: with the viewer on the room's private channel, `deck.changed` arrived 33 ms after someone left, 20 ms after someone paused and 32 ms after someone blocked the viewer, and each was gone from the viewer's next deck within 54 ms. FeatureDeck refetches on the first event at once.
- **The find test** (UI test in #39): in the 200-person fixture room, pick green, short, blonde and glasses, apply, open the target and tap That's them: **8.3 s** (limit 20 s). The real server's 200-person room (traffic check above) also narrows those filters to exactly the target.
- **P12 UI test** (same PR): with `-GlowDebugFakeScreenCapture YES` the cover shows and no card is on screen; without it, cards show. Both pass.
- Screenshots on Glow A (C1), fixture rooms: [room home](shots/c1-room-home-A.png), [leave](shots/c1-room-leave-confirm-A.png), [What did you notice](shots/c1-what-did-you-notice-A.png), [everyone](shots/c1-deck-grid-A.png), [filtered](shots/c1-deck-filtered-A.png), [enlarged](shots/c1-card-enlarged-A.png), [That's them?](shots/c1-tap-confirm-A.png), [sent](shots/c1-tap-sent-A.png), [after a tap](shots/c1-deck-tapped-A.png), [hidden while recorded](shots/c1-deck-hidden-recording-A.png), empty states ([no match](shots/c1-empty-no-match-A.png), [quiet](shots/c1-empty-quiet-A.png), [check-in ended](shots/c1-empty-checkinEnded-A.png), [paused](shots/c1-empty-paused-A.png), [views used](shots/c1-empty-viewLimitReached-A.png)), and the largest text size ([deck](shots/c1-deck-largest-text-A.png), [room home](shots/c1-room-home-largest-text-A.png)). A [recording](shots/c1-deck-ui-tests-A.mp4) of the three deck UI tests.

**Still mocked**

- Nothing in FeatureDeck itself: card photos come from B3's `PrivateImageView`, the deck from B4's routes, the room from B2's. Fixture rooms (`FixtureDeckService`, `FixtureImagingService`) are only for previews, tests and Debug launches.
- The preview session has no access token, so in the Simulator the live deck can't reach the server until B1's session (PR #6) lands. `-GlowDebugDeckFixture` runs every screen on a made-up room meanwhile.

**Next wave needs**

- **D1**: launch arguments (Debug only) `-GlowDebugDeckFixture 200` (or `quiet`, `checkinEnded`, `paused`, `viewLimitReached`), `-GlowDebugFakeScreenCapture YES`, and `-GlowDebugRoute deck/<room>` / `room/<room>` (#39). Identifiers: `screen.FeatureDeck.roomHome`, `room.status`, `room.visible`, `room.seeLooks`, `room.leave`, `room.leave.confirm`, `room.checkInAgain`, `room.tapsLeft`; `screen.FeatureDeck.deck`, `deck.notice` (the sheet), `deck.notice.who|top|hairLength|hairColor|extras` (chips inside by name), `deck.notice.apply`, `deck.notice.clear`, `deck.skip`, `deck.notice.open`, `deck.grid`, `deck.card.<card id>`, `deck.viewsLeft`, `deck.detail`, `deck.detail.thatsThem`, `deck.detail.more`, `deck.detail.close`, `deck.confirm`, `deck.confirm.tap`, `deck.confirm.cancel`, `deck.confirm.tapsLeft`, `deck.empty.<reason>`, `deck.empty.checkInAgain`, `deck.empty.beVisible`, `deck.hidden`. The fixture room's target card is `aaaaaaaa-0000-4000-8000-000000000079`.
- **D2**: the capture cover is C1-D2 and C1-D4; capture reports carry only kind and room. The traffic and P8 check scripts are in a collapsed comment on PR #25 (`scripts/e2e/` is D1's, so C1 didn't commit them there); both run against any local server and Supabase.
- **C2**: a mutual tap sends `navigate(.mutual(matchID))` after closing the enlarged card. If FeatureMatch also opens the takeover on `match.created`, both land on the same cover.
- **D4**: every string FeatureDeck shows is in `Copy/DeckCopy.swift`, grouped by screen (room home, What did you notice, deck, enlarged card and tapping, empty states, privacy, tag names, VoiceOver descriptions). Card descriptions for VoiceOver are built from tags only ("Green top, short blonde hair, glasses, headphones"). Plurals are hand-made (`tapsLeft`, `viewsLeft`, `timeLeft`) and want a string catalog with plural variants. `GlowCardTile`'s "Noticed" badge is B6's string.

### U1 · Design foundation (design wave)

_2026-10-25._ Branch `design/u1-foundation` (from `blind-mode`). The shared vision is [`docs/design/DIRECTION.md`](design/DIRECTION.md); this is its foundation. **U2, U3 and X2/U4: merge `design/u1-foundation` now** for the motion presets and tokens; every older DesignSystem name still works.

**Merge this first (additive, in the first commit)**

- `Motion` (`Tokens/Motion.swift`), DIRECTION's exact numbers: `Motion.snappy` (0.35/0.86), `Motion.smooth` (0.5/0.9), `Motion.gentle` (0.8/0.95), `Motion.fade` (easeOut 0.25, also every preset under Reduce Motion), `Motion.stagger` (40 ms), `breathPeriod` 4 s, `breathScale` 1.0...1.03, `breathOpacity` 0.6...1.0, `bloomDuration` 0.6, `heartbeatGap` 0.12, `veilLiftDuration` 1.2. Helpers that follow Reduce Motion by themselves: `.glowMotion(.smooth, value: x)`, `Motion.animate(.snappy) { … }` (from actions), `.glowRise(index: i, isVisible: shown)` (staggered rise), `.glowBreathing()` (waiting states), `Motion.rise(reduceMotion:)` (a transition), `GlowBreath.at(t)` (the numbers).
- Canvas and glass (`Glow/GlowCanvas.swift`): `.glowCanvas()` on every full screen (warm gradient plus 2.5 % film grain; `light: .accent` or `.hue(h)` adds a faint light at the top), `.glowGlass()` for lifted cards (28 pt continuous corners, 1 px top highlight, hairline, soft shadow; `isRaised:` and `tint:` a hue).
- Tokens: `.glowCanvasTop`, `.glowGlass`, `.glowGlassRaised`, `.glowTextTertiary` (hints, still 4.5:1), `GlowRadius.sheet` (20), `.tile` (24), `.panel` (28), `GlowSpacing.screenMarginWide` (24). The neutral ramp is warmer (U1-D1): same names and luminance, a warm near-black `#0B0A0F` and warm greys instead of blue greys, so every screen warms up without code changes.
- Type: `.display` and `.codeWord` are now New York (serif); new `.hero` (serif, regular, for one big quiet sentence), `.titleSerif`, `.codename` (serif italic, Blind), `.numeric` (monospaced digits; add `.contentTransition(.numericText())`), `.eyebrow` (use `.glowEyebrow()`). `.glowFont` applies tight tracking to the display styles.
- Haptics and sound, choreographed: `.glowMoment(.mutual, trigger:)` (two soft beats 120 ms apart plus the chime), `.glowArrives` (the swell), `.reveal` (success plus swell), `.messageSent` (tick), `.cardLeaves` (soft impact). Single pieces: `.glowHaptic(.heartbeat | .cardLeave | .reveal, trigger:)`, `.glowSound(.chime | .swell | .tick, trigger:)`, `GlowSounds.shared.play(_:)`. Sounds are synthesized in code (`GlowSoundSynth`), play in the `.ambient` session (the silent switch mutes them) and follow Settings > Sound (`GlowSounds.isEnabledKey`, on by default).

**Second commit (restyle, same public names)**

- Buttons are full capsules with a top highlight; filled ones cast a soft light in their color; pressing settles on `Motion.snappy`. `.glowOnSurface` is a capsule too. `GlowCodeWord` is New York semibold, set tight. `GlowEmptyState` breathes (a `GlowBreathingLight` behind a thin icon) and titles in `.titleSerif`.
- New: `GlowBreathingLight(hue:)` (waiting states, never a spinner), `.glowBloom(trigger:at:hue:)` (600 ms radial light from a point), `.glowVeil(isLifted:)` (X2/U4: blur and frost dissolving from the center over 1.2 s), `GlowWordmark()`. All have Reduce Motion crossfades and hold still under tests (U1-D2).
- Shell (`RootView`): tabs tinted with the accent; every stack root and pushed screen on the canvas through `containerBackground(for: .navigation)` (iOS 18+); `LaunchBackground` is `#0B0A0F`; the in-app launch view breathes. **X2**: the restyle didn't change `MainTabs`' structure, so your Blind tab merges cleanly; it inherits the canvas through `routeDestinations()`.
- Onboarding on the canvas with a staggered welcome; Settings > Sound toggle. Layout and copy changes are listed in `docs/design/CHANGES.md`.

**Snapshots**: the warmer neutrals and restyled components change every module's snapshots a little. U1 re-records them on this branch; when you merge and a PNG conflicts, take either side and re-record your own module (`scripts/sim.sh test <Module>` twice, or `TEST_RUNNER_SNAPSHOT_TESTING_RECORD=failed`).

**For B7 (admin CSS)**: the neutral hex values changed (`GlowPalette.tokens`): background `#0B0A0F`, surface `#17151C`, surfaceRaised `#221F27`, textPrimary `#F5F3F0`, textSecondary `#A9A39D`, line `#2D2931`. Accent, danger and the glow hues are unchanged.

### B6 · Design system

_2026-10-24, Wave 1._ Three PRs: [#20](https://github.com/davidaxie/glow/pull/20) on `w1/b6-design-tokens` (tokens and basic components, merged first so everyone can use them), [#21](https://github.com/davidaxie/glow/pull/21) on `w1/b6-lint` (`cross-owner` for A1: the SwiftLint rule) and the full module on `w1/b6-design`. **How to use everything is in [`ios/Packages/GlowKit/Sources/DesignSystem/README.md`](../ios/Packages/GlowKit/Sources/DesignSystem/README.md)**, one page.

**Built**

- `DesignSystem/Tokens`: every color token from the spec as SwiftUI styles (`.glowBackground`, `.glowSurface`, `.glowSurfaceRaised`, `.glowTextPrimary`, `.glowTextSecondary`, `.glowLine`, `.glowAccent`, `.glowDanger`, plus `.glowOnAccent` for text on accent and danger fills); the exact values in `GlowPalette` (`GlowRGB`, hex); the eight glow colors as `GlowHue` (raw values are the contract's `GlowColor`) with their text color `ink`; tag swatches as `GlowSwatch` (raw values are the contract's `TopColor` and `HairColor`); type as `GlowTextStyle` (`.glowFont(.title)`, `.font(.glow(.body))`), all Dynamic Type; `GlowSpacing` (4-point grid), `GlowRadius` (12 and 20), `GlowSize`; `GlowMotion` (0.2 s ease-out, the reveal spring, Reduce Motion fallbacks, `glowAnimation(_:value:)`) and `GlowPulse` (1.25 s, flash-safe); `GlowContrast` (WCAG math) and `GlowPalette.textPairings`.
- `DesignSystem/Components`: buttons (`.glowPrimary`, `.glowSecondary`, `.glowQuiet`, `.glowDanger`, `.glow(_:size:)`, `.glowLoading(_:)`), `GlowChip`, `GlowTagPicker` (one, or several with a limit), `GlowFlowLayout`, `GlowCardTile` with a watermark slot and `GlowWatermark`, `.glowHiddenWhenCaptured()` (P12), sheets (`.glowSheet`, `GlowSheetContent`), toasts (`.glowToast`), `GlowCodeField` (`.roomCode`, `.digits`), `GlowStepHeader`, `GlowEmptyState`, `GlowTakeover` (`.bloom`, `.night`, `.hue`).
- `DesignSystem/Glow`: `GlowSurface` (full-screen color, a flash-safe bloom pulse, a slow fade under Reduce Motion), `GlowCodeWord`, `.buttonStyle(.glowOnSurface)`, `.glowFullBrightness()` with `GlowBrightness` (restores the person's own level), `.glowKeepAwake()` with `GlowKeepAwake`.
- `DesignSystem/Haptics`: `.glowHaptic(_:trigger:)` (light tap, selection, success, warning, mutual, glow pulse), `GlowHaptics` and `GlowHapticPattern` (Core Haptics, silent on the Simulator).
- `GalleryView` (Settings > Debug > Gallery): every token and component in every state, plus a live sheet, toasts, takeover and full-screen glow. Compiled out of Release.
- The app icon (two soft glows, brightest where they overlap). The accent color (#FF4FA3) and `LaunchBackground` (#0B0B10) already matched the tokens, so they stay (B6-D5).
- Tests (`scripts/sim.sh test DesignSystem`): WCAG AA on every text pairing and every glow color's ink through the whole pulse; the pulse's period, smoothness and 70% floor in both motion settings; brightness and keep-awake restore in every order of events; code formats, the tag picker's limits, haptic patterns; tokens against the spec and `contracts/`; the lint rule (in #21); snapshots of every Gallery section at the default and the largest text size.

**Proof**: Gallery screenshots on "Glow A (B6)" in `docs/shots/b6-gallery-*.png` (from #20) and `docs/shots/b6-full-*.png` (live glow, takeover, card tiles, code fields). Full-section snapshots at both text sizes are in `ios/Packages/GlowKit/Tests/DesignSystemTests/__Snapshots__/`.

**Decisions**: B6-D1 (dark ink on every glow color), B6-D2 (dark ink on filled buttons and selected chips), B6-D3 (the pulse brightens, never darkens), B6-D4 (a recorded screen hides cards instead of blurring them), B6-D5 (plain launch color), B6-D6 (screen helpers count holders, app only), B6-D7 (three-beat glow haptic).

**Using it** (feature modules): `import DesignSystem`, then `Text("Hi").glowFont(.body).foregroundStyle(.glowTextPrimary)`, `Button("Check in") { … }.buttonStyle(.glowPrimary)`, `.background(.glowBackground)`. Never `Color(...)`, `UIColor`, `.font(.title)` or `Font.system` in a feature: SwiftLint fails them once #21 is in. Need a color or style that isn't here? Ask under **For B6**.

**Still mocked**: nothing. DesignSystem depends only on SwiftUI, UIKit and Core Haptics.

**Next wave needs**

- **C1 (deck):** `GlowCardTile` for cards (pass your non-caching image view as `photo`, and `GlowWatermark(viewerCode)` if you add one on the device), `GlowTagPicker` for What did you notice, `.glowHiddenWhenCaptured()` around the deck (fake a capture in UI tests with `.environment(\.isSceneCaptured, true)`), `GlowEmptyState` for "Nobody fits that yet.", `.glowHaptic(.lightTap, trigger:)` for taps, and `.glowSheet` for the tap confirmation. Screenshot logging is yours (P12).
- **C2 (mutual moment):** `GlowTakeover(.bloom) { … }` and `.glowHaptic(.mutual, trigger: matchID)`.
- **C3 (glow):** `GlowSurface(GlowHue(rawValue: glow.color.rawValue) ?? .pearl) { GlowCodeWord(word) … }`, which already handles brightness, keep-awake, Reduce Motion and the ink color. Use `.buttonStyle(.glowOnSurface)` for buttons on it, and `GlowHaptics.shared.play(.glowPulse)` when it starts. The Live Activity extension can use `GlowHue` and the tokens, but not `GlowSurface` or `glowKeepAwake` (app only, B6-D6).
- **B1, B2:** `GlowCodeField(…, format: .digits)` for the email code and `.roomCode` for room codes (pass `GlowConstants.ROOM_CODE_LENGTH`), `GlowStepHeader` for onboarding steps, `.glowToast` for "Looks like you're not in this room yet. Try again inside."
- **B3:** `GlowTagPicker` with `GlowSwatch` for the outfit tags.
- **B8:** `GlowSheetContent(…, tint: GlowPalette.danger)` with `.glowDanger` buttons, and a `.success` toast for "Done. They won't see you again."
- **B7:** the admin CSS variables come from `GlowPalette.tokens` (name and hex) and `GlowHue.allCases` (`rgb.hex`); the spec's values are unchanged.
- **D4:** DesignSystem has a few strings of its own ("In progress", "Dismiss", "Step %lld of %lld", "Close", "Noticed", "Code word: %@", "Hidden while your screen is shared", "Couldn't load this look", "Photo didn't load", and the eight color names). They use the main bundle today. When you add a string catalog to DesignSystem, A1 needs to add `resources: [.process("Resources")]` to its target, and the strings need `bundle: .module`.

### B8 · Safety, moderation and cleanup

_2026-10-24, Wave 1._ PR [#12](https://github.com/davidaxie/glow/pull/12) (moderation and rate limit interfaces) and PR [#22](https://github.com/davidaxie/glow/pull/22) on `w1/b8-safety` (everything else).

**Built**

- **Endpoints** (handlers in `server/src/server/safety/routes.ts`): `POST /api/blocks` and `POST /api/reports` (card, match or chat ID; 404 for anything the caller can't act on; `match.ended` to both people and `deck.changed` to their rooms, B8-D6), `POST /api/me/pause` (`deck.changed` only when it changed), `POST /api/abuse/capture` (B8-D7), `DELETE /api/me` (B8-D4) and `GET /api/cron/purge` (B8-D5, B8-D8). Each counts against its rate limit policy.
- **Purge** (`server/src/server/safety/purge.ts`): `purge_expired`, the returned card photos, an orphan sweep of both buckets, `checkin.expiring`, `glow.ended`, `match.choice` and `deck.changed`, the after-the-fact review of `pending` chat messages, and 7-day retention for Supabase Auth's audit log. `server/vercel.json` runs it every 5 minutes.
- **Migration** `supabase/migrations/0003_b8_forget_account.sql`: `forget_account_traces` and `purge_auth_audit` (functions only; A1 reviews, For A1 item 4).
- **FeatureSafety** (iOS): `BlockSheet(context:)`, `ReportSheet(context:)` (reason chips, optional details up to 1,000 characters, "Report and block"), `PauseView()` and `DeleteAccountView()` (confirm, then sign out), on B6's components, with models in `SafetyModels.swift`. Screenshots in `docs/shots/b8-*`.
- **Moderation and rate limits**: see the tables below.

**Tests**

- `server/tests/safety/safety.live.test.ts` runs against a real local Supabase: an agent's own stack (`eval "$(scripts/agent-env.sh B8 --own-db)"`, or point `server/.env.local` at it), or CI's. Agents on the shared stack skip it. It proves P7 (both decks lose each other within 5 seconds of a block), P8 (pause), report evidence, capture logging, account deletion (every uuid column of every public table, both buckets, the auth user and the audit log, with a positive control first), and P9 (expired card rows and photos deleted, the sweep, one warning per check-in, the cron secret).
- `server/tests/safety/purge.test.ts`: purge notifications and the 5-minute schedule. `server/tests/moderation/live.test.ts`: real Claude, p95 under 2.5 s and the consented fixtures, only with `ANTHROPIC_API_KEY` (Needs David 14).
- `ios/Packages/GlowKit/Tests/FeatureSafetyTests`: request bodies (card or match ID only), failures, analytics literals, and snapshots of every screen at default and largest text size.

**Moderation** (`server/src/server/moderation`, import from `@/server/moderation`)

| Export | Shape |
| --- | --- |
| `moderateImage(kind, bytes)` | `kind: 'card' \| 'profile'`, `bytes: Uint8Array` (the JPEG as uploaded). Resolves `ImageModeration`: `{ decision: 'approved', findings }`, `{ decision: 'rejected', reason, findings? }` or `{ decision: 'held', reason: 'possibly_minor', findings }` (profile only). Throws `ModerationUnavailableError` after MODERATION_TIMEOUT (2.5 s) or on an outage. |
| `moderateText(body)` | Resolves `TextModeration`: `{ decision: 'passed' }`, `{ decision: 'flagged', category }` or `{ decision: 'pending' }` (no answer within 2.5 s, or an outage). Never throws. |
| `reviewText(body)` | The same with a 15 s timeout, for the after-the-fact review. |
| `photoRejected(reason)` | `HttpError` 422 `photo_rejected` with `reason`. |
| `messageRejected()` | `HttpError` 422 `message_rejected`. |
| `ModerationUnavailableError`, `moderationUnavailable()` | `HttpError` 503 `unavailable`, `reason: 'moderation'`, `Retry-After: 2`. |
| `decideImage(kind, findings)` | The rules on their own (B8-D2). |
| `moderationFixtureJpeg(flags)`, `TEXT_FIXTURE`, `setModerationModelForTests(model)` | For tests. |
| Types | `ImageKind`, `ImageModeration`, `ImageRejectReason` (`face_visible`, `nudity`, `no_outfit`, `no_person`, `possibly_minor`, `unreadable`), `ImageFindings`, `TextModeration`, `TextCategory`. |

**Rate limits** (`server/src/server/ratelimit`, import from `@/server/ratelimit`)

| Export | Shape |
| --- | --- |
| `rateLimit(key, policy)` | Counts one request; throws `rateLimited()` (429 `rate_limited`, `Retry-After` in seconds) when over. Use the person's ID as the key. |
| `checkRateLimit(key, policy)` | `{ allowed, remaining, retryAfterSeconds }`, without throwing. |
| `limitRequest(operationId, req, user)` | Picks the policy for a contract operation and keys by person or client IP. For A1's route helper. |
| `RATE_LIMIT_POLICIES`, `policyForOperation(id)` | The policies below, and which operation uses which. |

| Policy | Limit | Operations |
| --- | --- | --- |
| `signIn` | 10 per 10 min, per IP | `testLogin` |
| `join` | 20 per 10 min | `resolveRoom`, `joinRoom`, `leaveRoom` |
| `checkin` | 10 per 10 min | `createCheckin` |
| `deck` | 60 per min | `getDeck` |
| `taps` | 20 per min | `createTap` |
| `messages` | 30 per min | `sendMessage` |
| `reports` | 10 per hour | `createReport` |
| `blocks` | 60 per hour | `createBlock` |
| `capture` | 60 per hour | `logCapture` |
| `photos` | 20 per 10 min | `addProfilePhoto`, `deleteProfilePhoto` |
| `account` | 30 per 10 min | `updateProfile`, `setPaused`, `deleteAccount`, `registerDevice`, `deleteDevice` |
| `admin` | 300 per min | every `admin*` operation |
| `api` | 300 per min | everything else (reads); `runPurge` has none |

A limited request answers 429 `rate_limited` with `Retry-After`; the app already maps that to `APIError.rateLimited`. Keys are hashed before they reach the store, and limits fail open if Upstash is down (B8-D3).

**Still mocked**: Claude runs only with `ANTHROPIC_API_KEY`; without it, local runs use the fake (B8-D1). Upstash runs only with `UPSTASH_REDIS_REST_*`; locally it's in memory. Notifications are real: `server/src/server/safety/dependencies.ts` re-exports B5's `notify` and `notifyRoom` from `@/server/notify` (since #15).

**Next wave needs**

- **C1**: the block and report sheets from a card, and capture logging (For C1).
- **C4**: moderation, the chat's block and report entries, and unmatch matching a block (For C4).
- **D1**: the end-to-end block path is `navigate(.block(.chat(id)))` → "Block" → "Close" (back to Matches); the other person's app gets `match.ended`. Expiry: set a check-in's `expires_at` in the past and call the purge route with the cron secret.
- **D2**: things to try to break: blocking or reporting a card the deck never showed you, or a match you're not in (404); a capture with someone else's room (stored without the room); the purge route without the secret (401); deleting an account and then finding anything about it (`rowsMentioning` in the live test is a start).

### B5 · Push, realtime and events

_2026-10-24, Wave 1, full._ PR on `w1/b5-push` (after the interfaces in [#15](https://github.com/davidaxie/glow/pull/15)). Decisions B5-D1 to B5-D10 in `docs/DECISIONS.md`.

**Built**

- **Server sender** (`server/src/server/notify`): `notify`, `notifyRoom` and `notifySettled`, a Realtime REST broadcast to private channels plus Apple push. APNs is HTTP/2 (`node:http2`, one connection per host, closed when idle) with an ES256 provider token signed by jose and reused for 50 minutes. Collapse IDs, thread IDs, `interruption-level` and `apns-expiration` come from the catalog and B5-D7; `glow.started` and `match.recheck` are time sensitive. Dead tokens (410, `BadDeviceToken`, `DeviceTokenNotForTopic`) are pruned; 429 and 5xx are retried once (B5-D8). Without `APNS_*`, push is skipped and Realtime still goes out.
- **`POST /api/devices` and `DELETE /api/devices/{id}`**: register (moving a token to a new person gives a new ID, B5-D3) and remove (someone else's device is the same 404 as a missing one).
- **iOS `Push`**: `LivePushService` registers the four categories at launch, asks Apple for a token whenever permission allows (every launch, as Apple recommends), uploads it once per person and token (sandbox in Debug, production in Release, B5-D5), retries when the app is next active, and maps taps to Routes. `PushService.unregister()` deletes the token on the server.
- **iOS `GlowRealtime`**: `LiveRealtimeService` on supabase-swift's `RealtimeClientV2`: joins `user:{id}` (lowercase) by itself when someone signs in, `join(room:)` / `leaveRoom()` for one room at a time, leaves everything on sign-out, drops any broadcast that isn't exactly a contract event, never replays old events (B5-D9), and on foreground refreshes the token, rejoins what dropped and reports `.connected`.
- **Fixtures**: `ios/fixtures/push/*.apns`, one per event, kept identical to the server's payloads by `server/tests/notify/fixtures.test.ts` (rewrite with `GLOW_WRITE_PUSH_FIXTURES=1`).

**Tests**: `server/tests/notify/` (Vitest): APNs against a local HTTP/2 server with a throwaway P-256 key (JWT verified, headers, retries, pruning, timeouts); P6 snapshots of every push exactly as sent over the wire (`__snapshots__/push-payloads.test.ts.snap`), with name and ID checks; the device store and Realtime channels against the local Supabase (one person can't join another's channel, uppercase topics and rooms without a check-in are refused, apps can't send, `notify` reaches only the right person); routes through the real helper. iOS: `PushTests` (17) and `GlowRealtimeTests` (14), including every fixture's Route.

**Proof**: [`match_created` banner](shots/b5-push-banner-match-created-A.png), [tapped, it opens the mutual moment](shots/b5-tap-match-created-A.png), and the banners for [`match_recheck`](shots/b5-push-banner-match-recheck-A.png), [`glow_started`](shots/b5-push-banner-glow-started-A.png) (Time Sensitive), [`message_created`](shots/b5-push-banner-message-created-A.png) and [`checkin_expiring`](shots/b5-push-banner-checkin-expiring-A.png). No names anywhere. Taps for the other events are covered by `PushRoutingTests` (every fixture through `route(for:)`); the native Simulator tool couldn't run (Needs David, the `xcode-select` item).

**How to notify from a route** (B4, B8, C2, C3, C4)

```ts
import { after } from 'next/server';
import { notify, notifyRoom, notifySettled } from '@/server/notify';

const result = await rpc('record_tap', { … });            // the database call succeeded
if (result.matchId) after(() => notify(result.userIds, { type: 'match.created', matchId: result.matchId }));
after(() => notifySettled(result.settled));                // choice_timeout → match.choice, glow_expired → glow.ended
after(() => notifyRoom(roomId, { type: 'deck.changed', roomId }));
```

- Schedule `after()` only once the database call succeeded: Next runs it even when the handler throws.
- `notify` takes one user ID or a list, `user:{id}` events only; `notifyRoom` takes `deck.changed` only. Extra fields are dropped (B5-D1). Neither throws.
- In tests: `vi.mock('@/server/notify', () => ({ notify: vi.fn(), notifyRoom: vi.fn(), notifySettled: vi.fn() }))`.

**How to subscribe in a feature** (C1 to C4)

```swift
@Environment(\.dependencies) private var dependencies

.task {
    for await event in dependencies.realtime.events(.messageCreated, .matchEnded) {
        await model.refresh()                     // events only say what changed; refetch from the API
    }
}
.task {
    for await state in dependencies.realtime.connectionStates() where state == .connected {
        await model.refresh()                     // after a reconnect, anything sent while away is gone
    }
}
```

Also `events(for: matchID)` and `events(for: roomID)`. The room channel needs `try await dependencies.realtime.join(room: roomID)` after a check-in (and when the room home reappears), and `await dependencies.realtime.leaveRoom()` on leaving. In previews and tests, `PreviewRealtimeService().emit(RealtimeEvent(kind: .matchCreated, matchID: id))`. `RealtimeEvent.destination` gives each event's screen; events never navigate by themselves (B5-D6).

**Still mocked**: nothing in B5's paths. The real APNs path is untested against Apple until the `.p8` exists: `server/tests/notify/apns-live.test.ts` sends a real sandbox push and skips until `APNS_*` and `APNS_TEST_DEVICE_TOKEN` are set. Realtime in the Debug app joins with the session's access token, so it only connects once B1's live Session is in.

**Next wave needs**: B1 calls `push.unregister()` before sign-out and `push.requestAuthorization()` in the notifications step; B8 swaps its `safety/stubs/notify.ts` for `@/server/notify`; routes that get `settled` call `notifySettled`; C1 joins the room channel; C2's mutual takeover can follow `realtime.events(.matchCreated)` while the app is open (the app root would need a listener, ask A1).

### B4 · Deck and matching engine

_2026-10-24, Wave 1._ PR [#9](https://github.com/davidaxie/glow/pull/9) on `w1/b4-deck`.

**Built**

- `POST /api/rooms/{id}/deck` (`server/src/server/deck/get-deck.ts`): validates the filters (including the contract's `uniqueItems`, B4-D1), calls `get_deck` (every deck rule, the filters, the view cap and the all-day shuffle), and returns up to 10 cards, each with a 60-second image link signed for this viewer. Cards are only `id`, `image`, `tags`, `tappedByMe` (P1).
- `POST /api/rooms/{id}/taps` (`server/src/server/taps/create-tap.ts`): calls `record_tap`. `sent` is exactly `{ result, tapsLeftToday }` and tells nobody (P5); `mutual` adds `matchId` and sends `match.created` to both people after the response (B4-D3).
- `GET /api/matches` (`server/src/server/matches/list-matches.ts`): calls `list_matches`, returns only MatchSummary fields, and sends A2's settled timeouts as events (`choice_timeout` → `match.choice`, `glow_expired` → `glow.ended`, to both people).
- `server/src/server/deck/db.ts`: the service-role client and `rpc()`, mapping the database's error codes to HTTP (CONTRACTS.md).
- `supabase/migrations/0004_b4_deck_set_based.sql`: the deck rules written once as views, read by both the per-card helpers and a set-based `get_deck` (B4-D5). About 20 ms to 2 ms of database time per deck with 300 people; query plans are in PR #9.
- Tests: unit tests for all three routes; integration tests against a real local Supabase for every deck rule, filters, paging, the view cap and shuffle, tap targets (404), the cap (409), mutual taps, 50 pairs tapping at once (twice), P5 (responses, counts, events and timing) and the matches list (B4-D6); and the 300-person HTTP load test, `server/tests/deck/load.ts`.

**Still mocked** (swapped in one file, `server/src/server/deck/dependencies.ts`):

- B3's `cardImageLink(cardId, viewerId)` (PR #7): `server/src/server/deck/stubs/card-link.ts` has B3's exact signature and makes the same link B3's image route checks.

Real: B5's `notify(userIds, event)` from `@/server/notify` (#15), and rate limits, which `route()` applies with B8's `deck`, `taps` and `api` policies before each handler runs. Tests mock `notify` to see who would be told what.

**Commands**

```
GLOW_INTEGRATION=1 pnpm --filter server exec vitest run tests/deck tests/taps tests/matches   # needs a local Supabase
pnpm --filter server build && PORT=3104 pnpm --filter server start &   # then:
node server/tests/deck/load.ts                                           # 300 people, then 50 simultaneous pairs
```

**Next wave needs** (C1 builds the deck screen, C2 the mutual moment and the matches list)

Deck, `POST /api/rooms/{id}/deck` with `{ "filters": { "gender": ["woman"], "topColor": ["green", "blue"], "extras": ["glasses"] }, "offset": 0 }` (every field optional; an empty list means any):

```json
{
  "cards": [
    {
      "id": "bbbbbbbb-0000-4000-8000-000000000001",
      "image": { "url": "/api/cards/bbbbbbbb-0000-4000-8000-000000000001/image?exp=1793040060&sig=…", "expiresAt": "2026-10-24T20:16:00.000Z" },
      "tags": { "topColor": "green", "hairLength": "short", "hairColor": "brown", "extras": ["glasses"] },
      "tappedByMe": false
    }
  ],
  "viewsLeftToday": 49,
  "hasMore": true,
  "nextOffset": 10
}
```

- Page with `offset: nextOffset` until `hasMore` is false. Refreshing gives the same order all day. Seeing a card again is free; `viewsLeftToday` counts different cards.
- An empty page says why in `emptyReason`: `quiet` (nobody else here fits you yet), `no_match` (nobody fits these filters: "Nobody fits that yet. Try fewer details."), `view_limit_reached`, `paused` (you're paused) or `checkin_ended` (your check-in expired, ended, was removed, or the room ended).
- The image link lasts 60 seconds and works only with this person's token. Fetch it with the bearer token; when it expires, fetch the deck page again for a fresh link.
- 404 means you never checked in to this room (or it doesn't exist). 400 is a filter value outside the contract or a repeated one. 429 has `Retry-After`.
- Refetch the deck on `deck.changed` (someone paused, left or blocked).

Tap, `POST /api/rooms/{id}/taps` with `{ "cardId": "…" }`:

```json
{ "result": "sent", "tapsLeftToday": 2 }
{ "result": "mutual", "tapsLeftToday": 1, "matchId": "64bfd966-bf7f-426a-b7aa-f0dc371bae1a" }
```

- `sent` promises nothing about the other person (P5): show "They won't know unless they tap you too." Tapping the same card again is free and answers `sent` again.
- When two people tap each other at the same moment, one gets `sent` and the other `mutual` (B4-D4). Both get `match.created` on `user:{id}` (and a push). Open the mutual moment on `match.created` or on a `mutual` reply, whichever comes first.
- 404: the card isn't in your deck right now (they left, paused, blocked you, or you matched). Drop it from the deck. 409 `tap_limit_reached`: no taps left today in this room.
- After a match, the card leaves both decks.

Matches, `GET /api/matches`:

```json
{
  "matches": [
    { "id": "64bfd966-…", "status": "choosing", "firstName": "Blake", "roomName": "Glow demo room (test data)",
      "createdAt": "2026-10-24T20:10:00.000Z", "choiceDeadline": "2026-10-24T20:20:00.000Z" },
    { "id": "453803c0-…", "status": "met", "firstName": "Casey", "roomName": "Glow demo room (test data)",
      "createdAt": "2026-10-24T19:00:00.000Z", "choiceDeadline": "2026-10-24T19:10:00.000Z", "lastMessageAt": "2026-10-24T19:40:00.000Z" }
  ]
}
```

- Newest first. "Now" is `choosing` and `glowing`; "Earlier" is `chatting` and `met`. Ended matches (unmatched or blocked) never appear. A choice window that ran out shows as `chatting`, and both people get `match.choice`.
- No user IDs anywhere: the match ID is the only handle (D20). `GET /api/matches/{id}` (C2) has the photo count and the choice.

### A2 · Contracts and database

_2026-10-24, Wave 0._ PR [#2](https://github.com/davidaxie/glow/pull/2) on `w0/a2-contracts` (merged), then the Checkpoint 1 fixes in PR [#14](https://github.com/davidaxie/glow/pull/14) on `w0/a2-checkpoint1`. The reference is [`docs/CONTRACTS.md`](CONTRACTS.md): one line per endpoint, event, constant and database function.

**Checkpoint 1 fixes** (`0002_a2_checkpoint1.sql`, D46 to D56)

- **Grants:** later migrations' tables, sequences and functions are usable by `service_role` by default; clients still get nothing.
- **`match.recheck`:** a visible, name-free push for a stale Find.
- **`start_glow`:** opens the chat or says why it waits, instead of raising.
- **Check-ins:** `create_checkin` needs a passed join check.
- **New operations:** `completeOnboarding`, plus admin review of held photos.
- **Timeouts:** lazy timeouts are reported in `settled`, so the route that applied them notifies.
- **Metrics:** no tap metrics at all.
- **Tap counts:** today's taps are counted apart from the tap row, so counts are exact.
- **Deck:** it says `checkin_ended` after purge, the same day.
- **Limits:** limits in openapi.yaml are checked against constants.json.
- **Known gap:** deleting an account clears a ban (D56, left for D2).

**Built**

- `supabase/migrations/0001_a2_init.sql`: enums, every table in the data model (plus `location_checks` and `room_activity`, D17 and D30), constraints and indexes. RLS is on everywhere with no policies, and grants and default privileges are closed to `anon` and `authenticated` (D28). Every database function from the spec plus the ones routes need (CONTRACTS.md), all security definer with `search_path = ''`, with advisory locks on the pair in `record_tap`, the viewer in `get_deck` and the room in `start_glow`. Also Realtime authorization (D27) and private buckets `profile-photos` and `room-cards`.
- `supabase/seed.sql`: the demo room, 4 meeting spots, and the test people below. `supabase db reset` runs clean.
- `contracts/openapi.yaml` (every endpoint, admin included, with schemas, errors and examples), `contracts/events.json` and `contracts/constants.json`.
- `scripts/codegen.sh` (`pnpm codegen`): checks the contract (P1 field names, no 403, events against openapi), then generates `server/src/contracts` (types, zod schemas, the route registry, constants, events with `apnsRequestFor`, database types), the Swift client and constants in `APIClient/Generated`, `supabase/tests/database/000_constants.test.sql`, and the tables in CONTRACTS.md. A second run changes nothing. `--verify` compiles both clients on their own.
- pgTAP, 443 tests in `supabase/tests/database/` (390 at PR #2, plus `090_checkpoint1` and the new table): lockdown of every table, function and bucket; Realtime channels; every deck rule including show me and blocks both ways; the tap cap and TTL; 50 simultaneous pairs making exactly 50 matches (it fails, 41 of 50, with the pair lock removed); choosing and glow, including color plus code word uniqueness; check-ins, 18+ and purge; blocks, reports and chat.

**Demo room (local seed, test data)**

| | |
| --- | --- |
| Slug | `demo` |
| Room ID | `de000000-0000-4000-8000-000000000001` |
| Static QR token | `DEMOSTATICTOKEN2` (`allow_static_qr` on) |
| Room code | `HACK26` |
| Center | 37.8029, -122.4484, radius 200 m, America/Los_Angeles. A placeholder venue (D11) |
| QR secret (hex) | `00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff`, so rotating tokens are reproducible locally |
| Link | `glow://r/demo?t=DEMOSTATICTOKEN2`, or `https://{DOMAIN}/r/demo?t=DEMOSTATICTOKEN2` |
| Meeting spots | Main entrance, Food line, Water station, Stage left |

**Test people** (no passwords; email code or test sign-in; IDs start with `7e570000`): `alex@glow.test` (woman, shows men), `blake@glow.test` (man, shows women), `casey@glow.test` (nonbinary, shows everyone), `drew@glow.test` (woman, shows women and nonbinary), `admin@glow.test` (man, shows women, in `admins`), `new@glow.test` (onboarding not started). Seeded people have no photos, and no check-ins, because card photos must exist in storage; check in through the API.

**Still mocked**: nothing in A2's paths. Server routes still answer 501 until each owner builds them, and the iOS app needs A3's `Package.swift` dependencies (For A3, item 1) before it can import the client.

**Next wave needs**

- **Everyone:** run `pnpm codegen` after touching `contracts/` or `supabase/migrations/`, and commit the result. Contract changes after Checkpoint 1 go through A1 in a `contract-change` PR. A new table needs RLS on and no policies, and is usable by `service_role` automatically (CONTRACTS.md, "Grants for new tables and functions").
- **Any route that calls `get_match`, `list_matches`, `set_choice`, `start_glow` or `glow_met`:** send the events for each entry in `settled` (CONTRACTS.md, "Settled timeouts"). Purge won't.
- **B1:**
  - A trigger creates each `profiles` row on sign-up, and the database refuses under-18 birthdates (error `under_18`).
  - Advance `onboarding_step` through `profile` and `photos` yourself. Then `POST /api/me/onboarding/complete` (`complete_onboarding`) finishes it, whether or not push was allowed. It needs an approved photo; held ones don't count.
  - Use `@glow.test` addresses for test sign-in.
  - Profile photo paths are `profile-photos/{userId}/{photoId}.jpg` (checked by a constraint).
- **B2:**
  - Write a `location_checks` row (pass, fail or demo_skip, plus an accuracy bucket, never coordinates) for every join and Find check. `create_checkin` refuses a check-in without a passing `join` row from the last `JOIN_TICKET_TTL`.
  - Leaving: `update checkins set left_at = now()` and delete the photo.
  - `GET /api/rooms/{id}` calls `get_room_state`.
  - `rooms.static_qr_token` and `qr_secret` (hex) are on the room row.
- **B3:**
  - Generate the card ID, upload to `room-cards/{roomId}/{cardId}.jpg`, then call `create_checkin` and delete any `replacedCardPaths`. Map `location_required` to 422.
  - The image route uses `card_visible_to`, and match photos use `match_photo_path`.
- **B4:** `get_deck`, `record_tap` and `list_matches` (send its `settled` events). The cap and race tests already pass in the database. A re-tap after an unmatch uses a tap (D53).
- **B5:**
  - `eventCatalog`, `userTopic`, `roomTopic` and `apnsRequestFor` in `@/contracts` build every channel name and push payload from events.json, including the new `match.recheck`.
  - Payload keys are camelCase (`matchId`, `roomId`). A3's stand-in fixture guessed `match_id`.
  - `userIds`, `recheckUserIds` and `staleUserIds` in function results tell you who to notify.
- **B7:**
  - Admin operations are in the contract, now with held-photo review (`adminListPhotos`, `adminPhotoImage`, `adminReviewPhoto`).
  - Metrics come from `room_activity`, with no taps (D52).
  - Ban with `profiles.banned_at`; remove a card with `checkins.visible = false`.
- **B8:**
  - `block_user`, `create_report` and `purge_expired` (it returns photo paths to delete, and events to send).
  - Pausing is `profiles.paused`, which every deck rule reads.
  - Moderation holds possibly-under-18 profile photos as `held`; B7 reviews them.
- **C2, C3, C4:**
  - `set_choice` sends `match.recheck` to `recheckUserIds`.
  - `start_glow` (pass C3's word list) now returns `started`, `chat` or `waiting`; see CONTRACTS.md, "start_glow results".
  - Also `glow_met`, `cancel_glow`, `get_match`, `send_message` and `unmatch`. Their result shapes are in CONTRACTS.md.

### A1 · Integrator and repo

_2026-10-24, Integrator mode._

**Merged into main**: A1's skeleton (#1), A2's contracts and database (#2), A3's iPhone skeleton (#3, rebased onto #2, with A3's decisions renumbered from D10–D22 to D33–D45), parallel-agent isolation (#4), the generated registry and stubs (#13), A2's Checkpoint 1 contract fixes with their stubs and spec updates (#14), the app test that accepts per-agent URLs (#28), real SwiftFormat checks in worktrees (#30), local CI (#31), rate limits in `route()` (#32), the Simulator and stack caps with union-merged docs (#33), the xcodebuild cap (#36), and own-stack and stale-slot fixes (#40).

**Built since Wave 0**

- **Parallel agents** (A1-D1): `scripts/agent-env.sh <ID>` (own Simulators, port, API URL, and `--own-db`), `sim.sh` reads `GLOW_SIM_A`, `GLOW_SIM_B` and `GLOW_API_BASE_URL` and has `setup A` and `teardown`, and `scripts/db.sh` behind `pnpm db:*` protects the shared stack. See "Many agents on one Mac" in `AGENTS.md`.
- **Generated registry wired**: every operation in `contracts/openapi.yaml` (52 now) has a route file that answers 501 until its owner builds it. `pnpm stubs` adds stubs after a contract change, and `scripts/smoke.sh` reads the endpoint list from the registry.
- **Local CI** (A1-D4): `scripts/ci-local.sh <ID>` runs both jobs in the agent's slot and prints a summary for the PR.
- **CI** (A1-D2): the codegen tool and Swift packages are cached; macOS runs on main and on ready-for-review PRs that touch the app, the contract or the iOS scripts.
- **Errors** (A1-D3) and **rate limits**: contract error codes only, with 409 and 422 helpers and `reason`; every route is rate limited by B8's policies right after sign-in.

**Commands**: see Commands, "Many agents on one Mac" and "While GitHub Actions is down" in `AGENTS.md`.

**Preview URL**: none yet. Vercel isn't linked (Needs David, item 1).

**Still mocked**: nothing in A1's paths. Every endpoint answers 501 until its owner builds it.

### A3 · iPhone app skeleton

_2026-10-24, Wave 0._ PR [#3](https://github.com/davidaxie/glow/pull/3) on `w0/a3-ios`.

**Built**

- `ios/project.yml` (XcodeGen): the `Glow` app (iOS 17, Swift 6 language mode, complete strict concurrency, warnings as errors), the `GlowLiveActivity` widget extension, `GlowTests` (hosted unit tests) and `GlowUITests`, Debug and Release from `ios/Glow/Config/{Shared,Debug,Release}.xcconfig`, and one scheme, `Glow`, whose test action runs every test target, package tests included. The `.xcodeproj` is generated and git-ignored.
- Capabilities in `ios/Glow/Glow.entitlements`: push (`aps-environment` per configuration), Time Sensitive Notifications, Sign in with Apple, Associated Domains (`applinks:{DOMAIN}`), plus the remote-notification background mode, Live Activities, purpose strings (camera, photo library, location, temporary full accuracy) in `Info.plist`, `PrivacyInfo.xcprivacy`, and a placeholder icon and launch color. `glow://` and the local-networking ATS exception are added to Debug builds only (D34).
- `ios/Packages/GlowKit`: every module from the spec, each with a placeholder (an entry view or a `live` factory) and a passing test: AppCore, APIClient, DesignSystem, Session, Location, Imaging, Push, GlowRealtime (the spec's Realtime, D41), LiveActivityShared (C3), and the nine feature modules. Supabase `Auth` is linked to Session, `Realtime` to GlowRealtime, and swift-snapshot-testing to DesignSystem's and every feature's tests.
- AppCore: `Route` (every screen), `Router`, `NavigateAction`, `DeepLink`, the `Dependencies` container with every service as a protocol (`SessionService`, `LocationService`, `ImagingService`, `PushService`, `RealtimeService`, `Analytics`), a preview mock for each, `AppConfig`, typed IDs (`RoomID`, `MatchID`, `CardID`; there is deliberately no user ID type), `RoomLink`, `JoinTicket` and `LocationFix` (which never print their secrets or coordinates), `PrivacyScrubber`, `Broadcaster` and `PlaceholderScreen`.
- APIClient wrapper: `GlowAPI` (base URL from config, an ephemeral no-cache URLSession), `AuthMiddleware` (Bearer token from Session, only to the API's own host), `RetryMiddleware` (D38), `StatusErrorMiddleware` (401, 404, 429 to `APIError`), `GlowDateTranscoder`, and `MockTransport` for tests and previews.
- The app target: `AppDelegate` (owns the dependencies and router, forwards push callbacks to `PushService`), `AppComposition` (the composition root), `RootView` (launching, onboarding or the Rooms, Matches and Settings tabs, by session state and Route; sheets; full-screen takeovers; incoming links) and `LiveAnalytics` (PostHog live, Sentry ready but not linked, D35 and D36).
- `scripts/sim.sh`: every command in the spec's Simulator workflow, plus `launch`, `open`, `allow-push`, `lint`, `verify-project`, `logs` and `reset`. `scripts/sim.sh help` lists them.
- `ios/fixtures/`: synthetic outfit photos (D44), the demo room's values from A2's seed (`demo-room.env`), and one stand-in push payload for B5 to replace.

**Proof**: [launch](shots/launch-rooms-A.png), [scan demo on Glow A](shots/scan-demo-A.png) and [Glow B](shots/scan-demo-B.png), [push A match_created](shots/push-match-created-A.png), and a 12-second recording of both ([A](shots/skeleton-scan-and-push-A.mp4), [B](shots/skeleton-scan-and-push-B.mp4)).

**Still mocked**: every service. Each service module's `live` factory returns the AppCore preview mock, and the session starts signed in and onboarded so the tabs show (launch with `-GlowPreviewSession onboarding` or `signedOut` to see the other phases). The generated client isn't merged yet: `GlowAPI.client` and `GlowAPI.perform` switch on by themselves when A2's `Generated/Client.swift` lands. Sentry isn't linked (D36).

**Commands**

```
scripts/sim.sh setup              # create and boot Glow A and Glow B (newest iPhone Pro, newest iOS)
scripts/sim.sh build              # xcodegen + Debug build (log: ios/build/logs/build.log)
scripts/sim.sh install            # install and launch on both
scripts/sim.sh scan demo          # open the demo room's link on both
scripts/sim.sh allow-push A       # once per Simulator: grant notification permission
scripts/sim.sh push A match_created
scripts/sim.sh shot <name>        # docs/shots/<name>-A.png and -B.png
scripts/sim.sh record <name> 15   # 15 seconds of both screens (or Ctrl-C without a duration)
scripts/sim.sh test               # every test on Glow A
scripts/sim.sh test AppCore       # one module's tests
scripts/sim.sh lint               # SwiftFormat + SwiftLint, as CI runs them
```

If `xcode-select` points at the Command Line Tools, `sim.sh` uses `/Applications/Xcode.app` by itself. Builds live in `ios/build/` (about 2 GB with package checkouts); delete it any time.

**How to add a file to a module.** Drop the `.swift` file anywhere under `ios/Packages/GlowKit/Sources/{Module}/` (tests under `Tests/{Module}Tests/`). SwiftPM picks it up; there's no project file to edit, and no need to rerun xcodegen. Make anything other modules use `public`. Need resources (images, a string catalog)? Put them in `Sources/{Module}/Resources/` and ask for `resources: [.process("Resources")]` on your module in `Package.swift`. Need another package or module dependency? Ask under A3 (then A1) in Requests. Feature modules may depend on AppCore, APIClient, DesignSystem and service modules, never on each other.

**How to add a route.**
1. Add a case to `Route` in `AppCore/Navigation/Route.swift`, with its `presentation` (which tab to push on, or `.sheet`, or `.fullScreen`) and a `name` (no IDs in names: they go to logs and analytics).
2. Add a public entry view for it in the module that draws it, taking the case's values.
3. Map the case to that view in `ios/Glow/Navigation/RouteDestination.swift`.
4. Add a test to `AppCoreTests/RouterTests.swift`.
Steps 1, 3 and 4 touch A3's files, so ask in Requests or open a small `cross-owner` PR. Then any module navigates with `@Environment(\.navigate) private var navigate` and `navigate(.yourRoute(id))`. A screen that only one module ever shows (like the What did you notice sheet) doesn't need a Route.

**How to run one module's tests on its own.** `scripts/sim.sh test {Module}`, for example `scripts/sim.sh test FeatureRooms` (about 10 seconds once built). It runs `xcodebuild test -only-testing:{Module}Tests` on Glow A. Also: `test unit` (everything but UI tests), `test ui`, `test Glow` (the app target's tests). In Xcode, open `ios/Glow.xcodeproj` after `scripts/sim.sh build`, and click the diamond next to a test.

**Next wave needs**

- **Plugging in your service** (B1, B2, B3, B5): replace the body of your module's `live` factory (`SessionModule.live`, `LocationModule.live`, `ImagingModule.live`, `PushModule.live`, `RealtimeModule.live`) with your implementation. Keep the signature: `ios/Glow/AppComposition.swift` calls it. Your protocol is in `AppCore/Services/` and its mock in `AppCore/Mocks/`. Change both together (D40, pending A1).
- **Using a service in a feature**: `@Environment(\.dependencies) private var dependencies`, then `dependencies.location`, `dependencies.api` and so on. In previews and tests, inject `.environment(\.dependencies, .preview(location: MyMock()))`.
- **Calling the API**: once A2's client lands, `try await dependencies.api.perform { try await $0.getMe() }`. It throws `APIError`: `.notFound` (missing or not yours, P11), `.unauthorized`, `.rateLimited`, `.offline`, `.cancelled` or `.unexpected(status:)`. For a POST that's safe to repeat, send an `Idempotency-Key` header and it'll be retried on a dropped connection. Test with `GlowAPI.mock(.responses(["getMe": .json("…")]))`.
- **Analytics**: `dependencies.analytics.track(AnalyticsEvent("room_joined", ["via": "qr", "retries": .int(1)]))`. Names, keys and string values must be literals; numbers and flags are fine. Never coordinates, names, photos or message text (D35). Report unexpected errors with `dependencies.analytics.record(error, context: "rooms.join")`.
- **Logging**: `Logger(subsystem: Log.subsystem, category: "…")`, never `print` (SwiftLint fails it).
- **Entry views the app shows**: keep these public initializers (the app's `RouteDestination` and `RootView` call them): `OnboardingFlowView(step:)`; `SettingsView()`, `EditProfileView()`, `EditPhotosView()`; `RoomsHomeView()`, `RoomScannerView()`, `RoomCodeEntryView()`, `RoomJoinView(link:)`; `CheckInView(roomID:ticket:)`; `PauseView()`, `DeleteAccountView()`, `BlockSheet(context:)`, `ReportSheet(context:)`; `RoomHomeView(roomID:)`, `DeckView(roomID:)`; `MatchesListView()`, `MutualMomentView(matchID:)`, `MatchView(matchID:)`; `GlowView(matchID:)`; `ChatView(matchID:)`; `GalleryView()`.
- **B1**: the session drives the root. Emit `.signedOut`, `.onboarding(step)` and `.ready` from `states()`; the Router holds any room link until `.ready` (D39). Email codes show up in Mailpit at `http://127.0.0.1:54424` (A2).
- **B2**: room links arrive as `.joinRoom(RoomLink)` (already validated: slug, optional token). After the location check passes, `navigate(.checkIn(roomID, JoinTicket(ticket)))`. `scripts/sim.sh scan demo` and `at venue` / `at away` use `ios/fixtures/demo-room.env`.
- **B5**: `PushService.route(for:)` turns a tapped notification into a Route, and `foregroundPresentation(for:)` decides banners while the app is open. The app delegate already forwards both, plus the device token.
- **C3**: `GlowActivityAttributes` is in `LiveActivityShared`, which both FeatureGlow and the extension link.
- **D1**: `GlowUITests/SimulatorSetupUITests.swift` isn't a product test: `scripts/sim.sh allow-push` runs it to tap Allow on the notification prompt. Please keep it.

### CHIPS · Icebreaker chips

_2026-10-24, Wave 3._ `cross-owner` PR on `w3/chips` (touches C3's FeatureGlow, C4's FeatureChat, A1's `scripts/agent-env.sh` and the docs). Decisions CHIPS-D1 to CHIPS-D4. David approved the feature.

**Built** (client only: no endpoint, no contract change, nothing stored on the server)

- **FeatureGlow, `GlowSayAloud.swift`**: under the code word and meeting spot, "Need an excuse?" and three lines to say aloud: "Are you {word}?", "We both noticed. Hi.", "Found you. Shall we sit by {spot}?" For reading only (nothing is tappable). The spot line is left out when the glow has no spot. VoiceOver reads each as "Suggested opener: …".
- **FeatureChat, `ChatIcebreaker.swift`**: in an empty, open chat, up to three chips: "Hey, glad we both noticed. What brought you to {room}?", "Are you {word}? I'm the other one." (only with a glow word), "Want to find a seat at {spot}?" (only with a meeting spot, so not after Just chat). Tapping one fills the composer and focuses it; it never sends. The person edits it and sends it through the normal path. The chips vanish as soon as either person has a message in the thread. `ChatHeader` now also carries `roomName`, `codeWord` and `meetingSpot`, read from the `GET /api/matches/{id}` call the header already made. Using a chip logs `chat_icebreaker_used` with `chip` = `room`, `word` or `spot`, never text.
- **Tests**: `ChatIcebreakerTests.swift` (copy and interpolation, omission, Just chat, hidden after either person writes, tapping fills and never sends, the edited text is what is sent, no marker on a sent chip, analytics ID only), `IcebreakerReachabilityTests.swift` (source-level: no other module mentions a chip type or a chip's words, no pre-match module depends on FeatureGlow or FeatureChat, and the app builds `GlowView` and `ChatView` only for their routes), `GlowSayAloudTests.swift`, and snapshots at the default and largest text size: chat with three chips, with a filled composer, and Just chat; the glow screen's existing snapshots were re-recorded because they now include the lines.

**For C3 and C4**: your modules gained the files above, and `GlowOnView`, `ChatThread`, `ChatModel`, `ChatHeader`, `LiveChatAPI.header` and `PreviewChatAPI` (a `header:` argument) changed a little. C4-D5's "no openers" half is superseded (CHIPS-D1); messages still show verbatim.

**For D1**: the chips are plain `Button`s with the accessibility label "Suggested opener: …" in the chat, and static text on the glow screen.

**For D4**: new strings: "Need an excuse?", "Are you %@?", "We both noticed. Hi.", "Found you. Shall we sit by %@?", "Need a way to start?", "Hey, glad we both noticed. What brought you to %@?", "Are you %@? I'm the other one.", "Want to find a seat at %@?", "Suggested opener: %@", "Puts it in the message box. Nothing is sent until you send it.", "Tap one to start your message. You can change it first."

**For A1**: `scripts/agent-env.sh` has a new row, `CHIPS 51` (port 3141), CHIPS-D4.

### X1 · Blind backend

_2026-10-25, Blind mode (docs/briefs/blind-mode.md). Branch `blind/x1-backend`._

**Contract is in: commit `a598fa9`** ("X1: Blind mode contract (/api/blind), codegen and 501 stubs"). **X2: merge `blind/x1-backend` (at least `a598fa9`) and build `LiveBlindService` on the generated Swift client.** The routes answer 501 until the next commits land; the shapes don't change.

Operations (tag `blind`, in the Swift client; `Client.blindX(...)`):

| operationId | Endpoint | Body | Reply |
| --- | --- | --- | --- |
| `blindGetMe` | `GET /api/blind/me` | | `BlindMe {member, hasPhoto, rightRemaining, rightCount, canDrop}` |
| `blindJoin` | `POST /api/blind/join` | | `BlindMe` (409 `onboarding_incomplete`) |
| `blindLeave` | `DELETE /api/blind/join` | | 204 |
| `blindGetDeck` | `GET /api/blind/deck?limit=1..20` | | `BlindDeck {cards: [BlindCard {id, photoUrl}]}` |
| `blindSwipe` | `POST /api/blind/swipe` | `{targetId: cardId, kind: pass\|like\|love}` | `{rightRemaining, rightCount}` (409 `right_cap_reached`) |
| `blindGetPool` | `GET /api/blind/pool` | | `{rightCount, rightRemaining, canDrop}` |
| `blindGetPoolCards` | `GET /api/blind/pool/cards` | | `BlindDeck` (Guess Who cards) |
| `blindGetCardImage` | `GET /api/blind/cards/{cardId}/image?exp&sig` | | JPEG. Use `photoUrl` as is (relative, bearer token, 60 s) |
| `blindGetDrop` | `GET /api/blind/drop` | | `{ready, demo, nextDropAt, rightCount, canDrop}` |
| `blindOpenDrop` | `POST /api/blind/drop` | | `{opened, chats: [{id, codename}]}` (409 `drop_not_ready`) |
| `blindListChats` | `GET /api/blind/chats` | | `{chats: [{id, codename, status, lastMessage?, unread}]}` |
| `blindGetChat` | `GET /api/blind/chats/{id}` | | `BlindChat {id, codename, status, iTappedReveal, theyLeft, partner?, guessCorrect?}` |
| `blindListMessages` | `GET /api/blind/chats/{id}/messages?after=` | | `{messages: [{id: Int, mine, text, at}]}` |
| `blindSendMessage` | `POST /api/blind/chats/{id}/messages` | `{text, confirm?}` | `{message?}` or `{warning: {reason}}` (409 `chat_closed`) |
| `blindReveal` | `POST /api/blind/chats/{id}/reveal` | | `{status}` |
| `blindLeaveChat` | `POST /api/blind/chats/{id}/leave` | | `{ok}` |
| `blindGuess` | `POST /api/blind/chats/{id}/guess` | `{guessId: poolCardId}` | `{ok}` |
| `blindBlock` | `POST /api/blind/chats/{id}/block` | | `{ok}` |
| `blindReport` | `POST /api/blind/chats/{id}/report` | `{reason (1..500), category?: ReportReason}` | `{ok}` |
| `blindGetPartnerPhoto` | `GET /api/blind/chats/{id}/photos/{n}?exp&sig` | | JPEG, only once revealed. Use `partner.photos[n]` as is |
| `blindAdminDrop` (admin, not in Swift) | `POST /api/admin/blind/drop` | | `{opened}` |
| `blindCronDrop` (cron, not in Swift) | `GET /api/cron/blind-drop` | | `{opened}` |

Differences from Double Blind's contract, for X2: absent instead of `null` for `lastMessage` and for `message` in a send reply (X1-D2); `photoUrl` and `partner.photos` are relative signed links fetched with the bearer token (like Glow's card images); block and report take the chat ID in the path; report adds an optional `category`. Not a member answers 404 on everything except `me` and `join` (P11). New error codes: `right_cap_reached`, `drop_not_ready`, `chat_closed`. Constants in `GlowConstants`: `blindRightSwipesPerDay` (20), `blindDropMinRightSwipes` (5), `blindMaxOpenChats` (5), `blindDeckPageMax` (20), `blindReportMaxChars` (500), `blindDropReplayWindow` (300 s).

**For A1**: `scripts/agent-env.sh` gains `X1 61` and `X2 62` (ports 3151, 3152); `scripts/codegen.sh` accepts `X` agent IDs in `x-owner`; AGENTS.md lists the Blind paths (X1 server and database, X2 FeatureBlind).
**For B7**: `AdminReport.context` is now `AdminReportContext` (ReportContext plus `blind_chat`), so Blind reports show in the queue.

## X2 · Blind mode, iPhone

Branch `blind/x2-ios`. The Blind tab, FeatureBlind and the Blind service protocol, models and mock are in. Every screen runs on the mock (`-GlowPreviewSession ready -GlowDebugRoute blind -GlowDebugBlind swiping|newcomer|dropReady|chatting|revealed|capReached`, plus `-GlowDebugBlindSection chats`, `-GlowDebugBlindAutoOpen YES` and `-GlowDebugBlindDropClosed YES`). `LiveBlindService` is written against X1's `/api/blind/*` contract but not yet run against X1's server. Details and what is left: `docs/qa/x2.md`.
