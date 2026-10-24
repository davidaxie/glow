# Decisions

When the spec is unclear, agents pick the option that protects privacy more and record it here. One entry per decision, newest at the bottom.

Format, up to D56: `## D{n} · {agent} · {short title}`. From Wave 1, decision IDs carry the agent, so parallel PRs never collide: each agent has one `## {agent} · {name}` section, with `### {agent}-D{n} · {short title}` entries numbered inside it (`### B2-D1`, `### B2-D2`, ...). Each entry gives the question, the choice, and why.

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

## D46 · A2 · service_role can use what later migrations create

**Question.** With `auto_expose_new_tables = false`, tables, sequences and functions from later migrations got no grants at all. Wave 1 routes would hit "permission denied" while pgTAP, running as `postgres`, still passed.

**Choice.** `0002` sets default privileges for the migration role: all on tables and sequences, and execute on functions, in `public` for `service_role`; select on tables and execute on functions in `private`. `anon` and `authenticated` still get nothing. `090_checkpoint1.test.sql` creates a table, sequence and functions and checks both sides. The rule is in `docs/CONTRACTS.md` ("Grants for new tables and functions").

## D47 · A2 · A push when your Find needs a fresh location check

**Question.** If A chose Find and pocketed the phone, and B chose Find more than `GEO_FRESHNESS_FOR_GLOW` later, A's suspended app never heard the silent `match.choice`, and the match timed out into chat.

**Choice.** A new event `match.recheck`, `{ type, matchId }`, goes to whoever's check is stale (`set_choice`'s `recheckUserIds`, `start_glow`'s `staleUserIds`). Its push says "Open Glow to find each other." (fixed text, no name, P6), with category `MATCH`, so a tap opens the match. It's time-sensitive, because the choice window is short. The app then sends Find again with a fresh fix.

## D48 · A2 · start_glow answers instead of raising

**Choice.** `start_glow` returns `{ result: started | chat | waiting, reason, ... }`, and changes `matches.status` itself:
- **Chat.** Both chose Find but someone left the room, or no code word is free: the match moves to `chatting` and the result is `chat`.
- **Waiting.** A location check went stale between `set_choice` and `start_glow` (a millisecond race at the 2-minute edge): nothing changes, and the stale people get `match.recheck`. This doesn't open the chat, because the check can still be redone in time.
- **Not both Find.** The call was early (a server bug): nothing changes.

It only raises `not_found` or `invalid_input`.

## D49 · A2 · A card needs a passed join check

**Choice.** `create_checkin` requires a `location_checks` row with purpose `join` and result `pass` or `demo_skip`, for that person and room, newer than `JOIN_TICKET_TTL`. The join route already writes one (D17). A QR code, poster or room code alone can never create a card, even if a route forgets to check the ticket. An admin's demo-mode skip counts, as the spec intends for stage phones.

## D50 · A2 · Finishing onboarding, and reviewing held photos

**Choice.** `POST /api/me/onboarding/complete` (B1) calls `complete_onboarding`. It finishes once the profile is filled in and at least `PROFILE_PHOTOS_MIN` photos are **approved**. Push is optional, so declining notifications never blocks anyone. Photos held for review (possibly under 18) don't count, so a possible minor stays in onboarding until a person looks (P10).

Admins (B7) review held photos with `GET /api/admin/photos`, `GET /api/admin/photos/{id}/image` and `POST /api/admin/photos/{id}/review` (approve, reject, or ban), each 404 for non-admins. Admins see the owner's viewer code, never a user ID.

## D51 · A2 · Lazy timeouts are reported, and the caller notifies

**Choice.** `get_match`, `list_matches`, `set_choice`, `start_glow` and `glow_met` return `settled: [{ matchId, kind: choice_timeout | glow_expired, userIds }]` for every timeout they apply. Purge skips anything already settled, so the route that called the function sends `match.choice` (choice_timeout) or `glow.ended` (glow_expired) to both people. `start_glow` can also expire other pairs' glows in the same room, and reports those too. The routes are listed in `docs/CONTRACTS.md` ("Settled timeouts").

## D52 · A2 · No tap counts in metrics at all

**Question.** `RoomMetrics.taps` with any `since` let an admin standing in the room time someone's one-sided tap. Options: drop it, or bucket `since` to 15 minutes and hide counts under 5.

**Choice.** Drop it, the more private option. `RoomMetrics` has no `taps`, `record_tap` writes no activity row, and a check constraint (`room_activity_no_taps`) stops anyone writing one. `0002` deleted the existing tap rows. Matches, which are mutual, still count.

## D53 · A2 · A re-tap after an unmatch is a new tap

**Question.** The review found the re-tap reply's `tapsLeftToday` off by one, because it reused today's tap row, and a re-tap at the cap refused.

**Choice.** Today's taps are now counted in `room_days.taps_used`, apart from the per-pair tap row, so every reply and `get_room_state` is exact. I kept "a re-tap after an unmatch uses a tap", so at the cap it's refused. This differs from reading the review as "re-tapping should be free": the old tap was used up by the match, and tapping again is a new choice to signal someone. Without the separate count, the old code effectively let someone tap one extra time a day. Tapping someone you already tapped (no match in between) is still free.

## D54 · A2 · The deck says "check-in ended" after purge, the same day

**Choice.** `room_days` also records that a person checked in to a room on a given room day (written by `create_checkin` and `get_deck`). `get_deck` answers 404 only when the room doesn't exist, or the viewer has no check-in there and none today. So after purge deletes an expired check-in, the app still gets `emptyReason: checkin_ended` and can offer to check in again. `room_days` is purged after `CARD_VIEW_RETENTION`.

## D55 · A2 · Limits in openapi.yaml are tied to constants.json

**Choice.** Every limit in `openapi.yaml` that repeats a constant carries `x-constant`, for example `x-constant: { maxLength: MESSAGE_MAX_CHARS }`, `"PROFILE_PHOTOS_MAX - 1"` or `"base64(PHOTO_MAX_BYTES)"`. `codegen.sh` fails if the number disagrees with `constants.json`. Changing a constant now means changing the schema too, and CI says so.

## D56 · A2 · Known gap: deleting an account clears a ban

**Choice, for D2.** `banned_at` lives on the profile, so a banned person who deletes their account (P9 and B8 delete every row) can sign up again with a new account and isn't banned. Not fixed in Wave 0. Options for later: a ban list keyed by a salted hash of the Apple ID `sub` or the email, kept after deletion. That keeps data about a deleted person, so it needs its own privacy decision.

## B6 · Design system

### B6-D1 · Dark ink on every glow color

**Question.** The spec puts a white code word on Ember, Rose, Violet and Sky. White on those is 2.8:1 (Ember), 3.3:1 (Rose, Sky) and 4.2:1 (Violet), under WCAG AA for normal text, and Ember is under 3:1 even for large text. B6's brief requires all text to meet AA, and the glow screen also shows smaller text (meeting spot, countdown) that scales with Dynamic Type.

**Choice.** `GlowHue.ink` is the app background color, #0B0B10, on all eight colors: 4.7:1 on Violet (the lowest) and up to 17:1 on Pearl. It's one property, so switching back to the spec's rule is a one-line change if A1 prefers it.

**Why.** It's the only rule that passes AA on every color at every text size, and the code word has to be read across a dark room.

### B6-D2 · Filled buttons and selected chips use dark ink

**Question.** White text on the accent #FF4FA3 is 2.8:1, and on danger #FF5A5F 2.9:1.

**Choice.** Primary and danger buttons and selected chips draw their label in #0B0B10 (`GlowPalette.onAccent`), 6.4:1. Pressing a filled control mixes in 12% white instead of darkening it, so pressed labels gain contrast. `GlowPalette.textPairings` lists every text and background combination the components draw, and a test checks each one against 4.5:1.

**Why.** WCAG AA, with nothing resting on the large-text exception.

### B6-D3 · The glow pulse brightens and never darkens

**Question.** The spec's flash safety says the glow pulses slower than once a second and never dims below 70% brightness. A pulse that darkens the color would also lower the code word's contrast at its dimmest moment.

**Choice.** The glow color stays at full strength. A soft white bloom (at most 15% white at its center) fades in and out on top every 1.25 s (0.8 times a second). The dimmest moment is 76% of the brightest in luminance on the darkest color (Violet), and tests check all eight against 70%. Under Reduce Motion the bloom doesn't scale: it only fades, on a slower 4 s cycle.

**Why.** Contrast only goes up during a pulse, and the flash limits hold with margin.

### B6-D4 · A recorded screen hides the card instead of blurring it

**Question.** The brief asks for a card tile that blurs while the screen is captured (P12). A blur still draws the photo's colors and shapes into the recording.

**Choice.** `glowHiddenWhenCaptured()` doesn't draw the content at all while `isSceneCaptured` is true (opacity 0, hidden from VoiceOver). In its place it shows a soft cover that looks blurred, with "Hidden while your screen is shared". The layout keeps its size. Tests and Debug builds can fake a capture with `.environment(\.isSceneCaptured, true)`. Logging screenshots stays C1's job.

**Why.** Nothing from the photo can be recovered from a recording. It looks just as calm as a blur.

### B6-D5 · The launch screen stays a plain background color

**Question.** The launch screen could show the glow mark, but that needs a `UILaunchScreen` image key in A1's `Info.plist`.

**Choice.** Keep `UILaunchScreen` as the `LaunchBackground` color, #0B0B10 (the `background` token), with no image. B6 owns the color, and the app icon carries the mark.

**Why.** Apple's guidance is a launch screen that looks like the first screen, with no branding. A plain dark screen opens straight into the dark app with no flash, and needs no change outside B6's paths.

### B6-D6 · Screen helpers count holders and work only in the app

**Question.** Two glow views can be on screen at once during a transition. If each one saved the brightness when it appeared, the second would save the first's raised level as the person's own, and leave their screen at full brightness after the glow.

**Choice.** `GlowBrightness` and `GlowKeepAwake` count holders. The first saves the person's level, and the last one restores it. Leaving the foreground, opening Control Center or the view disappearing all count as letting go. Coming back raises the level again from wherever the person set it in the meantime. The screen comes from the view's own window scene, never `UIScreen.main` (deprecated in iOS 26). The idle timer needs `UIApplication`, so `glowKeepAwake` and `GlowSurface` are marked unavailable in app extensions.

**Why.** "Always restores brightness" holds in every order of events, and tests cover each order.

### B6-D7 · The glow's haptic is three soft beats, not a 15-minute buzz

**Question.** The brief asks for a haptic for the glow pulse. A haptic on every pulse for the whole 15 minutes would drain the battery and wear on the person.

**Choice.** `GlowHapticPattern.glowPulse` is three soft double beats, timed to the visual pulse (1.25 s apart). C3 plays it when the glow starts, and can play it again on demand. `heartbeat(beats:)` makes longer or shorter versions.

**Why.** The person feels the glow start, and can still put the phone in a pocket.

## B8 · Safety, moderation and cleanup

### B8-D1 · Moderation runs on Claude, with a fake only in local development

**Question.** Moderation uses `claude-haiku-5-5`, but there's no `ANTHROPIC_API_KEY` yet, and check-ins must still work in the Simulator.

**Choice.** `server/src/server/moderation` hides the model behind an interface. With `ANTHROPIC_API_KEY` set (anywhere, including a laptop), it's Claude: `claude-haiku-5-5`, thinking off, effort `low`, structured outputs that return booleans only, and the photo decoded, stripped of metadata and downscaled to at most 768 px before it's sent. Without the key, and only when the env profile is `local` (laptop, CI, Vitest), it's a deterministic fake that approves everything except fixtures carrying a marker (`moderationFixtureJpeg(['face_visible'])`, `[glow-test:flag]`). On Vercel the key is required by `server/src/env.ts` (D1), so the fake can't run there; a test fails if that rule is ever relaxed, and the module also refuses to fall back outside `local`. The model never describes the person and nothing is logged but the decision, reason, model and time.

**Why.** The 2.5 s budget (MODERATION_TIMEOUT) needs the fastest settings, and a small image is plenty to see a face, nudity or an outfit. Booleans leave the model nothing to say about anyone. The fake keeps every agent unblocked without weakening what runs on the internet.

### B8-D2 · What moderation refuses, holds and lets through

**Choice.** Card photos: rejected for nudity, a recognizable face, someone who may be under 18, no person, or no visible outfit (that order picks the `reason`). Profile photos: rejected for nudity or nobody in the photo, and *held* for human review when the person may be under 18 (B7's queue). A photo that isn't a readable JPEG is rejected `unreadable` without calling the model, and a model refusal counts as a rejection. Any timeout or outage throws a 503 `unavailable` (reason `moderation`) for both kinds, so nothing unmoderated is stored. Chat: a flagged message is refused (422 `message_rejected`, not stored); if moderation doesn't answer in 2.5 s the message goes through as `pending`, and B8's purge cron reviews pending messages afterwards.

**Why.** Failing closed for photos is the spec's rule for cards, and for profile photos a retry costs the person a tap while storing an unchecked photo costs privacy. "Possibly under 18" is rejected on a card because cards are live in a room right now; on a profile it's held, since a person can still finish other steps while an admin looks. Refusing a flagged message, rather than storing and hiding it, means harmful text never reaches the database or the other person.

### B8-D3 · Rate limit keys are hashed, and limits fail open

**Choice.** `rateLimit(key, policy)` has one sliding window per policy (`signIn`, `join`, `checkin`, `deck`, `taps`, `messages`, `reports`, `blocks`, `capture`, `photos`, `account`, `admin`, `api`). Signed-in requests are keyed by the person's ID, others by client IP. The store only ever sees HMAC-SHA256(policy and key) under a key derived with HKDF from the service role key. Upstash when it's configured (required on Vercel), an in-memory window locally. If Upstash doesn't answer within 1 second, the request is allowed and the outage logged. The purge cron has no limit.

**Why.** Upstash is a third party, so it shouldn't learn user IDs or IP addresses. The service role key never leaves the server, so a dictionary of IPs doesn't help anyone who reads Redis. Failing open means a Redis blip slows nobody down; the caps that matter for privacy (taps, views) are enforced in the database regardless.

### B8-D4 · Deleting an account also deletes what Supabase Auth keeps about the person

**Question.** "Every row, storage object and device token, then the auth user." Deleting the auth user cascades through every table, but Supabase Auth's own audit log (`auth.audit_log_entries`) keeps the person's user ID, email and IP for every sign-up and sign-in, and the deletion writes one more entry naming them. Some rows also point at a person without a foreign key (other people's `card_views` of their cards).

**Choice.** `DELETE /api/me` reads what has to go, deletes their card and profile photos from storage, deletes `card_views` of their cards, deletes the profile (which cascades to every other table), deletes the auth user, then calls `forget_account_traces()` (migration `0003_b8_forget_account.sql`) to delete the audit entries and any stored Realtime message on their topic. A storage failure doesn't stop the deletion (no row is left that could serve those files, and the purge sweep removes them), and neither does a failure of the last step (the account is already gone; the audit retention below catches it). The other person in each match gets `match.ended`. The deleted person's token stops working at once (D3). The test checks every uuid column of every public table, both buckets, the auth user and the audit log.

**Why.** Deletion should mean nobody can find the person afterwards, including in our own logs.

### B8-D5 · Purge sweeps orphaned photos and keeps Auth's audit log for 7 days

**Question.** `purge_expired()` deletes the check-in rows and returns their photo paths, so if deleting a photo from storage fails once, nothing would ever try again. And P9 says "within 10 minutes of expiring".

**Choice.** After deleting the returned paths, every run also sweeps both buckets: any card photo with no `checkins` row, and any profile photo with no `profile_photos` row (or no profile at all), older than 2 minutes, is deleted. The 2-minute grace covers B3 and B1 uploading a photo just before writing its row. With the cron every 5 minutes, a card's photo is gone within 5 minutes of expiring, or 10 if storage fails once. Each run also sends `deck.changed` to every room that lost a card, so expired cards leave screens too, and deletes Supabase Auth audit entries older than 7 days (`purge_auth_audit`), which hold emails and IP addresses.

**Why.** P9 must hold even when a storage call fails, and the sign-in history of people who keep their accounts shouldn't pile up forever either.

### B8-D6 · A block looks exactly like an unmatch

**Choice.** A block or report sends `match.ended` to both people in any match it ended and `deck.changed` to the rooms either person is checked into, never `glow.ended` or anything that says why (D18). C4's unmatch should send the same `match.ended`, so the other person can't tell which happened. The response to the person blocking is a bare 204, and a card, match or chat ID the caller can't act on is 404 (P11).

### B8-D7 · Capture logs keep the room only if the person is in it

**Question.** `POST /api/abuse/capture` takes a room ID and has no 404 in the contract.

**Choice.** The `abuse_signals` row keeps the room only if the person has a check-in there; otherwise the room is left empty. The answer is always 204, so the endpoint never says whether a room exists. Three captures in 24 hours log `safety.capture_review` with the person's ID; B7's admin can list those accounts from `abuse_signals`.

### B8-D8 · The purge runs every 5 minutes from Vercel, or from any scheduler

**Question.** Vercel's Hobby plan only runs crons daily, and P9 needs every 5 minutes.

**Choice.** `server/vercel.json` schedules `/api/cron/purge` at `*/5 * * * *`, which is what P9 needs on a Pro plan. On Hobby, use an outside scheduler that calls `GET /api/cron/purge` every 5 minutes with `Authorization: Bearer $CRON_SECRET` (Upstash QStash schedules can forward that header; Upstash is already in the stack) and change the schedule to daily so the deploy is accepted. The route is safe to call from both at once and as often as anyone likes: the database work is one transaction, each expiry warning is sent once, and deleting a photo that's already gone does nothing. It has no rate limit, and anything without the secret gets 401.

### B8-D9 · The safety screens never hold a user ID

**Choice.** FeatureSafety sends only a card ID or match ID (the server works out the person), and analytics get only literals (where it started, the reason, whether details were given). After a block or report from a match or chat, Close goes back to the matches list, since that match has ended. Pausing waits for the server's answer before the toggle changes, then refreshes the profile. Deleting needs a confirmation and signs out after.

## B9 · Release and TestFlight

### B9-D1 · Release builds sign manually, with the signing files in CI secrets

**Question.** How should TestFlight builds be signed: Xcode's automatic signing (cloud signing with an API key), fastlane match, or a certificate and profiles supplied to CI?

**Choice.** Release device builds of the app and the Live Activity sign manually with the Apple Distribution certificate and two App Store profiles named `Glow App Store` and `Glow Live Activity App Store` (B9's `cross-owner` PR #17 to `ios/project.yml`). CI gets the `.p12` and both profiles as base64 GitHub secrets, puts them in a throwaway keychain and deletes it afterwards. The App Store Connect API key is **App Manager**, not Admin. The team stays one value, `DEVELOPMENT_TEAM` in `Shared.xcconfig`. Debug keeps automatic signing; Simulator and CI test builds stay unsigned.

**Why.** An automatically signed archive uses the development profile, which can't carry the Release entitlement `aps-environment = production`, so it fails to sign (and push from TestFlight needs production). Cloud signing in CI needs an Admin-role key, a registered device, and makes a new development certificate on every run. match needs another repository or bucket, which is another account. Manual signing needs the least access: the key that can upload builds can't touch certificates, profiles or users.

### B9-D2 · Build numbers come from TestFlight, and a release commits nothing

**Question.** "Bump the build number" usually means editing the project and committing. Who commits, and where?

**Choice.** `beta` asks TestFlight for the newest build number and uses that plus 1 (`GLOW_BUILD_NUMBER` overrides it). The number, and the hosted Supabase URL and anon key, PostHog key and Sentry DSN, go into the build through an xcconfig handed to `xcodebuild -xcconfig`, written to a temporary folder with owner-only permissions. Nothing is committed to `main`, and the workflow only has `contents: read`. A release is a `beta-*` tag (`ios/fastlane/ship release`) or A1's `wave-*-done` tag. In CI the lane stops waiting once the build appears on App Store Connect and its What to Test is set, instead of paying for macOS minutes while Apple processes it (the repo is private, where macOS minutes cost ten times as much); the unsigned Release build check runs on demand (`ios/fastlane/ship verify_release`) rather than on every PR, for the same reason. fastlane's usage reporting is off.

**Why.** CI that can push to `main` is a bigger target than CI that can't, and two releases racing to commit a build number would conflict. TestFlight is already the source of truth for which numbers are taken.

### B9-D3 · The release lane refuses a build that would loosen privacy

**Question.** Release builds differ from the Debug builds everyone tests: the hosted endpoints, no `glow://`, no local networking, production push. What stops a broken or leaky Release build from reaching testers?

**Choice.** Before building, `beta` refuses a Supabase key that isn't the anon key (a `sb_secret_` key, a JWT whose role is `service_role`, or the local demo key), a PostHog personal key, a local or non-https endpoint, and the placeholder domain. After exporting, it unzips the `.ipa` and refuses to upload if the Info.plist has the Debug-only scheme or any App Transport Security exception (D34), if `aps-environment` isn't production or Associated Domains isn't exactly `applinks:{DOMAIN}`, if `get-task-allow` is on, or if any file in the app contains a secret key, a private key, the test sign-in route (D6, D22) or a `GlowDebug…` launch argument. The checks are plain Ruby in `ios/fastlane/glow_release.rb` with unit tests, and `verify_release` runs them on an unsigned Release build without the Apple account.

**Why.** AGENTS.md says the app only ever holds the anon key and the API URL; this makes that a gate rather than a hope, at the last moment before a build reaches real phones.

### B9-D4 · Beta review gets notes, not a back door, and contact details stay out of git

**Question.** Apple's reviewers aren't at a venue, so they can't pass the location check. Should there be a review room that accepts any location, or a demo account that skips it? And where do the reviewer contact details live?

**Choice.** No bypass. The review notes (`ios/fastlane/testflight/review-notes.txt`) explain that rooms only open inside a venue, what a reviewer can do without one (sign in, onboarding, the scanner and code entry), and the privacy design; `GLOW_REVIEW_VIDEO_URL` can add a recording of the full loop. Sign in with Apple or the email code works for any reviewer, so no demo account is needed. The contact name, email and phone, and the feedback email, come only from GitHub secrets (`GLOW_REVIEW_*`, `GLOW_FEEDBACK_EMAIL`).

**Why.** Any way around the location check that works for a reviewer works for anyone who learns it, and the location check is what keeps strangers outside the room out of everyone's deck. David's phone number doesn't belong in a repository many agents read.

## B5 · Push, realtime and events

### B5-D1 · `notify` rebuilds every payload from the contract

**Question.** Callers build event objects from database results that also carry `userIds` and other fields. What stops one of them reaching a channel or a push?

**Choice.** `notify()` and `notifyRoom()` parse the event with the generated `zGlowEvent` and rebuild it from the declared keys only (`type` plus `matchId` or `roomId`, lowercased), so an extra field can't leave the server. The TypeScript types (`UserEvent`, `RoomEvent`) come from `eventCatalog`, so `deck.changed` can only go to a room and everything else only to a person. Both never throw: a failed broadcast or push is logged with the event type and counts (never user IDs or tokens), and the request that called it still succeeds.

**Why.** P1 and P6 shouldn't depend on every caller remembering to pick fields. A notification is a hint to refetch, so losing one is better than failing the tap or message that caused it.

### B5-D2 · Push fixtures for events without a push

**Question.** The brief wants `sim.sh push A <event>` to open the right screen for every event, but some events (`match.choice`, `match.ended`, `glow.ended`, `deck.changed`) have no push in the contract.

**Choice.** `ios/fixtures/push/` has a fixture for every event. The ones with a push are exactly the server's payload (`server/tests/notify/fixtures.test.ts` fails if they drift). The others are Simulator-only stand-ins, marked `"glowFixture": "simulator-only…"`, with the alert text "Simulator test: {event}". The server never pushes those events: `apnsRequestFor` returns null for them, and a test checks it.

**Why.** It lets us check every event's screen in the Simulator without inventing lock screen text the server would ever send.
## B2 · Rooms and joining

### B2-D1 · Join tickets are encrypted, not just signed

**Question.** The brief says a join ticket is "a JWT with person, room and time". A signed JWT (JWS) can be read by anyone who holds it: the person's user ID and the room ID sit in plain base64.

**Choice.** The ticket is an encrypted JWT (JWE, `dir` with `A256GCM`), keyed with HKDF-SHA256 of `JOIN_TICKET_SECRET`. Claims: `sub` (user ID), `room`, `chk` (the `location_checks` row), `res` (`pass` or `demo_skip`), `iat`, `exp` (`iat` + JOIN_TICKET_TTL), `iss` and `aud`. `verifyJoinTicket` in `server/src/server/rooms/ticket.ts` returns null for anything expired, edited, another person's or another room's, and never throws.

**Why.** The contract calls the ticket opaque, and D20 keeps user IDs out of everything the app holds. AES-GCM authenticates as well as hides, so it's still unforgeable.

### B2-D2 · How a rotating QR token is computed

**Question.** The spec says "the first 8 base32 characters of an HMAC-SHA256 of the current 30-second window, keyed with the room's secret", but not how the window is encoded or which base32.

**Choice.** window = floor(unix seconds / QR_ROTATION). The HMAC key is the 32 bytes of `rooms.qr_secret` (hex-decoded), the message is the window as an 8-byte unsigned big-endian integer (the TOTP counter of RFC 4226), and the token is the first QR_TOKEN_LENGTH characters of RFC 4648 base32 (A-Z, 2-7, no padding). The current and previous windows are accepted, every candidate is compared in constant time with no early exit, and poster tokens are compared even when `allow_static_qr` is off so both cases take the same time. B7's display page calls `displayToken(qrSecret, now)` from `@/server/qr`.

### B2-D3 · The link file with no Apple app ID

**Question.** `apple-app-site-association` needs `{TEAM_ID}.{BUNDLE_ID}`, and there's no Apple Developer account yet.

**Choice.** The app ID is `APPLE_APP_ID` (`{TEAM_ID}.{BUNDLE_ID}`, optional in `server/src/env.ts`, set by B9). While it's unset, the file is served with an empty `details` list: valid JSON that opens nothing, rather than a made-up ID. It's `application/json`, no redirect, and cacheable for an hour (it's the same for everyone). Links then open the `/r/{slug}` page, and the Debug app still takes `glow://`.

### B2-D4 · The web page for room links never looks the room up

**Question.** `/r/{slug}` is public. Should it show the room's name?

**Choice.** No. The page is identical for every slug and token: what Glow is, three steps, and the TestFlight link (or "ask the host for an invite" until `TESTFLIGHT_URL` exists). It never reads the database, so it can't confirm a room exists, and it never shows the token or the room's location. It has no scripts, a strict CSP, `no-referrer` (so the token never leaks to TestFlight in a Referer header) and `no-store`.

### B2-D5 · Join checks happen in an order that leaks nothing

**Choice.** `POST /api/rooms/{id}/join` checks sign-in, then onboarding (409), then the room and the code or token together (a wrong token for a real room is the same 404 as no room), then whether the room is open (409 `room_not_live`), and only then the location (422). A room code or QR token must open the room in the path, so a code for one room can't be used to join another. Too-rough fixes (`location_inaccurate`) and fixes outside (`not_in_room`) are both stored as `fail` with their accuracy bucket; nothing about the fix itself is stored or logged. A live room past its `ends_at` is reported as `ended` by resolve and room state, before any admin or purge job changes it.

## B4 · Deck and matching engine

### B4-D1 · A repeated filter value is a 400

**Question.** `DeckFilters` lists are `uniqueItems` in the contract, but the generated zod schemas don't check it.

**Choice.** `POST /api/rooms/{id}/deck` answers 400 `bad_request` when a filter list repeats a value, with the field path (`body.filters.topColor`, code `not_unique`) and never the value. An empty list means any, the same as leaving the field out.

**Why.** A request that doesn't match the contract is a 400 everywhere else. Quietly de-duplicating would hide client bugs.

### B4-D2 · Deck offsets past the daily cap are clamped

**Choice.** The deck route passes `min(offset, CARD_VIEWS_PER_ROOM_PER_DAY)` to `get_deck`. A day's deck never holds more cards than the view cap, so every larger offset is the same empty last page.

**Why.** The contract allows any integer, and an offset past Postgres's integer range would otherwise be a 500.

### B4-D3 · match.created goes out after the response, and never fails a tap

**Choice.** `record_tap` commits the match first. Then the tap route reads the pair from `matches` on the server and calls `notify([userA, userB], { type: 'match.created', matchId })` inside Next's `after()`, so a slow push never slows the reply. A failed notification is logged by event type only; the tap still answers `mutual`.

**Why.** The match exists either way, and the app finds it through `GET /api/matches`. User IDs only ever go to `notify()`, never to a reply (P1).

### B4-D4 · Two simultaneous taps: one says sent, the other says mutual

**Question.** When two people tap each other at the same moment, the pair lock in `record_tap` lets one tap land first. What does each person hear?

**Choice.** The first tap to land answers `sent`; the second finds it and answers `mutual` with the match ID. Both people get `match.created`. The app treats `match.created` (or a `mutual` reply) as the moment, and never assumes `sent` is final.

**Why.** It's the only answer that's true when it's given, and `sent` already promises nothing about the other person (P5). 50 pairs tapping at once make exactly 50 matches, each with one `sent` and one `mutual`.

### B4-D5 · The deck rules are written once, as views (migration 0004)

**Question.** With 300 people checked in, `get_deck` took about 25 ms of database time, mostly calling `private.active_checkin` and `private.pair_eligible` once per candidate. Rewriting the deck query set-based would copy the rules into a second place.

**Choice.** `0004_b4_deck_set_based.sql` writes the rules once, as `private.open_checkins`, `private.active_cards` and `private.eligible_pairs`, and replaces 0001's helpers (`open_checkin`, `active_checkin`, `pair_eligible`) with one-line reads of those views, same names and answers. `get_deck` joins the same views for the whole room. Postgres inlines views, so a single card is still a few index lookups and the whole deck is one set-based query (about 2 ms). The views are `security_invoker` and closed to clients. A rule change goes in the view, and both paths follow. B4's integration test checks that the deck and `card_visible_to` agree on every card.

**Why.** One definition of who sees whom, and the speed of a set-based query.

### B4-D6 · B4's integration tests run in CI

**Choice.** The deck, taps and matches integration tests call the real route handlers with real access tokens against a local Supabase. They run when `GLOW_INTEGRATION=1` or `CI` is set (GitHub Actions sets `CI`, after `supabase start` and `env:setup`), and refuse any non-local Supabase. Everything they make is named `b4it-…` and deleted afterwards, so pgTAP sees the database as it was. The 300-person load test is a separate script (`server/tests/deck/load.ts`) run by hand, not in CI.

**Why.** The Done-when boxes (every deck rule, 50 simultaneous pairs, P5) stay proven on every PR, without slowing local `pnpm test` for other agents.

### B4-D7 · Timing checks for P5 compare medians, interleaved

**Choice.** The P5 tests time the tapped person's deck against an untapped person's in the same room, and a `sent` tap to someone tapped many times against one to someone never tapped, interleaving the two so machine load hits both. They fail on a median gap over max(8 ms, 25%).

**Why.** A real leak (an extra query on one side) is a consistent gap; shared-machine noise isn't. The code paths are also identical by construction: `tappedByMe` reads only the viewer's own taps, and nothing is sent or counted for a `sent` tap.

## B7 · Admin and room ops

### B7-D1 · The admin web keeps its session in httpOnly cookies, and everyone else gets 404

**Question.** The brief says non-admins get 404 everywhere under `/admin`. The API's admin endpoints take a Bearer token, but a browser page that holds a token in JavaScript can leak it, and a page that only checks on the client still answers 200.

**Choice.** The admin signs in with a 6-digit email code (Supabase Auth, `shouldCreateUser: false`). The Supabase session is stored in httpOnly, SameSite=Lax cookies (Secure off localhost) that page JavaScript can't read. Every admin page, the display page and every server action checks the access token with Supabase Auth (D3) and the `admins` table (not banned) before anything else, and calls Next's `notFound()` otherwise, so the answer is the same HTTP 404 page as an address that doesn't exist. Pages check for themselves too, because layouts don't run again on client navigation. `/admin/sign-in` is the only page anyone can open, and it shows only an email and a code field. It answers the same whether an address has an account, and a right code for someone who isn't an admin reads as a wrong one; that session is revoked at once and no cookie is set. A sign-in lasts 24 hours; open pages refresh the access token every 10 minutes. The browser talks to the server through server actions (Next checks their Origin); `/api/admin/*` stays Bearer-only, for scripts and tests. A browser that has signed in as an admin before sees a "Sign in again" link on its 404 page (a cookie that holds nothing else).

**Why.** Nothing about the admin area, not even that a room exists, shows to anyone but an admin, and no admin token is ever readable by page scripts.

### B7-D2 · The display screen is for signed-in admins only, and shows no code for a room that isn't live

**Question.** Should the display page (`/display/{slug}`) be open to anyone with the link, so a venue laptop needn't sign in?

**Choice.** No. It answers 404 unless an admin is signed in on that screen, like everything else that hands out a working token. It shows no QR code at all while the room is paused, ended or not started yet.

**Why.** A rotating code is only better than a poster if you have to be in front of the screen to read it. An open display link would let anyone fetch live codes from anywhere.

### B7-D3 · Printed posters are off until an admin turns them on

**Question.** Should new rooms accept the static poster token by default?

**Choice.** No (`allow_static_qr` defaults to false, as in the database). The create form and room page explain the trade-off in one line, the poster can always be downloaded, and the room page says when posters are off. "Make a new poster code" replaces the token so old posters stop working.

**Why.** A photo of a poster works from anywhere, a rotating screen code doesn't. Either way the location check still applies.

### B7-D4 · Ending a room ends every check-in and deletes every card photo at once

**Choice.** Setting a room to `ended`, or moving its end into the past, ends every open check-in (`left_at`), hides the cards and deletes their photos straight away, instead of waiting for the purge cron. Moving the end earlier (still in the future) cuts every longer check-in to the new end (D15). Removing a card deletes its photo straight away too. Pausing keeps check-ins: the deck rules already hide every card in a room that isn't live.

**Why.** P9 is a ceiling, not a target.

### B7-D5 · A ban hides first, then signs out, then cleans up

**Choice.** Banning sets `profiles.banned_at` first (out of every deck at once, D31), then bans the Supabase Auth user so every token they hold stops working (D3), then ends their check-ins and deletes their card photos, ends their matches for both people (`unmatch`, so `match.ended` goes out; report evidence was already copied, D23), and marks every other open report about them as acted on. Each step is safe to run again. An admin can't ban themselves.

**Why.** If any later step fails, the person is already invisible. Ending their matches means nobody is left in a chat with a banned person.

### B7-D6 · Admins see photos only when they ask, watermarked with their own code

**Choice.** The cards page lists tags and watermark codes; each photo loads only when the admin taps "Show photo", watermarked with the admin's own viewer code, logged (`admin.card_viewed`, IDs only), and delivered as a data URL from a server action, so there is no image URL to cache, share or replay. Reports, cards and screenshot flags name people only by watermark code, never by user ID; banning a flagged person sends the watermark code, and the server looks the person up.

### B7-D7 · Live numbers have no tap count, and the rest are shown as they are

**Choice.** RoomMetrics has no taps (A2's D52, P5). Joins, card views, matches, glows started, We met and reports are shown live, refreshed every 10 seconds.

**Why.** Matches and glows are mutual by definition: both people already know. A tap count is the only number that could reveal a one-sided choice.

### B7-D8 · The map talks to OpenStreetMap with the origin only, and the admin's location is used once

**Choice.** The room map uses MapLibre GL 5 with OpenStreetMap's raster tiles and shows OpenStreetMap's attribution in full (not the collapsed "i"). Admin pages send `Referrer-Policy: strict-origin` (OpenStreetMap's tile policy asks for a referrer; this sends the site's origin, never a path with a room ID). "Set center to my location" asks the browser once, puts the pin there, and sends nothing until the admin saves the room, when it becomes the room's center: a public venue, which the spec allows storing. The server never logs it.

### B7-D9 · Local test sign-in for the admin web has the same locks as D6

**Choice.** `/admin/sign-in` offers "Sign in as admin@glow.test" only when the profile is local and `ALLOW_TEST_LOGIN` is on (which env.ts refuses on Vercel and with a cloud Supabase), and only for `@glow.test` addresses. It makes a one-time link on the server and uses it at once, so no email is sent. Every sign-in step, test or real, is rate limited per client address and per email address (B8's `signIn` policy), and every admin action per admin (`admin`).

### B7-D10 · The web domain is one server constant that must match the app's

**Choice.** `WEB_DOMAIN` in `server/src/server/admin/links.ts` builds every poster and display link, and a test fails if it differs from `GLOW_WEB_DOMAIN` in `ios/Glow/Config/Shared.xcconfig` (today both are `glow-domain-not-chosen.invalid`, D33). B7 asked A1 to move it into `server/src/env.ts` as a variable.

### B7-D11 · Admins can only see profile photos that need a decision

**Question.** `GET /api/admin/photos` takes any moderation status, so an admin could list and open every approved profile photo in the system.

**Choice.** Only `held` (the default) and `pending` photos can be listed (anything else is 400) or opened (404 once decided). Approve sets `approved`. Reject deletes the image and its row, and Ban does the same and then bans the owner (B7-D5); the reply says `rejected`. Every view is watermarked with the admin's code and logged.

**Why.** Held photos are often of someone who might be under 18. Admins need to see exactly what they're deciding on, and nothing else; a rejected image isn't kept anywhere.
## B3 · Check-in and private images

### B3-D1 · Card links are bound to one viewer and last 60 seconds, but aren't single-use

**Question.** The brief says "reused links" get 404. Does that mean a link works only once?

**Choice.** A link is an HMAC over `{cardId}.{viewerId}.{exp}`, with the viewer taken from the bearer token, so it's useless to anyone but the person it was made for (their reuse is a 404, which is what the contract means by "reused by someone else"). It also stops working after CARD_URL_TTL, and a link claiming a longer life is refused even if signed. Within those 60 seconds, its own viewer may fetch it again. Every fetch still checks `card_visible_to`.

**Why.** Single-use links would break whenever SwiftUI re-renders or a request is retried, without protecting anything: the only person who can use the link already sees the card. Binding to the token and re-checking visibility on every fetch is what keeps a leaked link worthless.

### B3-D2 · Match photos are watermarked too

**Question.** The spec only says card photos get the viewer's watermark.

**Choice.** `GET /api/matches/{id}/photos/{n}` adds the same faint viewer-code watermark as cards, and the same no-cache headers.

**Why.** A profile photo is a face, the most sensitive image the app serves. If one leaks, the code says who it was shown to.

### B3-D3 · The server re-encodes every card photo, though the phone already cleaned it

**Choice.** After moderation approves the upload, the server decodes it, applies any orientation, scales it to at most PHOTO_MAX_DIMENSION and re-encodes it with sharp, keeping no EXIF, GPS, XMP, ICC profile or comments. Only that copy is stored. Moderation runs on the bytes as uploaded (B8's fake reads its fixture marker from them).

**Why.** P3 is enforced on the phone, but a modified app could still send a photo with a location in it. Re-encoding makes "the stored photo has no metadata" true whatever the client does.

### B3-D4 · The phone removes every metadata segment, ICC profile included

**Choice.** The pipeline draws into 8-bit sRGB, exports with no properties, then `JPEGSanitizer` drops every APP1 to APP15 segment and every comment, keeping only JFIF and what's needed to decode.

**Why.** ImageIO writes no EXIF when given none, but "all metadata removed" shouldn't depend on a framework's defaults. A device's color profile can carry its model name, so it goes too; sRGB is what every viewer assumes without one.

### B3-D5 · Faces are checked again after blurring, and a survivor stops the upload

**Choice.** After blurring, Vision looks for faces again. Any it finds get a second pass; if a face survives that, the pipeline throws `processingFailed` and nothing is uploaded ("We couldn't blur that photo, so we didn't use it").

**Why.** A blur that left a detectable face would break P3 silently. Failing is better than a card with a face, and server moderation is the backstop after this.

### B3-D6 · A person must be found, unless a face already shows one

**Choice.** If Vision finds no face, the photo needs a human rectangle (whole or upper body), or the person is asked to retake. A photo with a face skips that check, since a face means a person is there (and it's blurred).

**Why.** The spec's retake rule is about empty photos. Neck-down outfit photos have no face, so the human rectangle request is what tells them apart from a photo of a wall.

### B3-D7 · The watermark is drawn with a built-in pixel font

**Choice.** The viewer's code is drawn as SVG rectangles from a 5×7 pixel font in `glyphs.ts`, repeated diagonally across the whole photo, once in white and once in black, each at 12% opacity.

**Why.** Vercel's functions have no system fonts, so SVG text could render as nothing and silently drop the watermark. Two passes keep it visible on white shirts and black jackets alike without being loud.

### B3-D8 · Private images are never cached, in memory or on disk

**Choice.** `PrivateImageLoader` fetches every image through `GlowAPI` (ephemeral session, no URL cache, D42), keeps no in-memory cache, and `PrivateImageView` holds the decoded image only in its own state. Card links must be a relative `/api/cards/{id}/image?exp&sig` path or nothing is sent, so a link can never carry the token to another host.

**Why.** Spec step 10 ("Display with caching turned off"), and a card should disappear from the phone the moment it leaves the deck. When a 60-second link has expired, the view reports `.notFound` and C1 refetches the deck for fresh links.

### B3-D9 · Cheap checks run before moderation, and a failed check-in leaves no photo

**Choice.** Check-in runs: rate limit, join ticket, base64 and size checks, then moderation, then storage, then `create_checkin`. If `create_checkin` fails, the photo just stored is deleted before the error goes back, and the photos of replaced check-ins are deleted at once rather than at the next purge.

**Why.** An expired ticket shouldn't cost a moderation call, and no photo should outlive the check-in it belonged to.
### B5-D3 · A token that moves to another person gets a new device ID

**Question.** The contract says registering an existing token moves it to the signed-in person. Should the device keep its ID?

**Choice.** If the token belonged to someone else, the server deletes that row and inserts a fresh one, so the new person gets a new device ID and the old person's ID stops working (404). The same person registering again keeps their ID.

**Why.** Two accounts used on one phone shouldn't be linkable through a shared ID, and the first account can't remove or probe the second one's device.

### B5-D4 · Sign-out removes the push token first

**Question.** After sign-out the app has no session, so it can't tell the server to stop pushing to this phone. Lock screen text never has names, but "New message" on a phone that's been handed to someone else still says something happened.

**Choice.** `PushService.unregister()` deletes this phone's device row; Session (B1) calls it before signing out. Signing in as someone else also moves the token (B5-D3), and `DELETE /api/me` (B8) deletes every device with the account.

**Why.** The person signing out is the only one who can authorize the delete, and only while signed in.

### B5-D5 · Sandbox or production comes from the build configuration

**Choice.** Debug builds (Xcode, `aps-environment` development) register their token as `sandbox`; Release builds (TestFlight, production) as `production`. The server picks the APNs host from each device row, and prunes a token Apple rejects (a wrong environment shows up as `BadDeviceToken`), which the app re-registers on its next launch.

### B5-D6 · Events never navigate by themselves

**Question.** Should a Realtime event (say `match.created`) open a screen on its own?

**Choice.** No. `RealtimeEvent.destination` names each event's screen, but only a tapped notification uses it (`PushService.route(for:)`). Features subscribe to the events they care about and decide; the app root can choose takeovers (the mutual moment, the glow) from the same stream.

**Why.** An event is a hint to refetch. Yanking someone to another screen from a background event would surprise them, and a stale or forged event could steer the app.

### B5-D7 · How long Apple keeps trying a push

**Choice.** `apns-expiration` is the push's usefulness: `glow.started` lasts `GLOW_TTL`, `checkin.expiring` lasts `CHECKIN_EXPIRY_WARNING`, `match.recheck` lasts `CHOICE_WINDOW`, and `match.created` and `message.created` an hour. `apns-collapse-id` comes from `events.json`, so a phone that was offline gets one notification per match, not a pile.

**Why.** A "Time to find each other" that arrives after the glow ended is worse than none.

### B5-D8 · Which push failures delete a token

**Choice.** Only Apple's dead-token answers delete a device: 410 (`Unregistered`, `ExpiredToken`), `BadDeviceToken` and `DeviceTokenNotForTopic`. 429 and 5xx are retried once; an expired provider token is re-signed once; everything else is logged (event type, status and reason only) and the device kept. A provider token is reused for 50 minutes.

### B5-D9 · Events are never replayed

**Choice.** The app's event stream only carries events sent after a screen subscribed; a screen that opens later never sees an old one. When the app comes back to the foreground, the service refreshes its token, rejoins any channel that dropped, and reports `.connected` again, so screens refetch whatever they missed.

**Why.** Replaying an old `match.created` could show a mutual moment twice; refetching from the API is always right.

### B5-D10 · Integration tests use the CLI's demo keys

**Choice.** `server/tests/notify/*` integration tests (Realtime channels, the device store) talk to the local stack with the Supabase CLI's public demo keys, the ones in `server/.env.example`, unless `GLOW_IT_SUPABASE_*` say otherwise. They refuse any non-local URL, create throwaway `@glow.test` people, delete them afterwards, and skip when no local stack answers. CI's Ubuntu job starts Supabase before Vitest, so they run there.
## A1 · Integrator and repo

### A1-D1 · Parallel agents share one Mac without sharing state

**Question.** Nine Wave 1 agents build and test on the same Mac at once. Simulators are global to the Mac, port 3000 can only be taken once, and `supabase db reset` on the one local stack would wipe everyone's data.

**Choice.** `scripts/agent-env.sh <ID>` gives each agent its own Simulator names (`Glow A (B1)`), server port (3090 plus a fixed index: B1 3101 to B9 3109, C1 3111 to C4 3114, D1 3121 to D5 3125) and API URL, which `sim.sh` bakes into the Debug app. Everyone shares the `glow` Supabase stack through the API; anyone who changes the schema or needs a reset takes their own stack with `--own-db` (a copy of their worktree's `supabase/`, project `glow-<id>`, ports 55000 plus 10 times the index). `pnpm db:reset` and `pnpm db:stop` refuse on the shared stack when `GLOW_AGENT_ID` is set, and `sim.sh teardown` won't delete the shared default Simulators without `--yes`.

### A1-D2 · macOS CI runs where it pays

**Question.** macOS minutes cost ten times Linux minutes on a private repo, and nine agents pushing drafts would run the iOS job hundreds of times.

**Choice.** The macOS job runs on every push to main, and on a PR only once it's ready for review and changes `ios/`, `contracts/`, `scripts/sim.sh`, `scripts/codegen.sh`, the Swift lint configs or the CI workflow. While a PR is a draft, its owner proves iOS work locally with `scripts/sim.sh`. Main stays fully covered, so anything that slips through is caught on merge and reverted. The codegen tool and Swift packages are cached.

### A1-D3 · Error codes come only from the contract

**Choice.** `HttpError` takes only codes from the contract's `ErrorCode` enum (a type error otherwise), with `conflict(code, message)` for 409, `unprocessable(code, message, { reason })` for 422, and the contract's optional `reason` in every error body. The app can rely on every code it might see being in `openapi.yaml`.

### A1-D4 · Local CI is the merge gate while GitHub Actions is down

**Question.** Actions stopped starting jobs (billing), and nine agents still need a way to prove a PR before it merges.

**Choice.** `scripts/ci-local.sh <ID>` runs both CI jobs in the agent's own slot (its port, Simulator and own Supabase stack, reset to the branch's migrations) and prints one summary with the head SHA and whether it's rebased on main. A PR is mergeable when its author posts a passing summary for the current head SHA, rebased on main. `--server-only` skips the iOS job only when nothing under `ios/`, `contracts/`, `scripts/sim.sh` or `scripts/codegen.sh` changed.
## C3 · Glow mode

### C3-D1 · How the 300 code words were picked

**Question.** The brief asks for 300 short, friendly words, nothing romantic or rude and not easy to mishear. What counts?

**Choice.** `server/src/server/glow/words.ts` holds 300 hand-picked concrete words (animals, foods, things, places, weather), 3 to 9 lowercase letters. None is romantic or suggestive (no flowers, sweets or pet names, so no "tulip", "honey" or "peach"), rude or slangy ("cougar", "beaver"), an insult or a comment on a body ("hippo", "walrus"), or a common first name ("robin", "juniper"), so a word is never mistaken for the other person's name. None contains a glow color's name (no "sundial" next to the Sun glow) or is an everyday color. No two words rhyme (identical after their first consonants, like "rocket" and "pocket"), differ by one letter ("beagle" and "eagle"), or contain each other, and near-homophones are out ("prism" and prison, "pigeon" and pidgin, "palette"). `server/tests/glow/words.test.ts` checks every one of these rules, so a later edit can't quietly break them.

**Why.** People say the word across a loud room and read it off a screen held up in the air. A word that sounds like a name, a compliment or another word on the list defeats the point, and some read as a come-on in a dating app.

### C3-D2 · An ended glow is visible for GLOW_ENDED_RETENTION, then it's gone

**Question.** `GET /api/matches/{id}/glow` reads the glow through `get_match`, which returns the latest session whatever its age. How long should an ended glow stay readable?

**Choice.** An active glow is always returned. An ended one (met, canceled, expired) is returned only until `GLOW_ENDED_RETENTION` (10 minutes) after it ended, then the route answers 404 as if it were never there. `glow/met` and `glow/cancel` follow the same rule. Reading the glow applies its timeout first (through `get_match`), and the route sends `glow.ended` for anything that settled.

**Why.** Both apps need a few minutes to show how it ended, and nothing more. It also matches purge, which deletes the session after the same time, so the answer never depends on when the cron last ran.

### C3-D3 · glow.ended goes out once, from the call that ended the glow

**Question.** `glow_met` and `cancel_glow` return the same glow whether this call ended it or it had already ended. Which call sends `glow.ended`?

**Choice.** Before calling the function, the route reads whether the match has an active glow (`activeGlowId`). It sends `glow.ended` to both only if there was one and the answer is `met` (for We met) or `canceled` (for End glow or Switch to chat). Timeouts the function settled are sent from `settled`. Repeating a tap, or the second person canceling a moment later, sends nothing new.

**Why.** It saves the other phone a refetch and a flicker. Two calls racing at the same moment can still send it twice, which is harmless.

### C3-D4 · The Live Activity shows only what's on the glow screen, and leaves a minute after the glow ends

**Question.** The lock screen is visible to anyone near the phone. What may the glow's Live Activity show, and for how long?

**Choice.** Only the glow color, the code word, the meeting spot and the countdown, the same things the glow screen already holds up for the room. Never a name, a photo, a user ID or a match ID (P1, P6). The attributes carry the glow session's own random ID so the app can find the activity again; it's never shown. The stale date is the glow's end, so the lock screen and Dynamic Island read "Time's up" exactly on time even if the app is asleep. When the glow ends, the app ends the activity showing how it ended and lets the system remove it 60 seconds later (`dismissalPolicy: .after`), instead of the default of up to 4 hours. Starting a glow ends any other glow's activity. There are no push updates to the activity yet: ActivityKit push tokens need APNs (B5) and an Apple account.

**Why.** The code word shouldn't sit on a lock screen long after it means anything. A minute is long enough to read "You found each other".

### C3-D5 · "They tapped We met" shows by refetching every 5 seconds

**Question.** When one person taps We met, the other's screen should say so ("They tapped We met. Tap it when you've found each other."), but no event covers one person's tap. Add an event?

**Choice.** No new event. While the glow screen is open and the glow is on, the app refetches the glow every 5 seconds, and at once on `glow.ended` or `glow.started`. The countdown and the end are checked every second on the phone itself.

**Why.** `theyMet` is already in the contract and only ever goes to the other person in the match, during the glow. A new event would be a contract change for a hint that a 5-second refetch covers, at most 180 small requests per phone per glow.

### C3-D6 · Hide glow keeps it going, at the person's own brightness

**Choice.** A small "Hide glow" button closes the glow screen to the Matches tab without ending anything. Brightness and keep-awake go back to the person's own settings at once, and the Live Activity keeps counting. The glowing match in the Matches list opens it again (C2's routes). Ending is only ever We met, End glow (with a confirmation) or Switch to chat.

**Why.** Someone may need their phone for something else for a minute. Ending the glow by accident would cost both people their chance, and a forced full-brightness screen that can't be left isn't kind.

### C3-D7 · The color's name is written on the glow, and analytics never carry it

**Choice.** Under the code word the screen says "Aqua glow" (the color's name), so someone who can't tell the colors apart still knows what to look for. Analytics events are `glow_shown`, `glow_we_met_tapped`, `glow_end_tapped` (`as`: `cancel` or `switch_to_chat`) and `glow_ended` (`outcome`: `met`, `canceled` or `expired`), with no code word, color or meeting spot.

**Why.** Color alone excludes some people. And a word plus a color plus a time is enough to pick a pair out of a room's metrics, so none of them go to PostHog.

## D5 · Demo and launch kit

### D5-D1 · Test people never go into a real room

**Question.** `scripts/seed-demo.ts` can run against any Supabase with `--remote`. A typo in `--slug` could put twelve fake people into the real event room, where attendees would see and tap them.

**Choice.** The seed only touches a room whose name ends in "(test data)", and refuses (exit 2) for any other existing room, before creating anyone. Rooms it creates get that name. Seeded people have fixed IDs per room slug, `{slug}-{name}@glow.test` emails, first names starting with "Test", and `test_data` in their auth metadata, so `--remove` can always find exactly them, and nobody else.

**Why.** Attendees must never spend a tap, or their hope, on someone who doesn't exist.

### D5-D2 · The stage demo runs in its own test-data room

**Question.** The brief puts the stage phones, in demo mode, in "the real Cal Hacks room". Then the deck on the projector would show real attendees' outfit photos to the whole hall, and attendees could tap the presenters.

**Choice.** Two rooms. The attendee room has real people only, demo mode off, and is what the posters, the display QR and the projected live numbers point at. The stage room ("Glow stage room (test data)", made by the seed) holds only the two admin stage phones and seeded test people, with demo mode on. Only the stage room's deck is ever shown.

**Why.** A card is shown to the people in the room with you, not to an audience. Seeded numbers are never presented as real ones either.

### D5-D3 · Seeded join checks are recorded as demo-mode skips

**Choice.** `create_checkin` needs a passed join check (D49). The seed writes `result = 'demo_skip'` (no accuracy bucket), never `pass`, and only in a room it controls.

**Why.** Nobody stood anywhere; a fake pass would be a lie in a table meant as proof. Skips are already counted on the admin room page, so they're visible.

### D5-D4 · The venue is one edit, and the tests keep the Simulators in step

**Choice.** `VENUE` at the top of `scripts/seed-demo.ts` (center, radius, timezone, meeting spots, table, and `confirmed: false`) is the only place D5's material reads the venue from. `--print-venue` prints it for the admin web and as the two lines for `ios/fixtures/demo-room.env` (A1's file, which `sim.sh at venue` reads). A test fails while the two differ, and the seed prints the lines to copy.

### D5-D5 · The deck is never mirrored to the projector

**Choice.** The stage shows phone A through a document camera (or the backup video), never AirPlay or screen sharing, and P12 stays on: if the deck hides when someone mirrors it, that's a line in the pitch, not a bug to work around. No Debug switch to turn P12 off was asked for.

### D5-D6 · Outreach collects nothing about anyone

**Choice.** The first-50 plan is posters, one Discord message, the table and visits to nearby teams, and only once the public TestFlight link works and the organizers agree. No sign-up sheet, waitlist or email collection as a fallback, and no per-poster tracking. Success is measured on the room's anonymous live numbers.

### D5-D7 · The Devpost draft says what's simulated

**Choice.** The draft has a "What's real and what's simulated" section: the stage room's seeded test people and their public-domain cards, the admin location skip, and (if true on the day) push, TestFlight review or Simulators. It's a draft for David; D5 posts nothing.

### D5-D8 · Seeded people have no profile photos and never tap

**Choice.** Seeded people get a complete profile but no profile photos (no real person's photo is used beyond the public-domain NASA outfit crops), and the seed never records a tap from them. So nobody can ever match a seeded person, and the reveal never shows a fake face.

### D5-D9 · The seed leaves an existing room's demo mode alone

**Choice.** A room the seed creates has demo mode on. An existing room keeps its setting unless `--demo-mode` is passed, so seeding the shared local `demo` room doesn't let `admin@glow.test` skip location checks in other agents' tests.
## C4 · Chat

### C4-D1 · The thread is checked before the text goes anywhere

**Question.** Sending runs a rate limit, moderation and `send_message`, which rejects blocked, unmatched and still-choosing threads. In which order?

**Choice.** Rate limit, then a blank-body check, then `get_match` (404 if the match isn't mine or ended, 409 `chat_not_open` while choosing), then moderation, then `send_message`, which repeats the thread check in the same transaction as the insert. So a blocked or unmatched person's text is never sent to the moderation model, and a flagged message to a closed chat answers 404 or 409, never 422. `get_match` also applies the lazy timeouts, so a choice window that ran out opens the chat at once, and its `settled` events (match.choice, glow.ended) are sent by the chat route.

**Why.** Message text should reach as few places as possible, and only for a thread the sender may write in. The cost is one extra database round trip per message.

### C4-D2 · Messages are stored pending, then marked passed

**Question.** B8's notes say to pass the verdict to `send_message`, but `send_message` has no moderation argument; every row starts `pending`.

**Choice.** After `send_message`, a `passed` verdict updates that row to `passed`, only if it's still `pending` and its body is the text that was checked (a retry with an old `clientId` returns the first message, which may differ). No migration. If the update fails, the message stays `pending`: it's delivered as usual and B8's review checks it again.

**Why.** It fails safe: the worst case is one more review, never an unchecked message marked passed.

### C4-D3 · Review-flagged messages disappear for the recipient, and say nothing to the sender

**Choice.** A message B8's review flags after the fact is left out of `listMessages` for the recipient and still shown to its sender, with no sign it was flagged (the contract has no field for it). The app replaces what each refresh covers, so a flagged message disappears from the recipient's open thread on the next event or refresh.

**Why.** The recipient is the one to protect. The sender already knows what they wrote, and telling them which message was flagged would teach them how to get around the filter.

### C4-D4 · Pages never end inside a millisecond

**Question.** `before` and `nextBefore` have millisecond precision, the database keeps microseconds, and a Swift `Date` loses up to a millisecond when it's formatted again.

**Choice.** A page that's full drops the messages of its oldest millisecond, and `nextBefore` is the start of the millisecond after it, so the next page (`created_at < nextBefore`) picks all of them up and nothing is skipped or repeated. A page can therefore hold a few fewer than `limit` messages. The app adds half a millisecond to `nextBefore` before sending it back, so the formatter lands on the exact millisecond whether it truncates or rounds (`LiveChatAPI.wireDate`, tested for all 1,000 values).

### C4-D5 · Messages show exactly as written

**Choice.** Message text is drawn verbatim: no Markdown, no tappable links, no link previews, no data detectors, and no suggested replies or openers. People can select and copy text.

**Why.** A link preview would make the phone fetch whatever URL the other person sent, which tells that server the reader's IP address and that they opened the chat. Markdown would let a message disguise a link. Suggestions would put words in people's mouths (brief: no AI in chat).

### C4-D6 · An unmatch sends exactly what a block sends

**Choice.** Unmatch sends `match.ended` to both people and `deck.changed` to every room where either has an open check-in: the same events, to the same people and rooms, as B8's block (B8-D6). A test runs an unmatch and a block side by side and checks that what goes out is identical. The app of the person who unmatched goes to the Matches tab. The other person's open chat refetches on the event, gets 404 and shows "This chat has ended." with no reason (D18).

**Why.** If a block sent `deck.changed` and an unmatch didn't, the other person's phone could tell which one happened from whether a room event arrived at the same moment. And the room's decks really did change: after an unmatch the two are eligible for each other again (D16). (C4 first chose no room event, then matched B8 at B8's request.)

### C4-D7 · The open chat refetches on any event about its match

**Choice.** FeatureChat doesn't branch on event types: any Realtime event whose match ID is this chat's (message.created, match.ended, glow.ended, match.choice) refetches the newest page, and a 404 closes the thread. Bursts fold into at most one extra request. It also refetches when the app comes back to the foreground, because events sent while it was suspended never arrive.

**Why.** Events carry only a type and a match ID anyway (P1), and one code path that asks the server is harder to get wrong than one per event.
