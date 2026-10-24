# Decisions

When the spec is unclear, agents pick the option that protects privacy more and record it here. One entry per decision, newest at the bottom.

Format: `## D{n} · {agent} · {short title}`, then the question, the choice, and why.

From Wave 1, agents work in parallel, so each takes its own block of numbers instead of the next one: B2 D46–D50, B8 D70–D72, A1 D90–D99 so far. Pick an unused block of ten and keep to it. If two PRs still collide, A1 renumbers the later one when merging and fixes its references.

## D1 · A1 · Which server variables are required where

**Question.** The spec lists every server variable but not which ones local development needs. `pnpm dev` must work on a fresh clone, and a missing variable must still stop the server.

**Choice.** `server/src/env.ts` picks a profile from what Vercel sets (`VERCEL_ENV`), and requires:

| Variable | Local (`pnpm dev`, CI, tests) | Vercel preview | Vercel production |
| --- | --- | --- | --- |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` | required | required | required |
| `JOIN_TICKET_SECRET`, `CARD_URL_SECRET`, `CRON_SECRET` | required | required | required |
| `ANTHROPIC_API_KEY`, `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN` | optional | required | required |
| `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID` | optional (all four or none) | optional (all four or none) | required |
| `POSTHOG_KEY`, `SENTRY_DSN` | optional | optional | optional |
| `ALLOW_TEST_LOGIN` | optional, local Supabase only | refused | refused |

On Vercel the server also refuses a localhost or non-https `SUPABASE_URL`, the local Supabase demo keys, the placeholder secrets from `.env.example`, and `ALLOW_TEST_LOGIN`. Everywhere, it refuses a service key in the anon slot (and the reverse), the same secret reused for two jobs, and secrets under 32 random bytes. A Vercel deploy with no `VERCEL_ENV` counts as a preview.

**Why.** Previews are reachable from the internet, so they get moderation and rate limits like production. Push isn't a privacy control, so previews can run before the Apple account exists. The checks run in `next.config.ts`, so `next dev`, `next build` and `next start` all stop before serving anything, and again in `instrumentation.ts` in case the runtime env differs from the build's. Messages name the variable and what's wrong, never its value.

## D2 · A1 · Local Supabase keys in `.env.example`

**Question.** Should `.env.example` carry working local values?

**Choice.** Yes for the local Supabase URL and its publishable and secret keys, which are the same public demo keys on every machine and only reach a Supabase on 127.0.0.1. The three signing secrets are placeholders marked `local-dev-only`; `pnpm env:setup` replaces them with fresh random ones and copies the real keys from `supabase status`. D1's Vercel checks reject all of these values.

**Why.** It makes a fresh clone work with one copy, while nothing in the file is a real secret or can reach real data.

## D3 · A1 · Checking access tokens with Supabase on every request

**Question.** Verify Supabase access tokens locally (JWKS, fast) or ask Supabase Auth (`auth.getUser`, one network call)?

**Choice.** `requireUser` asks Supabase Auth on every request, after cheap local checks that reject malformed, expired or non-user tokens without a network call. It also refuses anonymous Supabase users and banned users, and answers 503 (not 401) if Auth is unreachable or slower than 3 seconds, so the app doesn't sign people out on a blip.

**Why.** A deleted, banned or signed-out account stops working immediately instead of up to an hour later when its token expires. If deck latency ever needs it (B4's 300 ms p95), switch to local JWKS verification plus a short cache, and record the trade-off here.

## D4 · A1 · 401, 404 and malformed IDs

**Question.** P11 says not-allowed is 404. What about no sign-in, and IDs that aren't valid UUIDs?

**Choice.** No or bad sign-in is 401 for every route, decided before anything is looked up, so it reveals nothing about any resource. A path ID that fails validation is 404, like any other ID that names nothing you can see. The route helper turns any 403 into the exact same 404 body, and there's no `forbidden()` helper. Unknown `/api` paths get the same JSON 404. Dev-only routes (`/api/dev/*`) are a 404 unless test sign-in is on.

## D5 · A1 · Replies carry only contract fields

**Question.** What happens when a handler returns more than the contract declares?

**Choice.** The route helper parses every JSON reply with the contract's zod schema and sends the parsed result, so undeclared fields are dropped before they leave the server. A reply that doesn't match is a 500 with a generic body; the log names the operation and the failing field paths, never the values. A handler may return its own `Response` only where the contract says `raw` (images, HTML, the link file).

**Why.** It turns P1 from a convention into something a stray `select *` can't break.

## D6 · A1 · Test sign-in has three locks

**Choice.** `POST /api/dev/test-login` only exists when `ALLOW_TEST_LOGIN` is on, the profile is local, and `SUPABASE_URL` is a local address. env.ts refuses the other combinations at startup, and `proxy.ts` answers 404 for `/api/dev/*` otherwise. B1 still compiles the client side out of Release builds.

## D7 · A1 · Logs and Sentry collect nothing personal

**Choice.** All server code logs through `logger` (`server/src/server/log.ts`), which writes JSON lines and redacts any field whose name contains words like `lat`, `lng`, `location`, `accuracy`, `name`, `email`, `body`, `message`, `text`, `token`, `photo` or `ip`. ESLint forbids `console` elsewhere. The route helper logs only the operation, method, status and time. Sentry runs only when `SENTRY_DSN` is set, with every `dataCollection` option off (no headers, cookies, bodies, query strings, user info or stack-frame variables), and a `beforeSend` that keeps only the request's method and path. No source maps are uploaded yet.

**Why.** P2 says coordinates are never logged. Redaction by field name is a safety net under the rule "log IDs and outcomes only", and stack-frame variables are the easiest way for a coordinate to reach Sentry by accident.

## D8 · A1 · No CORS

**Choice.** The API sends no CORS headers. The app is native and the admin web is same-origin, so no other website can call the API from a browser with someone's session.

## D9 · A1 · Vercel deploys from GitHub Actions

**Choice.** `.github/workflows/vercel.yml` builds and deploys with the Vercel CLI: a preview for every PR (its URL posted on the PR) and production for main. `server/vercel.json` turns off Vercel's own Git deploys so nothing deploys twice. The workflow skips cleanly until the Vercel secrets exist.

**Why.** The build runs our env validation with the target environment's variables, so a deploy with a missing variable fails loudly instead of going live.

## D10 · A2 · Local Supabase ports are 544xx, not 543xx

**Question.** `supabase start` with the default ports failed its health check on the team Mac.

**Choice.** `supabase/config.toml` uses API 54421, DB 54422, Studio 54423, Mailpit 54424 and shadow DB 54420. CleanMyMac listens on 127.0.0.1:54321, and A1's scratch stack used 5532x. `project_id` is `glow`. CI reads the same file, so CI uses these ports too.

## D11 · A2 · Placeholder venue for the demo room

**Question.** The Cal Hacks venue isn't confirmed, but the seed needs a room center.

**Choice.** The seeded `demo` room is centered on the Palace of Fine Arts, San Francisco (37.8029, -122.4484, radius 200 m, America/Los_Angeles), labeled "Glow demo room (test data)". This is a **placeholder**. To change it, edit the one `insert into public.rooms` in `supabase/seed.sql` (local only). The real event room is made through B7's admin web, not the seed.

## D12 · A2 · "Per day" means the room's calendar day

**Question.** Caps are per day and the deck shuffle uses today's date, but in which timezone? A UTC day resets at 5 pm in California, in the middle of an evening event, which would hand everyone 3 new taps mid-event.

**Choice.** `rooms.timezone` (default America/Los_Angeles). The tap cap, view cap and shuffle seed use the room's local date.

## D13 · A2 · The view cap counts different cards

**Choice.** `CARD_VIEWS_PER_ROOM_PER_DAY` counts different cards shown per room per day. Seeing the same card again (refresh, scrolling back) is free. `get_deck` records the views it hands out, under a per-viewer lock, so parallel requests can't beat the cap.

**Why.** Refreshing shouldn't burn views. The cap exists to stop someone browsing the whole room, and counting distinct cards does that.

## D14 · A2 · You can only act on a card the deck has shown you

**Choice.** Tapping, blocking or reporting from a card, and fetching its image, all need the deck to have shown that card to that person (a `card_views` row) on top of the deck rules. Card IDs are random, but this means a card ID from anywhere else is useless.

## D15 · A2 · A check-in never outlasts its room

**Choice.** `expires_at` is the earlier of `CHECKIN_TTL` from now and the room's end. When a room ends, every card in it expires and is purged.

## D16 · A2 · Match lifecycle

**Choice.** `choosing` (CHOICE_WINDOW open) → `glowing` (both Find) or `chatting` → `met` (both tapped We met; the chat stays open). Unmatch, block and account deletion make it `ended`: every endpoint then answers 404 for it, and it leaves both lists. The two taps that made a match are marked used, so after an unmatch the pair can see each other again but needs two fresh taps to match again. No instant re-match from old taps.

## D17 · A2 · Location freshness without coordinates

**Question.** "Both passed a location check in the last 2 minutes" needs the passes stored somewhere, and P2 allows only pass or fail.

**Choice.** `location_checks` keeps user, room, purpose (join or find), result (pass, fail, demo_skip), a rough accuracy bucket and the time. Never coordinates. It's purged after `LOCATION_CHECK_RETENTION` (24 h), and it doubles as the log of demo-mode skips. If both chose Find but the first person's check has gone stale while they waited, `set_choice` answers `waiting` with `other_location_stale`, and the server sends them `match.choice` so their app re-sends Find with a fresh fix. Going straight to chat would make Find fail for almost anyone who chose first.

## D18 · A2 · A `match.ended` event

**Question.** Nothing told the other person's app when a match ended (unmatch or block), so an open chat would sit there until it failed.

**Choice.** `match.ended` (`{ type, matchId }`, no push) goes to both people. It doesn't say why, so a block looks the same as an unmatch.

## D19 · A2 · Three endpoints the spec didn't list

**Choice.** `GET /api/rooms/{id}` (B2) returns the room, my open check-in and what I have left today, so the app can restore the room home after a relaunch. `GET /api/me/photos/{id}` (B1) serves my own profile photos through the API, because P4 rules out public or signed storage links. `/api/admin/*` (B7) is fully specified. A1 should add these to `docs/SPEC.md`.

## D20 · A2 · No user IDs in any app response, even after a match

**Choice.** The only user ID the API ever returns is your own (`Me.id`). Cards are named by card ID, matched people by match ID, and messages say `fromMe` instead of naming a sender. `codegen.sh` refuses the contract if an app-facing response has a field like `userId`, `senderId`, `email`, `latitude` or `accuracy`, or an object that isn't closed, or `firstName` outside `MyProfile` and the match schemas. Database results meant for the server's `notify()` carry `userIds`; the route helper drops them because the contract doesn't have them.

**Why.** P1 needs this only before a match, but a match ID already does everything an app needs, and it keeps user IDs out of screenshots and logs entirely.

## D21 · A2 · Photo uploads are base64 inside JSON

**Choice.** `POST /api/me/photos` and `POST /api/rooms/{id}/checkin` take JSON with a base64 JPEG field, with a 4.2 MB body limit (`x-max-body-bytes`), under Vercel's 4.5 MB request limit. A1's placeholder had multipart.

**Why.** One body format, and zod validates the ticket, tags and photo size together. Photos are typically 300 to 600 KB, so the 33% base64 overhead doesn't matter.

## D22 · A2 · Test sign-in can only reach test accounts

**Choice.** `POST /api/dev/test-login` accepts only `@glow.test` emails, and the `dev` tag is left out of the generated Swift client, so no `testLogin` method ships in a Release binary. B1 writes the Debug-only call by hand.

## D23 · A2 · Reports keep the reported person's last messages

**Question.** A report also blocks, and a block ends the match and deletes the thread, which would destroy the evidence a moderator needs.

**Choice.** A match or chat report copies the reported person's last `REPORT_EVIDENCE_MESSAGES` (20) messages, only theirs, into `reports.evidence` before the block runs. Reports are deleted with either account. This keeps a little text past the chat's life, for safety review only.

## D24 · A2 · 18 and over, enforced by the database

**Choice.** A trigger on `profiles` refuses any birthdate that makes someone under `MIN_AGE`, so a minor's birthdate is never stored at all, whatever the route does. "Today" is taken in UTC-12, the last timezone on Earth, so nobody counts as 18 before it's their birthday everywhere (P10).

## D25 · A2 · Card tags and filters

**Choice.** Top color: black, white, gray, red, pink, orange, yellow, green, blue or purple (10). Hair length: short, medium or long. Hair color: black, brown, blonde, red, gray or dyed. Extras: glasses, hat, beard, headphones, backpack. Top color is required. Hair is optional (hats and hijabs), and a card without a hair tag doesn't match a hair filter. Filters match any of the listed values per attribute, and every listed extra. An empty list means any.

## D26 · A2 · How a glow is picked

**Choice.** `start_glow` takes the code word list from the server (C3's `words.ts`; lowercase letters, 2 to 16). It picks the color fewest active glows in the room use, so the first 8 glows in a room all have different colors. Then it picks a word, preferring words no active glow in the room uses, and never a color plus word already active (a unique partial index backs this up). Then the least used meeting spot. With 300 words, a room runs out only past 2,400 simultaneous glows.

## D27 · A2 · Realtime is receive-only, and presence is never allowed

**Choice.** The only Realtime policy lets a signed-in person receive `broadcast` messages on `user:{their id}` and on `room:{id}` while they have an open check-in there. There's no INSERT policy, so apps can't send anything, and presence (which would list everyone in a room) is refused even on your own channel. Topics use lowercase UUIDs; `GlowEvents.userTopic` and `userTopic` handle that. On the Supabase cloud project, also turn off Realtime's "Allow public access" (Needs David).

## D28 · A2 · Later migrations are closed by default

**Choice.** Besides revoking everything in `0001`, the migration changes default privileges: tables and sequences that later migrations create in `public` get no `anon` or `authenticated` grants, and new functions aren't executable by `PUBLIC` (that default is global, so it's revoked globally for the migration role). A pgTAP test checks that every table has RLS on with no policies, so a later migration that forgets fails CI.

## D29 · A2 · Database functions speak the API's shapes

**Choice.** Function JSON uses the API's camelCase names, leaves out null fields, and formats times as `2026-10-24T20:15:00.000Z`, so a route can pass the result straight to its reply. Expected failures are `P0001` errors whose message is a code (`not_found`, `tap_limit_reached` and so on; see `docs/CONTRACTS.md`).

## D30 · A2 · Anonymous activity counters for metrics

**Choice.** `room_activity` gets one row per check-in, card view batch, tap, match, glow started and glow met, with only a room ID, a kind, a count and a time. B7's metrics page reads it, because purge deletes the underlying rows within minutes. It's append-only, so it adds no lock contention to taps.

## D31 · A2 · Banned people

**Choice.** `profiles.banned_at` (B7's ban action) hides someone from every deck at once and stops new check-ins.

## D32 · A2 · One generated Swift Types.swift

**Choice.** swift-openapi-generator 1.14 splits the types into eight `Types+*.swift` files that all carry the same `public import`s, and Swift 6 warns about every one a file doesn't use publicly (40 warnings). `codegen.sh` merges them back into one `Types.swift`, so the client builds with no warnings under strict concurrency.

## D33 · A3 · The web domain is one placeholder variable

**Question.** {DOMAIN} isn't chosen yet, but the app needs it for Associated Domains, the links it accepts and the Release API URL.

**Choice.** `GLOW_WEB_DOMAIN` in `ios/Glow/Config/Shared.xcconfig` is the only place it's set, as `glow-domain-not-chosen.invalid` (the `.invalid` TLD can never resolve). The entitlement (`applinks:$(GLOW_WEB_DOMAIN)`), Info.plist (`GlowWebDomain`) and Release `API_BASE_URL` all read it. B9 changes that one line.

**Why.** One edit, and nothing can ever talk to a domain we don't control by accident.

## D34 · A3 · The glow:// scheme and local networking exist in Debug builds only

**Question.** The spec wants `glow://` in Debug only, and A1 asked for a Debug-only ATS exception for the local API and Supabase.

**Choice.** `ios/Glow/Info.plist` has neither. A build phase in `project.yml` adds `CFBundleURLTypes` (`glow`) and `NSAllowsLocalNetworking` to the built Info.plist in Debug, then checks they're there and fails the build if not. AppCore's `DeepLink` also refuses `glow://` unless `AppConfig.allowsCustomScheme`, which is only true in Debug.

**Why.** Adding in Debug (rather than removing in Release) means a broken script can only make Debug stricter, never Release looser. `NSAllowsLocalNetworking` only opens localhost and local IPs, not arbitrary http.

## D35 · A3 · App analytics are anonymous and take only literals, numbers and flags

**Question.** How do we make "never names, photos, coordinates or message text" hard to break in the app?

**Choice.** AppCore's `AnalyticsEvent` takes a `StaticString` name, `StaticString` keys, and `AnalyticsValue`s that can only be a Bool, an Int or a string literal, so a runtime string (a name, a message) can't be passed. The live adapter also drops keys whose words look sensitive (`lat`, `name`, `user_id`, …). PostHog never calls `identify`, has person profiles, GeoIP, session replay, autocapture and screen views off. Sentry has screenshots, view hierarchy, session replay, tracing, breadcrumbs and default PII off, and `PrivacyScrubber` cleans every event. David: also turn on "Discard client IP data" in the PostHog project settings when it exists.

**Why.** Types catch mistakes at compile time, and the scrubbers are a second line.

## D36 · A3 · The Sentry SDK is deferred; the adapter is ready

**Question.** sentry-cocoa 9.31 declares seven binary frameworks, and SwiftPM downloads all of them: 3.2 GB per checkout. This Mac had under 3 GB free, and Wave 1 has nine iOS worktrees.

**Choice.** The package is commented out in `ios/project.yml`. `Glow/Analytics/LiveAnalytics.swift` keeps the full, privacy-locked Sentry adapter under `#if canImport(Sentry)`; it was type-checked against sentry-cocoa 9.31 under Swift 6 with warnings as errors. Re-adding the package entry and dependency switches it on. PostHog is live. Waiting on David (see Needs David).

**Why.** Disk and CI time, with no privacy cost: until Sentry is linked, error reports go nowhere.

## D37 · A3 · The app links only Supabase Auth and Realtime

**Question.** Which supabase-swift products should the app get?

**Choice.** Session gets `Auth`, GlowRealtime gets `Realtime`. PostgREST, Storage and Functions aren't linked.

**Why.** The spec routes everything except sign-in and the person's own channels through the API. Not linking the table and storage clients means no feature can even try to read data directly.

## D38 · A3 · API retries never resend a request that might have landed

**Question.** "Retries when the network drops" could send a chat message or a tap twice.

**Choice.** `RetryMiddleware` retries every method when the request never left the phone (offline, host not found, can't connect). When it's unclear whether the server got it (connection lost, timeout, or a 503), it retries only GET, HEAD, PUT, DELETE and OPTIONS, or requests with an `Idempotency-Key` header. Streamed bodies are never retried. 401, 404 and 429 are thrown as `APIError.unauthorized`, `.notFound` (P11) and `.rateLimited`, and `ClientError` (which prints full requests, headers included) is never surfaced.

**Why.** A duplicate message or tap is worse than one honest "you're offline".

## D39 · A3 · Links before onboarding wait in memory; signing out forgets everything

**Question.** What happens to a room QR scanned before sign-in, given rooms can't open until onboarding is done?

**Choice.** The Router holds it as `pendingRoute`, in memory only, and opens it when the session becomes ready. Signing out (or going back to onboarding) clears every stack, sheet, takeover and pending route.

**Why.** A scanned code still works after sign-up, and nothing about the previous person's matches survives a sign-out.

## D40 · A3 · Service protocols live in AppCore, one file each

**Question.** Where do the service protocols go, if features may only depend on AppCore, DesignSystem and service modules?

**Choice.** Each protocol is its own file in `AppCore/Services/` with a matching mock in `AppCore/Mocks/`. A3 wrote the first shapes. Proposal for A1: from Wave 1, each service's owner owns those two files (B1 Session, B2 Location, B3 Imaging, B5 Push and Realtime). Each service module exposes a `live` factory the app calls, so owners swap in real code without touching the app target.

**Why.** The container needs the protocols without importing every service, and owners shouldn't wait on A3 to reshape their own API.

## D41 · A3 · Module names GlowRealtime and LiveActivityShared

**Question.** supabase-swift already has a target named `Realtime`, and SwiftPM needs unique target names. The Live Activity attributes must be shared by FeatureGlow and the widget extension.

**Choice.** The spec's Realtime module is `GlowRealtime` (still B5's). A small `LiveActivityShared` module (C3's) holds `GlowActivityAttributes`, so the extension doesn't link AppCore and the API stack.

**Why.** Both are forced by the build graph. The ownership map in `AGENTS.md` names both.

## D42 · A3 · API traffic never touches the disk cache

**Choice.** `GlowAPI.live` uses an ephemeral `URLSession` with no URL cache, no cookies and `reloadIgnoringLocalAndRemoteCacheData`.

**Why.** Signed card links and profile photos must never be readable from the phone's cache (spec: "Display with caching turned off").

## D43 · A3 · The privacy manifest declares more, not less

**Choice.** `ios/Glow/PrivacyInfo.xcprivacy` declares precise location (even though only pass or fail is kept), "who you want to see" as sensitive info, and everything else the app sends, all for app functionality, none for tracking. Analytics and crash data are declared as not linked to the person.

**Why.** Over-declaring costs nothing; under-declaring misleads people. B9 keeps App Store Connect's answers matching it.

## D44 · A3 · Fixture outfit photos are synthetic

**Choice.** `ios/fixtures/photos/` holds four generated images of a faceless figure in different tops, each labelled "synthetic". No real person.

**Why.** No one consented to be a fixture. B3 needs photos with real faces to test the blur: add ones the people in them agreed to, or freely licensed ones.

## D45 · A3 · `sim.sh scan` hands the link to the app at launch

**Question.** On iOS 26, `simctl openurl` stops at an "Open in Glow?" prompt for `glow://` links, so a headless `scan` would hang.

**Choice.** `scripts/sim.sh scan` relaunches the Debug app with `-GlowDebugOpenURL <link>`, which goes through the same `Router.open` as any link (and waits for onboarding like one). It's compiled out of Release. `scripts/sim.sh open <url>` still takes the system path, prompt and all.

**Why.** A real QR scan hands a universal link straight to the app, with no prompt, so this is closer to the real thing than the prompt is.

## D90 · A1 · Parallel agents share one Mac without sharing state

**Question.** Nine Wave 1 agents build and test on the same Mac at once. Simulators are global to the Mac, port 3000 can only be taken once, and `supabase db reset` on the one local stack would wipe everyone's data.

**Choice.** `scripts/agent-env.sh <ID>` gives each agent its own Simulator names (`Glow A (B1)`), server port (3090 plus a fixed index: B1 3101 to B9 3109, C1 3111 to C4 3114, D1 3121 to D5 3125) and API URL, which `sim.sh` bakes into the Debug app. Everyone shares the `glow` Supabase stack for reads and writes through the API; anyone who needs to change the schema or reset takes their own stack with `--own-db` (a copy of their worktree's `supabase/`, project `glow-<id>`, ports 55000 plus 10 times the index). `pnpm db:reset` and `pnpm db:stop` refuse on the shared stack when `GLOW_AGENT_ID` is set, and `sim.sh teardown` won't delete the shared default Simulators without `--yes`.

## D91 · A1 · macOS CI runs where it pays

**Question.** macOS minutes cost ten times Linux minutes on a private repo, and nine agents pushing drafts would run the iOS job hundreds of times.

**Choice.** The macOS job runs on every push to main, and on a PR only once it's ready for review and changes `ios/`, `contracts/`, `scripts/sim.sh`, `scripts/codegen.sh`, the Swift lint configs or the CI workflow itself. While a PR is a draft, its owner proves iOS work locally with `scripts/sim.sh build`, `test` and `lint`. Main stays fully covered, so anything that slips through is caught on merge and reverted (Build plan: "reverted first and fixed second"). The codegen tool and Swift packages are cached.

## D92 · A1 · Error codes come only from the contract

**Choice.** `HttpError` takes only codes from the contract's `ErrorCode` enum (a type error otherwise), with `conflict(code, message)` for 409 and `unprocessable(code, message, { reason })` for 422. The app can rely on every code it might see being in `openapi.yaml`.
