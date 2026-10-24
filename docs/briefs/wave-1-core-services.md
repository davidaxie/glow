# Wave 1 · Core services

Nine agents in parallel. Each owns its own folders and codes against the contracts, mocking anything that isn't merged yet.

## B1 · Sign in and onboarding

**Mission.** Get a new person from first launch to a finished, 18+ profile in under two minutes.

**Read first.** In the Technical spec: Product flow, Data model (profiles, profile\_photos), API contract (`/api/me`), Design system. Privacy invariants P1 and P10.

**You own.** FeatureOnboarding, FeatureSettings, Session, `server/src/server/profiles`, `server/app/api/me/**` (except pause and delete), and `server/app/api/dev/test-login`.

**Build.**

1. A welcome screen that explains Glow in three short lines, including the privacy promise.
2. Sign in with Apple through supabase-swift's ID token sign-in, and email sign-in with a 6-digit code. Set the Supabase email template to send the code instead of a link.
3. A Debug-only test sign-in for Simulator automation. It's compiled out of Release, and the server refuses it unless `ALLOW_TEST_LOGIN` is set.
4. Profile: first name, birthday, gender and show me. Under 18 gets a kind message and can't continue. The server enforces this too.
5. 1 to 3 profile photos: pick, crop to 4:5, strip metadata, upload. The server runs B8's moderation and holds flagged photos for review.
6. A notifications step that asks for permission and registers through B5's Push module.
7. An onboarding state machine on the server (`onboarding_step`), so the app always resumes at the right step.
8. Settings: edit profile and photos, plus links to B8's pause and delete screens.

**Done when.**

- [ ] A fresh install reaches a finished profile on Glow A, with the email code and with test sign-in
- [ ] An under-18 birthday is blocked in the app and by the server
- [ ] Rooms can't be opened until onboarding is complete
- [ ] Snapshot tests for every onboarding screen at default and largest text size

**Hand off.** How other modules get the signed-in person and their profile.

## B2 · Rooms and joining

**Mission.** Get someone from a QR code to a verified spot in the room in under ten seconds.

**Read first.** In the Technical spec: Location check, QR codes, universal links and room codes, API contract (rooms). Privacy invariant P2.

**You own.** FeatureRooms, Location, `server/src/server/rooms`, `server/src/server/geo`, `server/src/server/qr`, the routes `/api/rooms/resolve`, `/api/rooms/:id/join` and `/api/rooms/:id/leave`, `server/app/r/[slug]`, and `server/app/.well-known/apple-app-site-association`.

**Build.**

1. Universal link handling for `https://{DOMAIN}/r/{slug}?t={token}`, plus the `glow://` scheme in Debug.
2. The apple-app-site-association file, served as JSON with no redirect.
3. An in-app QR scanner (AVFoundation) with a torch button, and 6-character code entry as a fallback.
4. `/api/rooms/resolve`: a code, or a slug plus token, returns the room's name and end time.
5. Static and rotating token checks: constant-time compare, current and previous 30-second window.
6. The Location module: precise When In Use, temporary full accuracy when needed, one fresh fix with a 10-second timeout.
7. `/api/rooms/:id/join`: the location check from the spec, returning a 10-minute join ticket (a JWT with person, room and time). Coordinates are never stored or logged. In a demo mode room, admins skip the check, and each skip is logged.
8. Friendly failure screens: not in the room yet, weak signal (try near a window or door), room ended.
9. `/api/rooms/:id/leave`, which also sends deck.changed to the room. C1 puts the Leave button on the room home.
10. The `/r/{slug}` web page for people without Glow, with the TestFlight link.

**Done when.**

- [ ] `sim.sh at venue` then `sim.sh scan demo` reaches check-in
- [ ] `sim.sh at away` shows the not-in-the-room screen
- [ ] Unit tests cover distance math right at the radius edge, and both token windows
- [ ] A test proves no coordinates reach logs (P2)

**Hand off.** How C1 gets the current room and check-in state.

## B3 · Check-in and private images

**Mission.** Turn an outfit photo into a card that only helps someone who saw you in person.

**Read first.** In the Technical spec: Private images on device, Data model (checkins, profile\_photos), API contract (check-in and images). Privacy invariants P1, P3, P4 and P11.

**You own.** FeatureCheckIn, Imaging, `server/src/server/images`, and the routes `/api/rooms/:id/checkin`, `/api/cards/:cardId/image` and `/api/matches/:id/photos/:n`.

**Build.**

1. Camera capture with a neck-down framing guide. Debug Simulator builds use the photo picker instead.
2. The on-device pipeline from Private images on device, ending in the blur preview the person confirms.
3. A tag picker: top color (10 options), hair length (3), hair color (6), and extras (glasses, hat, beard, headphones, backpack).
4. Upload with the join ticket. The server runs B8's moderation and returns a clear retake message on rejection.
5. Store the card and call `create_checkin`.
6. The card image route: a signed 60-second link bound to one viewer, the `card_visible_to` check, a faint repeated watermark of the viewer's code at about 12% opacity using sharp, no-cache headers, and 404 for anyone else.
7. The profile photo route, for active matches only.
8. An image loader in the app with caching turned off for both routes.

**Done when.**

- [ ] Every fixture photo with a face comes out blurred, and the upload carries no metadata
- [ ] A face-visible or nude test photo is rejected with a retake message
- [ ] Expired links, reused links and viewers who can't see the card all get 404
- [ ] A snapshot of a served image shows the watermark

**Hand off.** The image loader API that C1 and C2 call.

## B4 · Deck and matching engine

**Mission.** Decide who sees whom, record taps, and create matches correctly under any load.

**Read first.** In the Technical spec: Core rules and numbers, Database functions, API contract (deck, taps, matches). Privacy invariants P1, P5 and P11.

**You own.** `server/src/server/deck`, `server/src/server/taps`, `server/src/server/matches` (creation and listing), the routes `/api/rooms/:id/deck`, `/api/rooms/:id/taps` and `GET /api/matches`, and new migrations prefixed `b4`.

**Build.**

1. `/api/rooms/:id/deck`: validate the filters, call `get_deck`, count views against the daily cap, and return up to 10 cards with B3's signed links and their tags. Never a user ID.
2. `/api/rooms/:id/taps`: call `record_tap` and return sent or mutual, taps left today, and the match ID when it's mutual. On mutual, call B5's `notify` for both people.
3. `GET /api/matches`: active and past matches, with first names (only ever for people you've matched with).
4. If `get_deck` or `record_tap` need tuning, do it in new migrations, with query plans in the PR.

**Done when.**

- [ ] Integration tests cover every deck rule in the spec
- [ ] Load test: with 300 people checked in, deck responses stay under 300 ms at p95
- [ ] 50 pairs tapping each other at once through the API make exactly 50 matches
- [ ] No response, count or timing reveals a one-sided tap (P5)

**Hand off.** The response shapes C1 and C2 rely on, with examples.

## B5 · Push, realtime and events

**Mission.** Make sure the right phone knows the moment something happens, without ever saying who.

**Read first.** In the Technical spec: Events and push, Data model (devices), Environment and secrets. Privacy invariants P1 and P6.

**You own.** Push, Realtime, `server/src/server/notify`, the routes `/api/devices`, and `ios/fixtures/push/`.

**Build.**

1. Push registration in the app. Upload the device token to `/api/devices` with its environment: sandbox for Xcode builds, production for TestFlight.
2. Notification categories for match, glow, message and expiry, and deep links from a tapped notification to the right Route.
3. The server sender: Apple push over HTTP/2 with Node's http2 module and a token signed from the .p8 key with jose. Use collapse IDs, mark `glow.started` as time sensitive, and prune tokens Apple rejects.
4. `notify(userId, event)`: a Realtime broadcast to `user:{id}` plus a push, with payloads built only from `contracts/events.json`.
5. The Realtime module: join `user:{id}` and the current `room:{id}` as private channels, expose an async stream of events, and reconnect when the app comes back to the foreground.
6. A fixture `.apns` file for every event, for `sim.sh push`.

**Done when.**

- [ ] `sim.sh push A <event>` opens the right screen for every event
- [ ] A test sends a real sandbox push to a registered device or Simulator
- [ ] Snapshot tests of every push payload show no names (P6)
- [ ] One person can't join another person's channel (test)

**Hand off.** How to subscribe to events in a feature module, with a code example.

## B6 · Design system

**Mission.** Make Glow look and feel calm, warm and a little magical, all from one shared module.

**Read first.** In the Technical spec: Design system, iOS modules and owners.

**You own.** DesignSystem, the app icon, and the launch screen assets.

**Build.**

1. The tokens from the spec as Swift Color and Font extensions, with Dynamic Type throughout.
2. Components: buttons (primary, secondary, quiet, danger), chips, a tag picker grid, a card tile with a watermark slot and a blur-while-captured modifier, bottom sheets, toasts, code entry fields, a step header, empty states, and a full-screen takeover.
3. GlowSurface: a full-screen color with a soft pulse slower than once per second, a slow fade under Reduce Motion, a brightness helper that restores the person's own level, and a keep-awake helper.
4. Haptics helpers for the mutual moment, the glow pulse and light taps.
5. A Gallery screen in Debug builds showing every component in every state.
6. The app icon and launch screen.

**Done when.**

- [ ] The Gallery shows every component, with snapshot tests at default and largest text size
- [ ] All text meets WCAG AA contrast
- [ ] GlowSurface respects Reduce Motion and always restores brightness
- [ ] A lint rule stops feature modules from defining their own colors or fonts

**Hand off.** A one-page usage guide in the module's README, with a picture of the Gallery.

## B7 · Admin and room ops

**Mission.** Let you set up and run a room from your phone in two minutes at the venue.

**Read first.** In the Technical spec: Data model (rooms, meeting\_spots, reports, admins), QR codes, universal links and room codes, Design system.

**You own.** `server/app/admin/**`, `server/app/display/[slug]`, `server/app/api/admin/**`, and `server/src/server/admin`.

**Build.**

1. Admin sign-in with Supabase plus a check against the admins table. Everyone else gets 404.
2. Rooms: create with a name, a Set center to my location button, a radius slider on a map (MapLibre with OpenStreetMap tiles), 3 to 5 meeting spots, and start and end times.
3. A poster PDF with a big QR code, the room code, and three-step instructions.
4. A display page with a full-screen QR code that changes every 30 seconds.
5. Room controls: pause, end, remove a card, remove a person.
6. A reports queue with dismiss, remove card and ban.
7. A live metrics page: joins, card views, taps, matches, glows started, we met, reports.
8. A demo mode toggle per room. While it's on, admins skip the location check, so the stage phones work wherever the stage is. Every skip is logged.

**Done when.**

- [ ] A room can be created at the venue from a phone in under 2 minutes
- [ ] A printed poster's QR code opens the app
- [ ] The display QR rotates, and joins succeed with it
- [ ] Non-admins get 404 everywhere under `/admin`

**Hand off.** Step-by-step room setup notes for D5.

## B8 · Safety, moderation and cleanup

**Mission.** Build the safety net: moderation, block, report, pause, delete, and automatic cleanup.

**Read first.** In the Technical spec: Data model (blocks, reports, abuse\_signals), Core rules and numbers, API contract (safety routes). Privacy invariants P7, P8 and P9.

**You own.** FeatureSafety, `server/src/server/moderation`, `server/src/server/safety`, `server/src/server/ratelimit`, the routes `/api/blocks`, `/api/reports`, `/api/me/pause`, `DELETE /api/me`, `/api/abuse/capture` and `/api/cron/purge`, and the cron entry in `vercel.json`.

**Build.**

1. `moderateImage(kind, bytes)` with Claude (`claude-haiku-5-5`, vision), returning strict JSON: face visible, nudity, outfit present, possibly under 18. Card photos fail closed and ask for a retake. Profile photos flagged as possibly under 18 are held for human review.
2. `moderateText(body)` for chat, with a 2.5-second timeout. On timeout, the message goes through and is reviewed afterwards.
3. Block and report routes that take a card, match or chat ID and work out the person on the server. A block ends any match and glow between the two. A report also blocks.
4. Pause: hides you from every deck at once and sends `deck.changed` to the room.
5. Delete account: every row, storage object and device token, then the auth user.
6. The purge cron every 5 minutes: call `purge_expired`, delete the returned card photos, and send `checkin.expiring` to anyone whose check-in ends in the next 15 minutes.
7. `rateLimit(key, policy)`, with policies for sign-in, join, deck, taps, messages and reports, used by every route.
8. Block and report sheets in the app, plus pause and delete screens.

**Done when.**

- [ ] Moderation answers in under 2.5 seconds at p95, and the face-visible and nude fixtures are rejected
- [ ] After deleting an account, a test finds no rows or files left for that person
- [ ] Expired cards disappear within 10 minutes (P9)
- [ ] Blocking removes both people from each other's decks within 5 seconds (P7)

**Hand off.** How other agents call moderation and rate limits, with examples.

## B9 · Release and TestFlight

**Mission.** Get real builds onto real iPhones as early as possible, and keep them coming.

**Read first.** Build plan: Realistic risks. In the Technical spec: Stack, Environment and secrets.

**You own.** `ios/fastlane/`, App Store Connect setup, `.github/workflows/release-ios.yml`, and `docs/RELEASE.md`. Signing settings in `project.yml` are shared with A3, so agree changes in `docs/HANDOFFS.md`.

**Build.**

1. Bundle IDs for the app and the Live Activity extension, capabilities turned on in the developer portal, and an Apple push .p8 key created and added to the server's environment.
2. The app record in App Store Connect, App Privacy answers that match the privacy manifest, and beta test information.
3. A fastlane lane named `beta`: bump the build number, archive, and upload to TestFlight with the App Store Connect API key. CI runs it when a tag is pushed.
4. An internal testing group for you, Robin and the two stage phones.
5. As soon as sign-in and room joining work, submit a build for external beta review, and set up the public TestFlight link for the posters.
6. Associated Domains checked end to end on a real iPhone: scanning a QR code opens the app.

**Done when.**

- [ ] `fastlane beta` uploads a build that installs from TestFlight on a real iPhone
- [ ] Push works on a TestFlight build, through production
- [ ] The public TestFlight link is approved, or the review status is in `docs/HANDOFFS.md`
- [ ] `docs/RELEASE.md` explains how to ship a new build with one command

**Hand off.** The TestFlight link and the latest build number, updated after every release.
