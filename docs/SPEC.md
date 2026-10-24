# Technical spec

This is what every agent builds against. If the code and this spec disagree, the spec wins until a contract change updates both. Export this tab as Markdown and commit it as docs/SPEC.md. Throughout, {DOMAIN} is the app's web domain and {BUNDLE} is its bundle ID.

## Product flow

This build has one mode: Live Room. Crossed Paths stays on the roadmap.

1. **Sign in** with Apple, or with a 6-digit email code. Add a first name, birthday (18+ only), gender, who you want to see, and 1 to 3 profile photos.
2. **Join a room** by scanning its QR code with the iPhone camera. The link opens Glow directly. The app checks you're inside the room's area, then forgets your location.
3. **Check in** with a quick photo of today's outfit. Apple's Vision framework blurs any face on the phone before upload. Add a few tags, like glasses or green hoodie.
4. **Pick what you noticed** (gender, top color, hair), then scroll a small deck of today's-look cards. No faces, names or distances.
5. **Tap** the person you noticed. They aren't told. You get 3 taps per room per day.
6. **It's mutual** if they tap you too. Both phones buzz, and each of you sees the other's real profile for the first time.
7. **Choose** Find each other or Just chat. Find only happens if both pick it.
8. **Glow.** Both screens go to full brightness in the same color, with the same code word and a meeting spot. A Live Activity on the lock screen counts down 15 minutes.
9. **We met.** Both tap it, and the chat stays open.

## Architecture

&#91;embedded content: architecture · iPhone app, API, Supabase\]

The app holds only the anon key. It signs in and listens to its own channel directly, and everything else goes through the API, the only place that holds the service role key.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| iPhone app | Swift 6, SwiftUI, iOS 17 minimum, Observation, async/await | Native camera, Vision, push, haptics and Live Activities |
| Project setup | XcodeGen (`project.yml`) plus one local Swift package, GlowKit, with a module per feature | Many agents work in parallel without fighting over one project file |
| API client | Apple's swift-openapi-generator, from `contracts/openapi.yaml` | One contract, typed on both sides |
| Backend services | Supabase: Postgres, Auth, Storage, Realtime, with supabase-swift in the app | Strong database guarantees, private files, live events |
| Server | Next.js on Vercel: API routes, admin web, display page, posters, the universal link file | sharp for watermarks, Node's http2 for Apple push, one deploy per PR |
| Sign in | Sign in with Apple, plus a 6-digit email code as backup | Fast and private; codes work in the Simulator too |
| Push | Apple Push Notification service with token auth (.p8 key), sent with Node http2 and jose | No third-party push service needed |
| Face blur | Vision face detection plus Core Image blur, on the phone | Works in the Simulator, and faces never leave the device |
| QR | Universal links, plus an AVFoundation scanner inside the app | The iPhone camera opens Glow directly |
| Location | CoreLocation, When In Use, precise | One check, then forgotten |
| Glow extras | ActivityKit Live Activity, SwiftUI sensory feedback and Core Haptics, screen brightness, idle timer off | The moment feels special and the screen stays visible |
| Moderation | Claude API, `claude-haiku-5-5` with vision | Fast checks on photos and messages |
| Signing | jose (JWT) and Node crypto HMAC | Join tickets, signed image links, rotating QR codes |
| Rate limits | Upstash Redis with @upstash/ratelimit | Works on serverless |
| Analytics and errors | PostHog and Sentry, in the app and on the server, with no personal data | Demo metrics and crash reports from real phones |
| Tests | Swift Testing, XCTest and XCUITest, swift-snapshot-testing, Vitest, pgTAP | Unit, snapshot, end to end and database |
| Release | fastlane with an App Store Connect API key, to TestFlight | One command ships a build |

## Repo layout

```
glow/
  AGENTS.md                 rules, privacy invariants, ownership map, commands
  docs/                     SPEC.md, CONTRACTS.md, HANDOFFS.md, DECISIONS.md,
                            SECURITY_REVIEW.md, DEVICE_QA.md, RELEASE.md, DEMO.md, shots/
  contracts/
    openapi.yaml            single source of truth for the API
    events.json             realtime and push event shapes
    constants.json          shared numbers (time limits, caps)
  supabase/                 config.toml, migrations/, tests/, seed.sql
  server/                   Next.js on Vercel
    app/api/...             API routes
    app/admin/...           admin web
    app/display/[slug]/     rotating QR screen
    app/r/[slug]/           fallback page when Glow isn't installed
    app/.well-known/apple-app-site-association/
    src/server/             auth, profiles, rooms, geo, qr, images, deck, taps, matches,
                            glow, chat, safety, moderation, notify, admin, ratelimit
    src/contracts/          generated types and zod schemas
    src/env.ts
  ios/
    project.yml             XcodeGen spec (the .xcodeproj is generated, never committed)
    Glow/                   app target: entry point, root navigation, push delegate,
                            Info.plist, entitlements, xcconfig files
    GlowLiveActivity/       widget extension for the glow countdown
    Packages/GlowKit/       local Swift package, one module per owner (see next section)
    GlowUITests/
    fastlane/
    fixtures/               outfit photos and push payloads for the Simulator
  hardware/badge/           Wave 4 only
  scripts/                  sim.sh, codegen.sh, e2e/, seed-demo.ts
```

## iOS modules and owners

Each agent owns whole modules, so nobody edits the same Swift files. Feature modules depend only on AppCore, DesignSystem and the service modules, never on each other. They move between screens by sending a Route.

| Module | What's inside | Owner |
| --- | --- | --- |
| App target (`ios/Glow`) | App entry, root navigation, push delegate, entitlements | A3 |
| AppCore | The Route enum, the dependency container (every service as a protocol), shared models, preview mocks | A3 |
| APIClient | Generated OpenAPI client, plus a wrapper that adds the sign-in token, retries and not-found errors | A2 (generated), A3 (wrapper) |
| DesignSystem | Colors, type, spacing, components, GlowSurface, haptics | B6 |
| Session | Supabase sign-in, Sign in with Apple, email code, session restore | B1 |
| Location | One precise location fix for room checks | B2 |
| Imaging | Camera capture, Vision face blur, JPEG export with no metadata | B3 |
| Push | Apple push registration, notification categories, deep links from notifications | B5 |
| Realtime | Supabase Realtime private channels and an in-app event stream | B5 |
| FeatureOnboarding | Welcome, sign in, profile, photos, notifications | B1 |
| FeatureSettings | Edit profile and photos, links to pause and delete | B1 |
| FeatureRooms | Scanner, room code entry, universal links, joining | B2 |
| FeatureCheckIn | Outfit photo, blur preview, tags | B3 |
| FeatureSafety | Block and report sheets, pause, delete account | B8 |
| FeatureDeck | What did you notice, the deck, tapping | C1 |
| FeatureMatch | Mutual takeover, reveal, choice, matches list | C2 |
| FeatureGlow | Glow screen, starting and ending the Live Activity | C3 |
| FeatureChat | Thread, composer, report and block from chat | C4 |
| GlowLiveActivity (extension) | Lock screen and Dynamic Island views for the glow countdown | C3 |

## Simulator workflow

Every iOS agent builds and tests on two Simulators, Glow A and Glow B, so one Mac can play both people in a match. A3 writes `scripts/sim.sh`, and everyone uses it the same way.

```
# one time
brew install xcodegen swiftlint swiftformat
pnpm install
supabase start                      # local database, auth, storage and realtime
pnpm --filter server dev            # local API on http://localhost:3000

# every session
scripts/sim.sh setup                # create and boot two simulators, Glow A and Glow B
scripts/sim.sh build                # xcodegen, then xcodebuild for the Simulator
scripts/sim.sh install              # install the Debug app on both
scripts/sim.sh at venue             # move both to the seeded room's center
scripts/sim.sh at away              # move both 2 km away, to test a failed room check
scripts/sim.sh photos               # add fixture outfit photos to both photo libraries
scripts/sim.sh scan demo            # open the demo room's link, as if its QR was scanned
scripts/sim.sh push A match_created # send a fixture notification to Glow A
scripts/sim.sh shot deck-empty      # save a screenshot of both to docs/shots/
scripts/sim.sh record               # record both screens until you stop it
scripts/sim.sh test                 # unit and UI tests on Glow A
```

Under the hood, `sim.sh` wraps `xcrun simctl` (create, boot, install, location, addmedia, openurl, push, io screenshot and recordVideo) and runs `xcodebuild` with the destination `platform=iOS Simulator,name=Glow A`. It picks the newest iPhone Pro runtime installed. Debug builds point at `http://localhost:3000` and the local Supabase, which the Simulator can reach on the same Mac. Debug builds also register a `glow://` link scheme, so `scan` works without a live domain.

| The Simulator can't | So agents |
| --- | --- |
| Use a camera | Use the photo picker with fixture photos, in Debug builds only. The real camera is tested on devices. |
| Use Bluetooth or Ultra Wideband | Leave all of Wave 4 to real iPhones |
| Play haptics | Check haptics on devices at Checkpoint 3 |
| Get real pushes without an Apple account | Use `sim.sh push` with fixture payloads |
| Always do Sign in with Apple | Use the email code, or the Debug-only test sign-in against local Supabase |

## Data model

All IDs are random UUIDs. A card's ID is its check-in's ID, so a card never carries a user ID. Every table has row level security turned on with no client policies, so only the server can read or write it.

| Table | Key columns | Notes |
| --- | --- | --- |
| profiles | id (the auth user's ID), first\_name, birthdate, gender, show\_me (list), paused, onboarding\_step, viewer\_code, created\_at | viewer\_code is a short random code printed in watermarks, so a leaked screenshot can be traced |
| profile\_photos | id, user\_id, path, position (0 to 2), moderation\_status | Served only to people with an active match |
| devices | id, user\_id, apns\_token, apns\_environment (sandbox or production), app\_version, created\_at, last\_ok\_at | Xcode builds use sandbox, TestFlight uses production. Rejected tokens are pruned. |
| admins | user\_id |  |
| rooms | id, slug, name, code (6 characters), lat, lng, radius\_m, qr\_secret, allow\_static\_qr, demo\_mode, status, starts\_at, ends\_at | A room's own location is a public venue, so it's fine to store |
| meeting\_spots | id, room\_id, name, sort | 3 to 5 per room |
| checkins | id (also the card ID), room\_id, user\_id, card\_path, top\_color, hair\_length, hair\_color, extras (list), visible, joined\_at, expires\_at, left\_at | One active check-in per person per room |
| card\_views | viewer\_id, checkin\_id, room\_id, viewed\_at | For the daily view cap. Purged after 48 hours. |
| taps | id, room\_id, from\_user, to\_user, created\_at, expires\_at | Unique per room, from and to. Lasts 24 hours. |
| matches | id, room\_id, user\_a, user\_b (a sorts before b), status, a\_choice, b\_choice, choice\_deadline, created\_at | One active match per pair |
| glow\_sessions | id, match\_id, room\_id, color, code\_word, spot\_id, started\_at, ends\_at, a\_met, b\_met, status | Color plus code word is unique among active sessions in a room |
| messages | id, match\_id, sender\_id, body, moderation, created\_at | Deleted on unmatch or account deletion |
| blocks | blocker\_id, blocked\_id, created\_at | Always checked in both directions |
| reports | id, reporter\_id, reported\_id, context (card, match or chat), context\_id, reason, details, status, created\_at |  |
| abuse\_signals | id, user\_id, room\_id, kind (screenshot, recording), created\_at | Repeated screenshots flag the account for review |

## Database functions

The rules that must never break live in Postgres, so a bug in a route can't skip them. Every function is security definer with a fixed search\_path, and only the server calls them.

| Function | What it does | Guarantees |
| --- | --- | --- |
| `create_checkin(user, room, card_path, tags)` | Ends any older check-in for that person in that room and starts a new one with a 3-hour expiry | One active check-in per person per room |
| `get_deck(viewer, room, filters, limit, offset)` | Returns eligible cards in a shuffled order that stays the same for the viewer all day | Every deck rule in Core rules, in one place |
| `card_visible_to(viewer, checkin)` | Yes or no, used by the image route | Same rules as the deck |
| `record_tap(viewer, room, checkin)` | Checks the card is in the viewer's deck and the daily cap, saves the tap, and makes a match if the other person already tapped back | An advisory lock on the pair, so two taps at the same moment make exactly one match |
| `set_choice(user, match, choice)` | Saves Find or Chat and returns what happens next | Find only proceeds when both chose it before the deadline |
| `start_glow(match)` | Picks a color, code word and meeting spot that no other active glow in the room is using | A unique partial index backs this up |
| `purge_expired()` | Deletes expired check-ins, old taps, ended glows and old card views, and returns the photo paths to delete | Called by the cron route every 5 minutes |

## API contract

Every request sends the Supabase access token as a Bearer token, and the server checks it. Full request and response shapes live in `contracts/openapi.yaml`. Anything the caller isn't allowed to see returns 404.

| Endpoint | Does | Owner |
| --- | --- | --- |
| `GET /api/me` | My profile, photos and onboarding step | B1 |
| `PUT /api/me/profile` | Save first name, birthday, gender and who I want to see | B1 |
| `POST /api/me/photos`, `DELETE /api/me/photos/:id` | Add (moderated) or remove a profile photo | B1 |
| `POST /api/dev/test-login` | Debug-only sign-in for Simulator tests. Refused unless `ALLOW_TEST_LOGIN` is set. | B1 |
| `POST /api/me/pause` | Pause or resume being visible | B8 |
| `DELETE /api/me` | Delete my account and all my data | B8 |
| `POST /api/devices`, `DELETE /api/devices/:id` | Register or remove a push token | B5 |
| `POST /api/rooms/resolve` | Room code, or slug plus QR token, returns the room's name and end time | B2 |
| `POST /api/rooms/:id/join` | Token plus one location fix returns a 10-minute join ticket | B2 |
| `POST /api/rooms/:id/leave` | End my check-in now and delete my card | B2 |
| `POST /api/rooms/:id/checkin` | Join ticket plus blurred photo plus tags creates my card | B3 |
| `GET /api/cards/:cardId/image` | Watermarked card photo, through a signed 60-second link | B3 |
| `POST /api/rooms/:id/deck` | Filters return up to 10 cards with signed image links | B4 |
| `POST /api/rooms/:id/taps` | Secret tap, returns sent or mutual and taps left today | B4 |
| `GET /api/matches` | My active and past matches | B4 |
| `GET /api/matches/:id` | One match, with the other person's first name and photo count | C2 |
| `GET /api/matches/:id/photos/:n` | The other person's profile photo, for active matches only | B3 |
| `POST /api/matches/:id/choice` | Find (with a fresh location fix) or Chat | C2 |
| `GET /api/matches/:id/glow`, `POST .../glow/met`, `POST .../glow/cancel` | The glow session and its end | C3 |
| `GET` and `POST /api/matches/:id/messages` | Read and send chat messages | C4 |
| `POST /api/matches/:id/unmatch` | End the match for both people | C4 |
| `POST /api/blocks` | Block someone from a card, match or chat ID | B8 |
| `POST /api/reports` | Report someone (this also blocks them) | B8 |
| `POST /api/abuse/capture` | Log a screenshot or screen recording of the deck | B8 |
| `GET /api/cron/purge` | Expiry cleanup, protected by the cron secret | B8 |
| `/api/admin/*` | Rooms, meeting spots, posters, display tokens, reports, metrics, demo mode | B7 |
| `GET /.well-known/apple-app-site-association` | The file that lets QR links open the app | B2 |
| `GET /r/:slug` | Web page for people who don't have Glow yet, with the TestFlight link | B2 |

## Events and push

The server sends every event two ways: over Realtime to the person's private channel, and as an Apple push when the event needs one. Payloads carry only the event type plus a match or room ID, never a user ID or name. The app refetches details from the API.

| Event | Sent when | To | Lock screen text |
| --- | --- | --- | --- |
| `match.created` | The second tap lands | Both people | Someone you noticed noticed you back. |
| `match.choice` | The other person chooses | The other person | No push |
| `glow.started` | Both chose Find | Both people | Time to find each other. (time sensitive) |
| `glow.ended` | Both met, someone canceled, or time ran out | Both people | No push |
| `message.created` | A new chat message arrives | The recipient | New message |
| `checkin.expiring` | 15 minutes before a check-in ends | That person | Your check-in ends soon. |
| `deck.changed` | Someone in the room pauses, leaves or blocks | Everyone checked into that room | No push |

Channels: `user:{id}` is private to that person. `room:{id}` is private to people with an active check-in in that room.

## Core rules and numbers

**Who appears in your deck.** All of these must be true:

- You and they both have an active check-in in this room: not expired, not left, not paused.
- Their gender is in your show me, and your gender is in theirs.
- Neither of you has blocked the other.
- You don't already have an active match.
- Their card fits the filters you picked under What did you notice.
- You haven't used up today's card views in this room.

The order is shuffled with a seed made from your ID, the room and today's date. Refreshing gives the same order, so nobody can work out who arrived when.

**Taps and matches.** You can only tap a card that's in your deck right now. A tap lasts 24 hours. If the other person tapped you in the same room within that time, `record_tap` makes the match in the same transaction.

**Choosing and glow.** Each person has 10 minutes to choose. If both pick Find, the server checks that both are still checked in and both passed a location check in the last 2 minutes, then starts the glow. Any other result opens the chat. A glow ends after 15 minutes, when both tap We met, or when either person cancels.

These numbers live in `contracts/constants.json`, which generates Swift and TypeScript constants. Nobody hardcodes them.

| Constant | Value |
| --- | --- |
| CHECKIN\_TTL | 3 hours |
| CHECKIN\_EXPIRY\_WARNING | 15 minutes before |
| TAP\_TTL | 24 hours |
| TAPS\_PER\_ROOM\_PER\_DAY | 3 |
| CARD\_VIEWS\_PER\_ROOM\_PER\_DAY | 50 |
| DECK\_PAGE\_SIZE | 10 |
| ROOM\_RADIUS\_DEFAULT | 200 m |
| GEO\_MAX\_ACCURACY | 500 m |
| GEO\_ACCURACY\_CREDIT | up to 100 m |
| GEO\_FRESHNESS\_FOR\_GLOW | 2 minutes |
| CHOICE\_WINDOW | 10 minutes |
| GLOW\_TTL | 15 minutes |
| QR\_ROTATION | 30 seconds, current and previous window accepted |
| JOIN\_TICKET\_TTL | 10 minutes |
| CARD\_URL\_TTL | 60 seconds |
| MESSAGE\_MAX\_CHARS | 1,000 |
| MODERATION\_TIMEOUT | 2.5 seconds |
| PURGE\_INTERVAL | 5 minutes |

## Private images on device

The original photo never leaves the phone. Only the blurred version is uploaded.

1. **Capture** with AVFoundation, up to 1920 px on the long side. Debug Simulator builds use the photo picker and fixture photos instead.
2. **Find faces** with Vision's face rectangle request. Grow each face box by 30% on every side.
3. **Blur** inside each box with Core Image: a strong Gaussian blur plus pixelation, so no face can be recovered.
4. **Check for a person** with Vision's human rectangle request. If nobody is in the photo, ask for a retake.
5. **Preview.** Show "This is what others will see" with the blur visible. The person confirms.
6. **Export** a JPEG at quality 0.8 with all metadata removed (no location, no device info). Keep the original only in memory, and drop it right after export.
7. **Upload** to `POST /api/rooms/:id/checkin` with the join ticket. The server's Claude moderation rejects photos with a visible face, nudity, or no outfit.
8. **Store** privately as `room-cards/{roomId}/{cardId}.jpg`.
9. **Serve** only through the card image route. It checks the viewer, adds a faint repeated watermark of the viewer's code with sharp, and sends no-cache headers.
10. **Display** with caching turned off. The app never saves cards to the photo library.

## Location check

1. Ask for When In Use location, precise. If the person only allowed approximate location, ask for temporary full accuracy for this check, with a purpose string that explains why.
2. Get one fresh fix, waiting up to 10 seconds.
3. Send latitude, longitude and accuracy to `POST /api/rooms/:id/join`.
4. The server passes the check if the distance from the room's center, minus the smaller of the accuracy and 100 m, is within the room's radius. It rejects any fix with accuracy worse than 500 m and asks the person to try again.
5. The server keeps only pass or fail and a rough accuracy bucket. Coordinates are never stored or logged, and Sentry and PostHog scrub them.
6. Choosing Find repeats the check before a glow starts.
7. In a room with demo mode on, people signed in as admins skip the check, and every skip is logged.

## QR codes, universal links and room codes

- **The link.** A room's QR code holds `https://{DOMAIN}/r/{slug}?t={token}`. With Associated Domains set up, the iPhone camera opens Glow straight to that room. If Glow isn't installed, the same link shows a web page with the TestFlight link.
- **Printed posters** use a static token per room, and only rooms with `allow_static_qr` accept it.
- **Screens** show a token that changes every 30 seconds: the first 8 base32 characters of an HMAC-SHA256 of the current 30-second window, keyed with the room's secret. The server accepts the current and the previous window, and compares in constant time.
- **Room codes.** Every room also has a 6-character code people can type in.
- **In-app scanner.** An AVFoundation scanner covers people who open Glow first.
- **Always.** A QR code, poster or room code only gets you to the location check. It never gets you into a room by itself.

## Design system

Glow should feel calm, warm and a little magical: a dark, quiet app where the only bright thing is the glow. B6 builds these as Swift tokens in DesignSystem, and B7 mirrors them as CSS variables for the admin web.

| Token | Value | Used for |
| --- | --- | --- |
| background | #0B0B10 | App background. The app is always dark. |
| surface | #16161D | Cards and sheets |
| surfaceRaised | #20202A | Pressed and raised elements |
| textPrimary | #F4F4F6 | Main text |
| textSecondary | #A1A1AA | Secondary text |
| line | #2A2A35 | Dividers |
| accent | #FF4FA3 | Primary buttons and focus |
| danger | #FF5A5F | Block, report and delete |
| Type | SF Pro, with SF Pro Rounded for the code word | Dynamic Type everywhere |
| Corners | 12 for controls, 20 for cards and sheets, capsules for chips |  |
| Spacing | A 4-point grid |  |
| Motion | 0.2 s ease-out for UI, a spring for the reveal, a 1.25 s loop for the glow | Reduce Motion turns pulses into a slow fade |

**Glow colors.** Eight, picked so no two look alike across a room: Ember #FF6B2C, Rose #FF3D8B, Violet #8C5BFF, Sky #2F8CFF, Aqua #12D6C5, Lime #9BE52E, Sun #FFD23F and Pearl #F2F2F7. The code word is black on Aqua, Lime, Sun and Pearl, and white on the rest.

**Flash safety.** The glow pulses less than once per second and never dims below 70% brightness. That keeps it far from the 3 flashes per second limit that can trigger seizures.

**Voice.** Warm, calm, never pushy.

| Moment | Say | Don't say |
| --- | --- | --- |
| Confirming a tap | They won't know unless they tap you too. | Send your crush a signal! |
| Mutual | Someone you noticed noticed you back. | It's a match!!! |
| Empty deck | Nobody fits that yet. Try fewer details. | No results. |
| After blocking | Done. They won't see you again. | User blocked. |
| Failed room check | Looks like you're not in this room yet. Try again inside. | Location verification failed. |

## Environment and secrets

| Name | Where | Notes |
| --- | --- | --- |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | iOS xcconfig and server | The only keys the app ever holds |
| `API_BASE_URL` | iOS xcconfig | `http://localhost:3000` in Debug, `https://{DOMAIN}` in Release |
| `SUPABASE_SERVICE_ROLE_KEY` | Server only | Never in the app or the admin bundle. D2 checks. |
| `ANTHROPIC_API_KEY` | Server | Moderation |
| `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID` | Server | The .p8 key from B9. Each device row says sandbox or production. |
| `JOIN_TICKET_SECRET`, `CARD_URL_SECRET` | Server | At least 32 random bytes each |
| `CRON_SECRET` | Server | Protects the purge route |
| `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN` | Server | Rate limits |
| `POSTHOG_KEY` | App and server | No personal data in events |
| `SENTRY_DSN` | App and server | Scrub request bodies and coordinates |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY` | CI only | TestFlight uploads |
| `ALLOW_TEST_LOGIN` | Local only | Never set on Vercel |

## Testing and definition of done

| Layer | Tool | Must cover |
| --- | --- | --- |
| Database | pgTAP through `supabase test db` | Locked-down tables, every deck rule, tap caps, simultaneous mutual taps, blocks, expiry |
| Server | Vitest | Every route's sign-in check and 404 rule, location math, QR token windows, watermarks, push payloads |
| Contracts | Codegen check in CI | Generated clients are up to date, and every response matches `openapi.yaml` |
| iOS units | Swift Testing | View models, the blur pipeline on fixture photos, location logic |
| iOS snapshots | swift-snapshot-testing | Every screen at default and largest text size |
| End to end | XCUITest on Glow A, with person B played by a script through the API | The full loop from sign-in to We met, plus chat, block and expiry |
| Devices | Real iPhones from TestFlight | Camera, haptics, push while locked, glow brightness, GPS inside the venue |

**Definition of done for every PR**

- [ ] Builds with no warnings under Swift 6 strict concurrency, and the server typechecks
- [ ] SwiftLint, SwiftFormat, ESLint and Prettier pass
- [ ] New logic has tests, and CI is green
- [ ] New screens have Simulator screenshots and a recording in the PR, VoiceOver labels, and a Dynamic Type check
- [ ] No privacy invariant is weakened
- [ ] `docs/HANDOFFS.md` is updated

## Sources

- [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/overview-of-testflight/), App Store Connect Help
- [Passwordless email logins](https://supabase.com/docs/guides/auth/auth-email-passwordless), Supabase. Codes need `{{ .Token }}` in the email template, and expire after 1 hour by default.
- [Should you pay for the Apple Developer Program?](https://flaviocopes.com/apple-developer-free-vs-paid/), Flavio Copes
