# Contracts

Owner: A2. What every agent codes against: the API (`contracts/openapi.yaml`), realtime and push events (`contracts/events.json`), shared numbers (`contracts/constants.json`), and the database functions in `supabase/migrations/`. The tables marked GENERATED are written by `scripts/codegen.sh`; don't edit them by hand. After Checkpoint 1, contract changes go through A1 in a PR labeled `contract-change` (see AGENTS.md).

## Using the generated code

| Where | What | How |
| --- | --- | --- |
| Server | `server/src/contracts` | `import { zDeck, type Deck, TAPS_PER_ROOM_PER_DAY, eventCatalog, apnsRequestFor, userTopic } from '@/contracts'`. Route files use `route(operationId, handler)` from A1's `@/server/http`, which reads `operations` from here. |
| Server, database | `server/src/contracts/database.ts` | `createClient<Database>(url, serviceKey)` types every table and `rpc()` call. |
| App | `APIClient/Generated` | `Client(serverURL:configuration:transport:)` from swift-openapi-generator, `Components.Schemas.*`, `GlowConstants`, `GlowEvents`. A3's wrapper adds the token, retries and the not-found error. |
| Database | `private.constants` | `private.const('TAPS_PER_ROOM_PER_DAY')`. `supabase/tests/database/000_constants.test.sql` fails if it drifts from `constants.json`. |

Run `pnpm codegen` after any change in `contracts/` or `supabase/migrations/`, and commit what it writes. CI runs it and fails on any difference.

## Conventions

- **Sign-in.** `Authorization: Bearer <Supabase access token>` on every call except test sign-in, the link file, `/r/{slug}` (no sign-in) and the purge cron (`Bearer $CRON_SECRET`).
- **Not allowed is 404 (P11).** Nothing ever answers 403. A malformed path ID is 404 too.
- **No one else's identity before a match (P1).** No app-facing response has a user ID, email or location field, and every object in one is closed (`additionalProperties: false`). `codegen.sh` refuses the contract otherwise. Cards are named by card ID (the check-in ID), matched people by match ID. Messages say `fromMe`, never a sender.
- **Errors.** `{ "error": { "code", "message", "reason"?, "issues"? } }`. `code` is one of `ErrorCode` in openapi.yaml; apps pick their own words per code.
- **Times.** RFC 3339 UTC with milliseconds: `2026-10-24T20:15:00.000Z`. The zod schemas reject offsets like `+00:00`, so format database times with `new Date(value).toISOString()`. The database functions already return this format.
- **Absent, not null.** Optional fields are left out rather than sent as `null`. The database functions strip null fields, so their output can go straight into a reply.
- **IDs** are UUIDs. Realtime topics use the lowercase form: `GlowEvents.userTopic(id)` and `userTopic(id)` do it for you.
- **Photos** upload as base64 JPEG inside JSON (`NewProfilePhoto`, `CheckinRequest`), at most `PHOTO_MAX_BYTES` before encoding. The route allows 4.2 MB bodies, under Vercel's 4.5 MB limit.
- **Card image links** are `/api/cards/{cardId}/image?exp={unix seconds}&sig={base64url HMAC-SHA256(CARD_URL_SECRET, "{cardId}.{viewerId}.{exp}")}`, at most `CARD_URL_TTL` long. The viewer comes from the bearer token, so the link carries no user ID and is useless to anyone else.
- **Storage.** Private buckets `profile-photos` (`{userId}/{photoId}.jpg`) and `room-cards` (`{roomId}/{cardId}.jpg`), with no policies: only the service role reads them, and only the image routes serve them.
- **Days** for the tap and view caps and the deck shuffle are the room's calendar day in `rooms.timezone`.

## Endpoints

Full request and response shapes are in `contracts/openapi.yaml`.

<!-- BEGIN GENERATED: endpoints -->
| Endpoint | operationId | Owner | Sign-in | Does |
| --- | --- | --- | --- | --- |
| `GET /api/me` | `getMe` | B1 | person | My profile, photos and onboarding step |
| `DELETE /api/me` | `deleteAccount` | B8 | person | Delete my account and all my data |
| `PUT /api/me/profile` | `updateProfile` | B1 | person | Save first name, birthday, gender and who I want to see |
| `POST /api/me/photos` | `addProfilePhoto` | B1 | person | Add a profile photo (moderated) |
| `GET /api/me/photos/{id}` | `getMyPhoto` | B1 | person | One of my own profile photos |
| `DELETE /api/me/photos/{id}` | `deleteProfilePhoto` | B1 | person | Remove one of my profile photos |
| `POST /api/me/pause` | `setPaused` | B8 | person | Pause or resume being visible |
| `POST /api/me/onboarding/complete` | `completeOnboarding` | B1 | person | Finish onboarding |
| `POST /api/dev/test-login` | `testLogin` | B1 | none | Debug-only sign-in for Simulator tests |
| `POST /api/devices` | `registerDevice` | B5 | person | Register a push token |
| `DELETE /api/devices/{id}` | `deleteDevice` | B5 | person | Remove a push token |
| `POST /api/rooms/resolve` | `resolveRoom` | B2 | person | Turn a room code, or a slug plus QR token, into a room |
| `GET /api/rooms/{id}` | `getRoomState` | B2 | person | The room, my check-in there, and what I have left today |
| `POST /api/rooms/{id}/join` | `joinRoom` | B2 | person | QR token or code plus one location fix returns a join ticket |
| `POST /api/rooms/{id}/leave` | `leaveRoom` | B2 | person | End my check-in now and delete my card |
| `POST /api/rooms/{id}/checkin` | `createCheckin` | B3 | person | Join ticket plus blurred photo plus tags creates my card |
| `GET /api/cards/{cardId}/image` | `getCardImage` | B3 | person | A watermarked card photo, through a signed 60-second link |
| `POST /api/rooms/{id}/deck` | `getDeck` | B4 | person | Filters return up to DECK_PAGE_SIZE cards with signed image links |
| `POST /api/rooms/{id}/taps` | `createTap` | B4 | person | Secret tap. Returns sent or mutual and taps left today |
| `GET /api/matches` | `listMatches` | B4 | person | My active and past matches |
| `GET /api/matches/{id}` | `getMatch` | C2 | person | One match, with the other person's first name and photo count |
| `GET /api/matches/{id}/photos/{n}` | `getMatchPhoto` | B3 | person | The other person's profile photo, for active matches only |
| `POST /api/matches/{id}/choice` | `setChoice` | C2 | person | Find (with a fresh location fix) or Chat |
| `POST /api/matches/{id}/unmatch` | `unmatch` | C4 | person | End the match for both people |
| `GET /api/matches/{id}/glow` | `getGlow` | C3 | person | The match's glow session |
| `POST /api/matches/{id}/glow/met` | `markGlowMet` | C3 | person | I tapped We met |
| `POST /api/matches/{id}/glow/cancel` | `cancelGlow` | C3 | person | Cancel the glow, or switch to chat |
| `GET /api/matches/{id}/messages` | `listMessages` | C4 | person | Read chat messages |
| `POST /api/matches/{id}/messages` | `sendMessage` | C4 | person | Send a chat message |
| `POST /api/blocks` | `createBlock` | B8 | person | Block someone from a card, match or chat ID |
| `POST /api/reports` | `createReport` | B8 | person | Report someone (this also blocks them) |
| `POST /api/abuse/capture` | `logCapture` | B8 | person | Log a screenshot or screen recording of the deck |
| `GET /api/cron/purge` | `runPurge` | B8 | cron secret | Expiry cleanup, protected by the cron secret |
| `GET /api/admin/rooms` | `adminListRooms` | B7 | person | All rooms |
| `POST /api/admin/rooms` | `adminCreateRoom` | B7 | person | Create a room |
| `GET /api/admin/rooms/{id}` | `adminGetRoom` | B7 | person | One room, with its meeting spots |
| `PATCH /api/admin/rooms/{id}` | `adminUpdateRoom` | B7 | person | Change a room (name, center, radius, times, status, demo mode, static QR) |
| `PUT /api/admin/rooms/{id}/spots` | `adminReplaceSpots` | B7 | person | Replace the room's meeting spots (MEETING_SPOTS_MIN to MEETING_SPOTS_MAX) |
| `GET /api/admin/rooms/{id}/poster` | `adminRoomPoster` | B7 | person | Printable poster with the static QR code, room code and three steps |
| `GET /api/admin/rooms/{id}/display-token` | `adminDisplayToken` | B7 | person | The current rotating QR token, for the display page |
| `POST /api/admin/rooms/{id}/static-token` | `adminRotateStaticToken` | B7 | person | Replace the poster token (old posters stop working) |
| `GET /api/admin/rooms/{id}/metrics` | `adminRoomMetrics` | B7 | person | Live counts for the room (from room_activity, no user IDs) |
| `GET /api/admin/rooms/{id}/cards` | `adminListCards` | B7 | person | Cards in the room right now, for moderation |
| `GET /api/admin/cards/{cardId}/image` | `adminCardImage` | B7 | person | A card photo for review, watermarked with the admin's code |
| `POST /api/admin/cards/{cardId}/remove` | `adminRemoveCard` | B7 | person | Remove a card, or remove the person from the room |
| `GET /api/admin/reports` | `adminListReports` | B7 | person | The reports queue |
| `POST /api/admin/reports/{id}/resolve` | `adminResolveReport` | B7 | person | Dismiss a report, remove the card, or ban the person |
| `GET /api/admin/photos` | `adminListPhotos` | B7 | person | Profile photos waiting for review |
| `GET /api/admin/photos/{id}/image` | `adminPhotoImage` | B7 | person | A profile photo for review, watermarked with the admin's code |
| `POST /api/admin/photos/{id}/review` | `adminReviewPhoto` | B7 | person | Approve or reject a held profile photo, or ban its owner |
| `GET /.well-known/apple-app-site-association` | `getAppSiteAssociation` | B2 | none | The file that lets QR links open the app |
| `GET /r/{slug}` | `getRoomWebPage` | B2 | none | Web page for people who don't have Glow yet, with the TestFlight link |
<!-- END GENERATED: endpoints -->

## Events

Every event goes over Realtime as a broadcast on a private channel (event name = the type, payload = the event object), and as an Apple push when it has lock screen text. Payloads are only `{ type, matchId }` or `{ type, roomId }`. The app refetches details from the API. Apps can't send on any channel, and presence is never allowed.

- `user:{userId}`: only that person may join (lowercase UUID).
- `room:{roomId}`: only people with an open check-in in that room may join.

<!-- BEGIN GENERATED: events -->
| Event | Channel | To | Lock screen text | Sent when |
| --- | --- | --- | --- | --- |
| `match.created` | `user:{userId}` | both people | Someone you noticed noticed you back. | The second tap lands and a mutual match exists. |
| `match.choice` | `user:{userId}` | the other person, or both when choosing ends | No push | The other person chose Find or Chat, or the match's choosing ended (both chose, the glow couldn't start, or the window ran out). Refetch the match. |
| `match.recheck` | `user:{userId}` | the person whose location check is stale (set_choice's recheckUserIds, start_glow's staleUserIds) | Open Glow to find each other. (time sensitive) | You chose Find and the other person did too, but your location check is older than GEO_FRESHNESS_FOR_GLOW. The app (or a tap on the push, which opens the match) sends Find again with a fresh fix. |
| `match.ended` | `user:{userId}` | both people | No push | The match ended for both people (unmatch, block or account deletion). Close the match and its chat. |
| `glow.started` | `user:{userId}` | both people | Time to find each other. (time sensitive) | Both chose Find and the glow started. |
| `glow.ended` | `user:{userId}` | both people | No push | The glow ended: both tapped We met, someone canceled, or time ran out (from purge, or from whichever route reported it in settled). |
| `message.created` | `user:{userId}` | the recipient | New message | A new chat message arrived. |
| `checkin.expiring` | `user:{userId}` | that person | Your check-in ends soon. | This person's check-in ends in CHECKIN_EXPIRY_WARNING or less. |
| `deck.changed` | `room:{roomId}` | everyone checked into that room | No push | Someone in the room paused, left or blocked. Refetch the deck. |
<!-- END GENERATED: events -->

APNs payload: `{ "aps": { "alert": { "body" }, "sound", "category", "thread-id", "interruption-level" }, "type", "matchId" | "roomId" }`, with `apns-collapse-id` from the catalog. `apnsRequestFor(event)` in `server/src/contracts/events.ts` builds exactly this. The alert body is fixed text and never contains a name (P6).

## Database functions

All are `security definer` with `search_path = ''`, executable only by the service role, and called with named `p_` arguments: `supabase.rpc('record_tap', { p_viewer_id, p_room_id, p_checkin_id })`. JSON in and out uses the API's camelCase names. Results that include `userIds`, `recipientId`, `recheckUserIds`, `staleUserIds` or `settled` are for the server's `notify()`, and must never be sent to an app. The route helper drops them anyway, because the contract doesn't have them. Migrations: `0001_a2_init.sql`, then `0002_a2_checkpoint1.sql` (Checkpoint 1 fixes).

| Function | Does | Returns | Raises |
| --- | --- | --- | --- |
| `create_checkin(p_user_id, p_room_id, p_checkin_id, p_card_path, p_tags)` | Ends any older check-in for this person in this room and starts a new one, lasting `CHECKIN_TTL` or until the room ends. Needs a passed (or demo-skipped) `location_checks` row with purpose `join` for this person and room from the last `JOIN_TICKET_TTL`, so a QR code alone never makes a card. Generate the card ID, upload to `room-cards/{roomId}/{cardId}.jpg`, then call this. A retry with the same card ID returns the same check-in. | `{ checkin, replacedCardPaths }` (delete those photos) | `invalid_input`, `not_found`, `room_not_live`, `onboarding_incomplete`, `location_required` |
| `get_deck(p_viewer_id, p_room_id, p_filters, p_limit, p_offset)` | Every deck rule, the filters, the daily view cap and the stable daily shuffle, in one place. Records the views it hands out. After purge deletes an expired check-in, the same day still answers `emptyReason: checkin_ended`. | `{ cards: [{ id, cardPath, tags, tappedByMe }], viewsLeftToday, hasMore, nextOffset?, emptyReason? }` | `not_found` (unknown room, or no check-in there and none today), `invalid_input` |
| `card_visible_to(p_viewer_id, p_checkin_id)` | For the image route: the card is in the viewer's deck now and the deck has shown it, or it's the viewer's own. | boolean | none |
| `record_tap(p_viewer_id, p_room_id, p_checkin_id)` | Checks the card is in the deck and the daily cap, saves the tap, and makes the match in the same transaction if they tapped back. An advisory lock on the pair makes simultaneous taps produce exactly one match. Tapping the same card again is free. A re-tap after an unmatch is a new tap. Today's taps are counted in `room_days`, apart from the tap row, so `tapsLeftToday` is exact. | `{ result: sent \| mutual, tapsLeftToday, matchId? }` | `not_found`, `tap_limit_reached`, `invalid_input` |
| `set_choice(p_user_id, p_match_id, p_choice)` | Saves Find or Chat. Find needs a passed `location_checks` row from the last `GEO_FRESHNESS_FOR_GLOW` (write it first). With `next: waiting` and `reason: other_location_stale`, send `match.recheck` to each ID in `recheckUserIds`. | `{ next: waiting \| glow \| chat, reason, match, settled, recheckUserIds? }` | `not_found`, `location_required` |
| `start_glow(p_match_id, p_code_words)` | Call it when `set_choice` says `glow`. Picks a free color, a code word from `p_code_words` and the least-used meeting spot, unique among active glows in the room, and starts the glow. Idempotent. If it can't start the glow, it never leaves the match stuck in choosing: see "start_glow results" below. | `{ result: started \| chat \| waiting, … }` | `not_found`, `invalid_input` |
| `glow_met(p_user_id, p_match_id)` | We met. When both have, the glow ends as met. A glow whose time ran out comes back `expired`, with the expiry in `settled`. | Glow from that person's side, plus `settled` | `not_found` |
| `cancel_glow(p_user_id, p_match_id)` | Cancel or switch to chat. | Glow | `not_found` |
| `get_match(p_user_id, p_match_id)` | One match, after applying timeouts. | MatchDetail plus `userIds` and `settled` | `not_found` |
| `list_matches(p_user_id)` | My matches that haven't ended, newest first, after applying timeouts. | `{ matches, settled }` | none |
| `match_photo_path(p_viewer_id, p_match_id, p_n)` | The other person's nth approved profile photo, for a match that hasn't ended. | object name in `profile-photos` | `not_found` |
| `get_room_state(p_user_id, p_room_id)` | The room, my open check-in, and taps and views left today. | `{ room, checkin?, tapsLeftToday, viewsLeftToday }` | `not_found` |
| `complete_onboarding(p_user_id)` | Finishes onboarding once the profile is filled in and at least `PROFILE_PHOTOS_MIN` photos are approved. Notifications are optional; held photos don't count (P10). Idempotent. | `{ onboardingStep: "complete" }` | `not_found` (no profile, or banned), `onboarding_incomplete` |
| `unmatch(p_user_id, p_match_id)` | Ends the match for both and deletes the thread. | `{ matchId, roomId, userIds }` | `not_found` |
| `block_user(p_user_id, p_context, p_context_id)` | Blocks the person behind a card (one the deck showed you), match or chat ID, and ends any match between them. | `{ endedMatchIds, roomIds }` | `not_found`, `invalid_input` |
| `create_report(p_reporter_id, p_context, p_context_id, p_reason, p_details)` | Reports and blocks. Match and chat reports keep the reported person's last `REPORT_EVIDENCE_MESSAGES` messages as evidence. | `{ reportId, endedMatchIds, roomIds }` | `not_found`, `invalid_input` |
| `send_message(p_sender_id, p_match_id, p_body, p_client_id)` | Adds a message once choosing is over. A retry with the same client ID returns the first message. | `{ id, matchId, body, moderation, createdAt, clientId?, recipientId }` | `not_found`, `chat_not_open`, `invalid_input` |
| `purge_expired()` | The cron job: expires glows and choice windows, flags check-ins ending soon (once each), and deletes expired check-ins, old taps, ended glows, and old card views, location checks and `room_days`. | `{ cardPaths, expiringCheckins, endedGlows, choiceTimeouts, deleted }` | none |

### start_glow results

`start_glow` no longer raises `glow_not_ready` or `no_code_word`. It answers with one of:

| `result` | `reason` | What changed | What the server does |
| --- | --- | --- | --- |
| `started` | none | The glow is on (`glow`, plus `userIds`) | Send `glow.started` to both |
| `chat` | `not_checked_in`, `no_code_word`, `already_decided` | The match is now (or already was) `chatting` | Send `match.choice` to both; the chat opens |
| `waiting` | `location_stale` | Nothing; `staleUserIds` lists whose location check is too old | Send `match.recheck` to each of them |
| `waiting` | `not_both_find` | Nothing (`set_choice` didn't say `glow`) | Nothing |

Every result also carries `settled` (below).

### Settled timeouts

Matches time out lazily: the purge cron does it every `PURGE_INTERVAL`, and these functions do it on the spot for the matches they touch. Purge skips anything already settled, so **the route that called the function must send the events** for every entry in `settled: [{ matchId, kind, userIds }]`:

| `kind` | What happened | Send to both people in `userIds` |
| --- | --- | --- |
| `choice_timeout` | The `CHOICE_WINDOW` ran out; the match is `chatting` | `match.choice` |
| `glow_expired` | A glow's `GLOW_TTL` ran out; its match is `chatting` | `glow.ended` |

| Function | Route that sends the events | Owner |
| --- | --- | --- |
| `get_match` | `getMatch` | C2 |
| `list_matches` | `listMatches` | B4 |
| `set_choice` | `setChoice` | C2 |
| `start_glow` (it can also end other pairs' glows in the room) | `setChoice`, through C3's `startGlow` | C2, C3 |
| `glow_met` | `markGlowMet` | C3 |
| `purge_expired` (`endedGlows`, `choiceTimeouts`) | `runPurge` | B8 |

**Database errors.** Expected failures are SQLSTATE `P0001` with the code as the message (`error.message` in supabase-js). Map them like this:

| Code | HTTP |
| --- | --- |
| `not_found` | 404 `not_found` |
| `invalid_input` | 400 `bad_request` (the route's zod check usually catches it first) |
| `room_not_live`, `onboarding_incomplete`, `tap_limit_reached`, `chat_not_open` | 409, same code |
| `location_required` | 422 `location_required` |
| `under_18` (from the profiles trigger) | 422 `under_18` |

**Plain tables.** For simple reads and writes, the server uses the tables directly with the service role: `profiles`, `profile_photos` (including the admin review: set `moderation_status`, or `profiles.banned_at` to ban), `devices`, `admins`, `rooms`, `meeting_spots`, `location_checks`, `abuse_signals`, `reports` (admin) and `room_activity` (metrics). Rules that need a lock or must hold everywhere go through the functions above. Only the functions write `room_days` (today's taps, and who checked in today). A trigger creates each person's `profiles` row on sign-up and refuses birthdates under `MIN_AGE`. `room_activity` never holds taps, so no metric can time a one-sided tap (P5).

**Grants for new tables and functions.** Every table, sequence and function that a migration creates in `public`, and every function in `private`, is usable by `service_role` automatically (default privileges, `0002`). Tables in `private` get `select`. `anon` and `authenticated` get nothing, ever. Turn on row level security with no policies for every new table: `010_lockdown.test.sql` fails CI otherwise. Don't add grants to clients.

## Constants

<!-- BEGIN GENERATED: constants -->
| Constant | Value | Meaning |
| --- | --- | --- |
| `CHECKIN_TTL` | 3 h | How long a check-in lasts (3 hours). Cut short if the room ends first. |
| `CHECKIN_EXPIRY_WARNING` | 15 min | checkin.expiring is sent this long before a check-in ends (15 minutes). |
| `TAP_TTL` | 24 h | How long a tap lasts (24 hours). |
| `TAPS_PER_ROOM_PER_DAY` | 3 | Taps per person per room per day, in the room's timezone. |
| `CARD_VIEWS_PER_ROOM_PER_DAY` | 50 | Different cards a person can be shown per room per day. Seeing the same card again is free. |
| `CARD_VIEW_RETENTION` | 48 h | Card view records are purged after 48 hours. |
| `DECK_PAGE_SIZE` | 10 | Cards per deck page. |
| `ROOM_RADIUS_DEFAULT` | 200 m | Default room radius. |
| `GEO_MAX_ACCURACY` | 500 m | Location fixes less accurate than this are rejected (try again). |
| `GEO_ACCURACY_CREDIT` | 100 m | Up to this much of a fix's reported accuracy is subtracted from its distance to the room's center. |
| `GEO_FRESHNESS_FOR_GLOW` | 2 min | Both people need a passed location check this recent before a glow starts (2 minutes). |
| `LOCATION_FIX_TIMEOUT` | 10 s | How long the app waits for one fresh location fix. |
| `LOCATION_CHECK_RETENTION` | 24 h | Pass or fail records of location checks are purged after 24 hours. |
| `CHOICE_WINDOW` | 10 min | Time each person has to choose Find or Chat after a match (10 minutes). |
| `GLOW_TTL` | 15 min | How long a glow lasts (15 minutes). |
| `GLOW_ENDED_RETENTION` | 10 min | Ended glow sessions are kept this long so both apps can read how they ended, then purged. |
| `QR_ROTATION` | 30 s | A screen's QR token changes every 30 seconds. |
| `QR_ACCEPTED_WINDOWS` | 2 | Rotating QR windows accepted: the current one and the previous one. |
| `QR_TOKEN_LENGTH` | 8 characters | A rotating QR token is the first 8 base32 characters of HMAC-SHA256(room secret, window). |
| `JOIN_TICKET_TTL` | 10 min | A join ticket from a passed location check lasts 10 minutes. |
| `CARD_URL_TTL` | 1 min | A signed card image link lasts 60 seconds. |
| `MESSAGE_MAX_CHARS` | 1000 characters | Longest chat message. |
| `MESSAGES_PAGE_SIZE` | 50 | Most chat messages per page. |
| `MODERATION_TIMEOUT` | 2.5 s | Moderation gives up after 2.5 seconds. Chat messages then go through and are reviewed afterwards. Card photos fail closed. |
| `PURGE_INTERVAL` | 5 min | The purge cron runs every 5 minutes. |
| `MIN_AGE` | 18 years | Nobody younger can finish onboarding. |
| `PROFILE_PHOTOS_MIN` | 1 | Fewest profile photos to finish onboarding. |
| `PROFILE_PHOTOS_MAX` | 3 | Most profile photos (positions 0 to 2). |
| `MEETING_SPOTS_MIN` | 3 | Fewest meeting spots per room. |
| `MEETING_SPOTS_MAX` | 5 | Most meeting spots per room. |
| `ROOM_CODE_LENGTH` | 6 characters | Room codes are 6 characters from ABCDEFGHJKLMNPQRSTUVWXYZ23456789. |
| `REPORT_DETAILS_MAX_CHARS` | 1000 characters | Longest free-text detail on a report. |
| `REPORT_EVIDENCE_MESSAGES` | 20 | A match or chat report keeps the reported person's last 20 messages for review. |
| `PHOTO_MAX_DIMENSION` | 1920 px | Longest side of an uploaded photo. |
| `PHOTO_JPEG_QUALITY` | 80% | JPEG quality for uploads (0.8). |
| `PHOTO_MAX_BYTES` | 3,000,000 bytes | Largest uploaded JPEG, before base64. |
| `FACE_BOX_GROWTH` | 30% | Each detected face box grows by this much on every side before blurring. |
<!-- END GENERATED: constants -->
