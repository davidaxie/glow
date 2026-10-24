# Handoffs

What each agent built, what's still mocked, and what the next wave needs. Requests for another agent go under that agent's ID in **Requests**. Each agent keeps its own section under **Status** up to date. Newest notes go at the top of each section.

## Needs David

Things only David can do. None of these block Wave 0 work locally.

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

## Requests

### For A1

_From B9, 2026-10-24._ PRs [#5](https://github.com/davidaxie/glow/pull/5) (release pipeline) and [#17](https://github.com/davidaxie/glow/pull/17) (`cross-owner`).

1. **Signing in `ios/project.yml`**, PR #17: 16 lines that make Release device builds of `Glow` and `GlowLiveActivity` sign manually with Apple Distribution and the profiles `Glow App Store` and `Glow Live Activity App Store` (B9-D1). Debug, Simulator and CI builds don't change. `ios/fastlane/ship check` lists this as the one non-Apple blocker for `beta`, and a test in `ios/fastlane/test` stops skipping once it's merged. #5 doesn't depend on #17 to merge; they can go in either order.
2. **`Shared.xcconfig` values, later.** When David has them, `DEVELOPMENT_TEAM` (the Team ID) and `GLOW_WEB_DOMAIN` go in `ios/Glow/Config/Shared.xcconfig`, which is yours now. The release lane refuses to ship while either is empty or the placeholder.
3. **A privacy policy page** at `https://{DOMAIN}/privacy`. App Privacy and external TestFlight testing need a policy URL. A draft in Glow's voice is in `docs/RELEASE.md` ("Privacy policy draft"), with `{CONTACT_EMAIL}` to fill in. The path isn't in the ownership map, so it's yours to place or assign.
4. **Privacy manifest, two candidates to declare** (D43 says more, not less): `NSPrivacyCollectedDataTypeEmailsOrTextMessages` for chat messages (Apple's definition is about message contents; the manifest has them only as Other User Content), and `NSPrivacyCollectedDataTypeDeviceID` for the push token stored with each account. If you add either, run `ios/fastlane/ship privacy_answers`, commit `ios/fastlane/app-privacy.json` and tell B9 to update the table in `docs/RELEASE.md`. CI's **Release iOS → Release checks** job fails while the two disagree.
5. **CI.** `.github/workflows/release-ios.yml` adds one Ubuntu job (**Release checks**, about a minute) on PRs that touch release files: the lane helper tests and `fastlane check`. The macOS TestFlight job only runs on `beta-*` and `wave-*-done` tags or by hand, and skips with a notice until the Apple secrets exist. After you tag `wave-1-done`, the build number shows in that run's summary.

_From B8, 2026-10-24._

1. **Rate limit every route in the helper.** In `route()` (`server/src/server/http/route.ts`), right after `authenticate`, add `await limitRequest(operationId, req, user)` from `@/server/ratelimit`. It picks the policy per operation (`policyForOperation`, a test covers every operation in the contract), keys by person or by client IP, throws your `rateLimited()` 429, and skips `runPurge`. Then no handler has to remember to call it.
2. ~~**`reason` on errors.**~~ Done in #13. `photoRejected(reason)` is built on `unprocessable`, and `ModerationUnavailableError` passes `reason: 'moderation'`.
3. **`tests/setup.ts`:** please also delete `ANTHROPIC_API_KEY` before each test, so a key exported in someone's shell never makes the suite call the real API (B8's live test reads the key once at import, before setup runs).

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

### For A2

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

_From A1, 2026-10-24._ `HttpError` and `errorBody` now carry the contract's optional `reason`: `throw unprocessable('photo_rejected', 'Try another photo.', { reason: 'face_visible' })` sends 422 `{ error: { code, message, reason } }`. `conflict(code, message)` covers 409s like `onboarding_incomplete`. The route helper now validates against the generated contract, so `addProfilePhoto` takes A2's base64 JSON body, not multipart.

_From B8, 2026-10-24._ Profile photo moderation, in `@/server/moderation` (exact exports under B8 in Status):

```ts
import { moderateImage, photoRejected } from '@/server/moderation';

const verdict = await moderateImage('profile', jpegBytes); // Uint8Array, the JPEG as uploaded
if (verdict.decision === 'rejected') throw photoRejected(verdict.reason); // 422 photo_rejected
// verdict.decision is 'approved' or 'held': store it as profile_photos.moderation_status.
```

It throws `ModerationUnavailableError` (an `HttpError`, 503 `unavailable`, reason `moderation`) on a timeout or outage. Let it propagate and don't store the photo (B8-D2). Held photos (possibly under 18) are never shown until B7 approves them. Rate limits: `addProfilePhoto` and `deleteProfilePhoto` use the `photos` policy, `updateProfile` uses `account`, `testLogin` uses `signIn` (per IP). If A1 wires `limitRequest` into the route helper (For A1 below), you don't call anything; otherwise `await rateLimit(user.id, 'photos')` first thing in the handler.

### For B2

_From A1, 2026-10-24._ 1: the registry is wired, and `server/app/api/rooms/[id]/route.ts` exists as a 501 stub for `getRoomState`; it's yours (listed in your `AGENTS.md` row), so replace the stub. 2: done. 3: `server/src/env.ts` has two optional variables, both validated and optional everywhere: `TESTFLIGHT_URL` (must be `https://testflight.apple.com/...`) and `APPLE_APP_ID` (`TEAMID.bundle.id`, like `ABCDE12345.com.davidxie.glow`). Please use `APPLE_APP_ID` for the link file rather than `APNS_TEAM_ID` plus `APNS_BUNDLE_ID`: the APNS variables only exist together with the push key, so a preview without push couldn't serve the link file. Read them with `getEnv()`.

### For B3

_From A3, 2026-10-24._ `ios/fixtures/photos/` has four synthetic, faceless outfit images (D44). Add fixture photos with real faces that the people in them agreed to (or freely licensed ones) for the blur tests. `ios/fixtures/` is A3's, so add them in a `cross-owner` PR or ask A1.

_From B8, 2026-10-24._ Card photo moderation fails closed:

```ts
import { moderateImage, photoRejected } from '@/server/moderation';

const verdict = await moderateImage('card', jpegBytes); // throws ModerationUnavailableError (503) on timeout or outage
if (verdict.decision !== 'approved') throw photoRejected(verdict.reason);
// reasons: face_visible, nudity, no_outfit, no_person, possibly_minor, unreadable
```

Moderate before uploading to storage, so a rejected photo is never stored. In tests, `await moderationFixtureJpeg(['face_visible'])` gives a JPEG the local fake rejects (also `nudity`, `no_outfit`, `no_person`, `possibly_minor`, `slow` for the timeout, `error` for an outage); `moderationFixtureJpeg([])` is approved. Rate limit policy: `checkin` (10 per 10 min) for `createCheckin`, `join` for `joinRoom`, `resolveRoom` and `leaveRoom`.

### For C4

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

### For B5

_From B9, 2026-10-24._ Every TestFlight build is the **Release** configuration, signed for the App Store, so its entitlement is `aps-environment = production` (B9-D1); Debug builds from Xcode are `development`. So register `production` in Release builds and `sandbox` in Debug (a compile-time `#if DEBUG` is enough; there's no development-signed Release build in the pipeline). On the server, the one `.p8` key in `APNS_*` covers both environments; send to `api.push.apple.com` for `production` rows and `api.sandbox.push.apple.com` for `sandbox` ones. B9's Done-when box "Push works on a TestFlight build, through production" is checked with your sender, two iPhones and a mutual tap (docs/RELEASE.md, step 9).

_From A3, 2026-10-24._ Please replace `ios/fixtures/push/match_created.apns` (A3's stand-in: lock screen text plus a match ID) with fixtures built from `contracts/events.json`, one per event. `scripts/sim.sh push A <event>` picks up `ios/fixtures/push/<event>.apns`. The spec's Realtime module is `GlowRealtime`.

### For B6

_From A3, 2026-10-24._ The app icon (`ios/Glow/Assets.xcassets/AppIcon.appiconset`), the accent color and `LaunchBackground` (the launch screen color) are A3's placeholders; they're yours to replace. `.swiftlint.yml` has a marked spot under `custom_rules` for your "no colors or fonts in feature modules" rule.

### For B9

_Answered by B9, 2026-10-24, in PRs #5 and #17._ The team stays in `DEVELOPMENT_TEAM` in `Shared.xcconfig` (David fills it in; the lane refuses to ship while it's empty). The Release Supabase values, `POSTHOG_KEY` and `SENTRY_DSN` go in from CI secrets through an `xcodebuild -xcconfig` override, never into git (B9-D2). Release `aps-environment = production` needed manual App Store signing for the archive (#17, B9-D1). The App Privacy answers are generated from the manifest and CI fails if they drift (`ios/fastlane/app-privacy.json`).

_From A3, 2026-10-24._ Signing lives in `ios/Glow/Config/Shared.xcconfig` (`DEVELOPMENT_TEAM` is empty, `CODE_SIGN_STYLE = Automatic`), so set the team there. `GLOW_WEB_DOMAIN` (same file) is {DOMAIN}. Release `SUPABASE_URL` and `SUPABASE_ANON_KEY` are empty in `Release.xcconfig`: pass them, and `POSTHOG_KEY` (and `SENTRY_DSN` once Sentry is back, D36), as xcodebuild settings from CI. `aps-environment` is `development` in Debug and `production` in Release. App Privacy answers should match `ios/Glow/PrivacyInfo.xcprivacy` (D43).

## Status

### B9 · Release and TestFlight

_2026-10-24, Wave 1._ PR [#5](https://github.com/davidaxie/glow/pull/5) on `w1/b9-release`, plus the `cross-owner` signing change in PR [#17](https://github.com/davidaxie/glow/pull/17) for A1. The manual is [`docs/RELEASE.md`](RELEASE.md).

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

**Proof (local, Xcode 26.0.1, no Simulators used).** `ios/fastlane/ship test`: 33 runs, 0 failures (1 skip until #17 merges). `ios/fastlane/ship check`: passes and lists what `beta` still needs. `ios/fastlane/ship verify_release`: an unsigned Release device build passes every check that doesn't need signing (placeholder domain and empty Supabase values show as warnings). A Release build with a test `-xcconfig` override put build 42 in both the app and the Live Activity and the hosted Supabase URL in the Info.plist. `ios/fastlane/ship beta` and `status` without credentials stop with the list of blocked items. With #17: `-showBuildSettings` gives Manual + Apple Distribution + both profiles for Release device builds only, a Release Simulator build succeeds, and a signed Release device build asks for the team and the "Glow App Store" profile.

**Done when**

- [ ] `fastlane beta` uploads a build that installs from TestFlight on a real iPhone. Blocked: needs Apple Developer account (Needs David, item 11, steps 1 to 9). The lane, workflow and checks are built and tested up to the first Apple call.
- [ ] Push works on a TestFlight build, through production. Blocked: needs Apple Developer account (the APNs key, step 3) and B5's sender. Release builds carry `aps-environment = production` once #17 is in.
- [ ] The public TestFlight link is approved, or the review status is in `docs/HANDOFFS.md`. Blocked: needs Apple Developer account. Status is in the table above; the `external` lane submits the review.
- [x] `docs/RELEASE.md` explains how to ship a new build with one command: `ios/fastlane/ship release`.

**Still mocked or blocked**: nothing in B9's paths is mocked. Everything that talks to Apple is blocked on the account; the hosted Supabase values on the Supabase cloud project; the domain on David's choice.

**Next wave needs**

- **Everyone:** to get a build onto phones, merge to `main` and run `ios/fastlane/ship release` (once the account exists). Testers get it in TestFlight minutes later.
- **B1, B2:** tell B9 here when sign-in and room joining work on `main`, so the first external review goes in (Build plan: Apple's review runs while everyone keeps building).
- **B2:** the `/r/{slug}` page shows `TESTFLIGHT_URL` and the link file lists `APPLE_APP_ID` (A1's variables); David sets both in Vercel (RELEASE.md steps 11 and 12).
- **D2, D3:** TestFlight builds go through the release gate above; `ios/fastlane/ship verify_release` reproduces it locally on an unsigned build.
- **Anyone changing `project.yml`, `Info.plist`, entitlements, the xcconfigs or the privacy manifest:** run `ios/fastlane/ship check` and `ios/fastlane/ship verify_release`.

### B6 · Design system

_2026-10-24, Wave 1, first PR (tokens and basic components)._ Branch `w1/b6-design-tokens`. The full module (tag picker, card tile, code fields, takeover, GlowSurface, haptics, icon, README) follows on `w1/b6-design`.

**Built**

- `DesignSystem/Tokens`: every color token from the spec as SwiftUI styles (`.glowBackground`, `.glowSurface`, `.glowSurfaceRaised`, `.glowTextPrimary`, `.glowTextSecondary`, `.glowLine`, `.glowAccent`, `.glowDanger`, plus `.glowOnAccent` for text on accent and danger fills); the exact values in `GlowPalette` (`GlowRGB`, hex); the eight glow colors as `GlowHue` (raw values are the contract's `GlowColor`) with their text color `ink`; tag swatches as `GlowSwatch` (raw values are the contract's `TopColor` and `HairColor`); type as `GlowTextStyle` (`.glowFont(.title)`, `.font(.glow(.body))`), all Dynamic Type; `GlowSpacing` (4-point grid), `GlowRadius` (12 and 20), `GlowSize`; `GlowMotion` (0.2 s ease-out, the reveal spring, Reduce Motion fallbacks, `glowAnimation(_:value:)`) and `GlowPulse` (1.25 s, flash-safe); `GlowContrast` (WCAG math) and `GlowPalette.textPairings`.
- `DesignSystem/Components`: `GlowButtonStyle` (`.glowPrimary`, `.glowSecondary`, `.glowQuiet`, `.glowDanger`, `.glow(_:size:)`, plus `.glowLoading(_:)`), `GlowChip` and `GlowChipStyle`, `GlowFlowLayout` (wrapping rows), `.glowSheet(isPresented:)`, `.glowSheet(item:)`, `.glowSheetPresentation()` and `GlowSheetContent`, `GlowToast` and `.glowToast($message)`, `GlowStepHeader`, `GlowEmptyState`.
- `GalleryView` (Settings > Debug > Gallery): every token and component above in every state (normal, pressed, loading, disabled, selected). Compiled out of Release.
- Tests: every text pairing and every glow color's ink meets WCAG AA 4.5:1, the pulse never dims below 70% and runs under once a second, tokens match the spec, glow colors and swatches match `contracts/openapi.yaml`, and snapshots of every Gallery section at the default and the largest text size.

**Proof**: the Gallery on "Glow A (B6)", top to bottom, in `docs/shots/b6-gallery-page-1-A.png` to `b6-gallery-page-12-A.png`, plus [a live sheet](shots/b6-gallery-sheet-presented-A.png) and [a live toast](shots/b6-gallery-toast-presented-A.png). Full-section snapshots at both text sizes are in `ios/Packages/GlowKit/Tests/DesignSystemTests/__Snapshots__/`.

**Decisions**: B6-D1 (dark ink on every glow color), B6-D2 (dark ink on filled buttons and selected chips), B6-D3 (the pulse brightens, never darkens).

**Using it** (feature modules): `import DesignSystem`, then `Text("Hi").glowFont(.body).foregroundStyle(.glowTextPrimary)`, `Button("Check in") { … }.buttonStyle(.glowPrimary)`, `.background(.glowBackground)`. Never `Color(...)`, `UIColor`, `.font(.title)` or `Font.system` in a feature: a SwiftLint rule (sent to A1 as a `cross-owner` PR) fails them. Need a color or style that isn't here? Ask under **For B6**.

**Still mocked**: nothing. DesignSystem depends on nothing but SwiftUI.

### B8 · Safety, moderation and cleanup

_2026-10-24, Wave 1, interfaces._ PR on `w1/b8-safety-interfaces`; the rest of B8 follows on `w1/b8-safety`.

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

**Still mocked**: Claude runs only with `ANTHROPIC_API_KEY`; without it, local runs use the fake (B8-D1). Upstash runs only with `UPSTASH_REDIS_REST_*`; locally it's in memory.

### A2 · Contracts and database

_2026-10-24, Wave 0._ PR [#2](https://github.com/davidaxie/glow/pull/2) on `w0/a2-contracts`. The reference is [`docs/CONTRACTS.md`](CONTRACTS.md): one line per endpoint, event, constant and database function.

**Built**

- `supabase/migrations/0001_a2_init.sql`: enums, every table in the data model (plus `location_checks` and `room_activity`, D17 and D30), constraints and indexes. RLS is on everywhere with no policies, and grants and default privileges are closed to `anon` and `authenticated` (D28). Every database function from the spec plus the ones routes need (CONTRACTS.md), all security definer with `search_path = ''`, with advisory locks on the pair in `record_tap`, the viewer in `get_deck` and the room in `start_glow`. Also Realtime authorization (D27) and private buckets `profile-photos` and `room-cards`.
- `supabase/seed.sql`: the demo room, 4 meeting spots, and the test people below. `supabase db reset` runs clean.
- `contracts/openapi.yaml` (every endpoint, admin included, with schemas, errors and examples), `contracts/events.json` and `contracts/constants.json`.
- `scripts/codegen.sh` (`pnpm codegen`): checks the contract (P1 field names, no 403, events against openapi), then generates `server/src/contracts` (types, zod schemas, the route registry, constants, events with `apnsRequestFor`, database types), the Swift client and constants in `APIClient/Generated`, `supabase/tests/database/000_constants.test.sql`, and the tables in CONTRACTS.md. A second run changes nothing. `--verify` compiles both clients on their own.
- pgTAP, 390 tests in `supabase/tests/database/`: lockdown of every table, function and bucket; Realtime channels; every deck rule including show me and blocks both ways; the tap cap and TTL; 50 simultaneous pairs making exactly 50 matches (it fails, 41 of 50, with the pair lock removed); choosing and glow, including color plus code word uniqueness; check-ins, 18+ and purge; blocks, reports and chat.

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

- **Everyone:** run `pnpm codegen` after touching `contracts/` or `supabase/migrations/`, and commit the result. Contract changes after Checkpoint 1 go through A1 in a `contract-change` PR.
- **B1:** a trigger creates each `profiles` row on sign-up, and the database refuses under-18 birthdates (error `under_18`). `onboarding_step` is yours to advance. Use `@glow.test` addresses for test sign-in. Profile photo paths are `profile-photos/{userId}/{photoId}.jpg` (checked by a constraint).
- **B2:** write a `location_checks` row (pass, fail or demo_skip, plus an accuracy bucket, never coordinates) for every join and Find check. Leaving: `update checkins set left_at = now()` and delete the photo. `GET /api/rooms/{id}` calls `get_room_state`. `rooms.static_qr_token` and `qr_secret` (hex) are on the room row.
- **B3:** generate the card ID, upload to `room-cards/{roomId}/{cardId}.jpg`, then call `create_checkin` and delete any `replacedCardPaths`. The image route uses `card_visible_to`, and match photos use `match_photo_path`.
- **B4:** `get_deck`, `record_tap` and `list_matches`. The cap and race tests already pass in the database.
- **B5:** `eventCatalog`, `userTopic`, `roomTopic` and `apnsRequestFor` in `@/contracts` build every channel name and push payload from events.json. `userIds` in function results tell you who to notify.
- **B7:** admin operations are in the contract. Metrics come from `room_activity`; ban with `profiles.banned_at`; remove a card with `checkins.visible = false`.
- **B8:** `block_user`, `create_report`, `purge_expired` (it returns photo paths to delete, and events to send). Pausing is `profiles.paused`, which every deck rule reads.
- **C2, C3, C4:** `set_choice`, `start_glow` (pass C3's word list), `glow_met`, `cancel_glow`, `get_match`, `send_message` and `unmatch`. Their result shapes are in CONTRACTS.md.

### A1 · Integrator and repo

_2026-10-24, Wave 0._ PR [#1](https://github.com/davidaxie/glow/pull/1) on `w0/a1-repo`.

**Built**

- pnpm workspace (`package.json`, `pnpm-workspace.yaml`) with one package, `server`: Next.js 16.4 App Router, TypeScript 6 strict, ESLint 9 with the Next config, Prettier, Vitest 4. Node 24 (`.nvmrc`).
- `server/src/env.ts`: every server variable validated with zod, with local, preview and production profiles (D1). A wrong environment stops `next dev`, `next build` and `next start` with a message naming each variable. `server/.env.example` describes all of them.
- `server/src/server/auth`: `requireUser(req)` checks the Supabase access token with Supabase Auth (D3), `requireCron(req)` checks the cron secret in constant time.
- `server/src/server/http`: the typed route helper, `route(operationId, handler)`. Sign-in from the contract, 404 for malformed IDs and for any 403 (P11), 400 with field paths but no values, only contract fields in replies (P1), `no-store` everywhere, and 500s logged without bodies (P2). See "Writing a server route" in `AGENTS.md`.
- A route file answering 501 for all 32 endpoints in the spec's API contract, a JSON 404 for any other `/api` path, and `proxy.ts` hiding `/api/dev/*` unless test sign-in is on (D6).
- `server/src/server/log.ts` (redacting JSON logger) and Sentry in `server/instrumentation.ts`, off unless `SENTRY_DSN` is set and collecting nothing personal (D7).
- Scripts: `scripts/env-setup.sh`, `scripts/dev-token.sh`, `scripts/smoke.sh`.
- CI (`.github/workflows/ci.yml`) and Vercel deploys (`.github/workflows/vercel.yml`, `server/vercel.json`).
- `AGENTS.md` with the rules and privacy invariants word for word, the ownership map from every brief, and every command. Tests fail if those sections drift from the build plan or if a file in git has no owner.

**Commands**: see the Commands section of `AGENTS.md`. The short version: `pnpm install`, `pnpm db:start`, `pnpm env:setup`, `pnpm dev`, then `pnpm check` before you push.

**Ownership map**: see the Ownership map in `AGENTS.md`.

**Preview URL**: none yet. Vercel isn't linked (Needs David, item 1).

**Still mocked**: the operation registry. `server/src/server/http/contract-placeholder.ts` stands in for A2's generated `server/src/contracts` with the right paths, methods, auth and path params, and empty request and response schemas. A1 swaps it for the generated registry when A2's PR merges, then deletes the placeholder.

**Next wave needs**: build your endpoint by replacing `notImplemented` in its route file (the owner is named at the top of each file). Get a local token with `pnpm -s dev:token`, and check every endpoint with `pnpm smoke`.

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
