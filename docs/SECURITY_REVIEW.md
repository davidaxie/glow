# Security and privacy review

Owner: D2 (Wave 3). Reviewed `main` at 1af3364 plus the open Wave 2 PRs, by reading the code, by attacking a live local stack (D2's own Supabase and the real route handlers), and by running a scripted two-person journey through mitmproxy. Everything here was done on localhost; nothing outside it was touched.

## Summary

| ID | Severity | Finding | Owner | Status |
| --- | --- | --- | --- | --- |
| [D2-F1](#d2-f1) | **High** | Anyone could take over an account before its owner signs up, using Supabase's password sign-up | A2 | **Fixed** (#46, merged), retested |
| [D2-F2](#d2-f2) | Medium | Supabase Auth tells anyone with the anon key whether an email has an account | Supabase, David | Open; mitigations listed |
| [D2-F3](#d2-f3) | Low | First names can hold control characters, bidi overrides, or only invisible characters | B1 | Open, fix proposed |
| [D2-F4](#d2-f4) | Low | A NUL character in any text field made the server answer 500 | A1 | **Fixed** (#49, merged), retested |
| [D2-F5](#d2-f5) | Medium | A banned person can register again under another address (A2's D56) | A2, B7, B8 | Open; smallest fix proposed (D2-D2) |
| [D2-F6](#d2-f6) | Low | `GlowDebugCheckInPhoto` is not compiled out of Release builds | B3 | Open, one-line fix |
| [D2-F7](#d2-f7) | Medium (accepted) | Fake coordinates: what the location check can't prove | B2 | Accepted; residual risk written down |
| [D2-F8](#d2-f8) | Low | Signing out may leave the phone registered for push | B5, B1 | Open (code review) |
| [D2-F9](#d2-f9) | Low | Deck PR #25: screenshots of other screens count as deck captures; a one-sided tap reaches PostHog | C1 | Open (PR not merged) |
| [D2-F10](#d2-f10) | Low | Email codes are valid for an hour | David | Open, setting listed in Needs David |
| [D2-F11](#d2-f11) | Info | Seven smaller notes | various | Listed below |

No critical finding. The one high finding is fixed and has a test that fails without the fix. Nothing in the attack list broke an invariant P1 to P12 on what is merged.

## The privacy invariants, and the test that holds each one

All of these run in `scripts/ci-local.sh` (and in CI) as `server/tests/security/`, except where noted. Tests marked "live" run against a real local Supabase (D2's own stack, or the one CI starts) and skip themselves on the shared stack, like B8's.

| | Test | What it does |
| --- | --- | --- |
| P1 | `journey.live.test.ts`, `p1-realtime.live.test.ts`, `p6-push-payloads.test.ts`, `proxy.live.test.ts` | Three people, a room, every reply kept and searched for the others' user ID, email, first name and photo path. No user ID but your own appears anywhere, even after a match (D20). Card links carry only the card ID. Every event and push is only `type` plus a match or room ID, whatever an owner passes in. |
| P2 | `p2-coordinates.live.test.ts` | Joins with digits that appear nowhere else (inside, outside, too vague). Pass and fail come back; then every log line, error report, reply and every row of every table the service role can read is searched for those digits. `location_checks` rows hold exactly seven columns. |
| P3 | `lifecycle.live.test.ts` | A photo with a visible face is refused and nothing is stored. A photo carrying GPS EXIF, a copyright tag and a colour profile is stored with none of them. A join ticket works for its own person and room only. The phone-side blur is B3's (`ImagingTests`); D2 checked it with the proxy run below. |
| P4 | `p4-storage.live.test.ts`, `journey.live.test.ts` | With the anon key, signed out, as the owner and as another person: no read, public link, signed link, listing, overwrite, delete or bucket creation, for a real card and a real profile photo. Signed card links fail for another person, with a longer or shorter expiry, with a changed signature, or with none. |
| P5 | `journey.live.test.ts`, `proxy.live.test.ts` | A one-sided tap changes nothing the tapped person's deck, room state or match list say, sends no event, and a repeat tap says the same. Measured timing before and after being tapped: no difference (below). |
| P6 | `p6-push-payloads.test.ts` | For every event in the contract: the APNs request has fixed lock screen text and only `aps`, `type` and an ID, even when the event was stuffed with a user ID and a name. |
| P7 | `journey.live.test.ts`, `chat.live.test.ts` | A block removes both people from each other's deck, makes taps and card links 404, and ends the match and its thread, all well inside 5 seconds. A block racing 12 sends leaves nothing behind. |
| P8 | `lifecycle.live.test.ts` | Pausing and leaving each remove a card from the next deck fetch; the leaver's photo is deleted, not just hidden; resuming brings back only the paused person. |
| P9 | `lifecycle.live.test.ts` | One purge run deletes an expired check-in and its photo and keeps a live one. The purge route answers 401 to no secret, a wrong secret, a user's token, a Basic scheme and a near-miss secret. |
| P10 | `lifecycle.live.test.ts`, `onboarding.live.test.ts` | Under 18 (17 years 364 days, tomorrow's 18th birthday, today) is refused by the route and by the database trigger, and is never stored. Completing needs an adult profile and an approved photo; a held (possibly minor) photo counts for nothing. |
| P11 | `journey.live.test.ts`, `chat.live.test.ts`, `admin.live.test.ts`, `fuzz.live.test.ts` | Someone else's match, a made-up match, a room you never joined, and every admin operation as a non-admin give the same 404 body. No test ever saw a 403. Every non-admin operation (31) gets hostile input (NUL, control characters, SQL and HTML text, 200 KB strings, prototype keys, bad IDs) and never answers 5xx or 403. |
| P12 | **Blocked on C1's PR #25** | The deck's blur while recorded is app code that isn't on `main` yet. Review notes are in D2-F9. A Simulator test with a faked capture belongs in C1's PR and D1's journeys. |

Other tests: `no-passwords.live.test.ts` (D2-F1), `nul-bytes.test.ts` (D2-F4), `release-surface.test.ts` (no test sign-in or `GlowDebug*` hook outside `#if DEBUG`, no secret key in `ios/` or the admin bundle, no analytics key that is a name, coordinate, ID or text), `hosted-env.test.ts` (a Vercel deploy can't turn on test sign-in or run without a real Anthropic key, Upstash or cron secret), `caps-race.live.test.ts`, `ban.live.test.ts`, and the pgTAP file `supabase/tests/database/100_d2_no_passwords.test.sql`. `proxy.live.test.ts` is opt-in (`D2_PROXY=1`, needs mitmproxy).

## The attack list

| Attack | Result |
| --- | --- |
| Guess or reuse card image links | Safe. The link signs `cardId.viewerId.exp` with the viewer taken from the token, so another person's token fails; a changed `exp` or signature, or none, fails; the expiry can't exceed 60 s ahead; the card is checked again on every fetch. 404 for every failure. |
| Find a user ID or name in a response before a match | None found, before or after (the proxy run searched 8 checks over every request, response and Realtime frame). |
| Join another person's Realtime channel | Safe. A signed-in attacker can't join `user:{victim}` (also not upper-cased), a room channel needs an open check-in, public joins receive nothing, and nobody can send. See the Realtime note under D2-F11. |
| Read storage with the anon key | Safe (P4 above). |
| Send fake coordinates | Works as designed; the remaining risk is [D2-F7](#d2-f7). |
| Parallel requests to pass the tap and view caps | Safe. 9 simultaneous taps give exactly 3 successes and 6 conflicts; 14 simultaneous deck page requests over 56 cards never show more than 50 different ones. |
| Timing differences that reveal a one-sided tap | None. Median deck / room-state / match-list times for the tapped person, 25 requests each before and after three people tapped them: 3.6 / 3.3 / 2.7 ms before, 3.6 / 3.1 / 2.9 ms after (p90 within 1.2 ms). Taps are also not in any count or event. |
| Find out whether an email has an account | **Found:** [D2-F2](#d2-f2). The Glow API has no such path. |
| Inject text through names and messages | Safe against injection (messages and names are stored and returned as JSON data, shown verbatim by the app; React escapes the admin web; forged log lines in a message are inert). Two input problems: [D2-F3](#d2-f3) and [D2-F4](#d2-f4). |
| Find the test sign-in in a Release build | Not found. Every use of `signInForTesting`, `/api/dev/test-login` and `GlowDebug*` is inside `#if DEBUG`, except F6. On the server it is a 404 unless it's on locally, and it signs in `@glow.test` addresses only (a real address, a look-alike domain and a newline trick all fail). Hosted deploys refuse to start with it on. |
| Find the service role key in the app or admin bundle | Not found. Nothing in `ios/` holds a `sb_secret_` key or a service_role JWT; no admin client component imports a server module or the env; the built browser chunks (`.next/static`) hold no secret value and no secret's name. |
| Coordinates or message bodies in logs, Sentry or PostHog | None. Logs searched for coordinate digits and message text. Sentry is scrubbed and off without a DSN. App analytics: no event has a key that is a name, coordinate, ID or text; one concern in D2-F9. |
| Admin routes as a non-admin (B7's ask) | Safe. All 17 admin operations give the same 404 to a signed-in non-admin, whatever the body or query, and 401 when signed out. |
| C4's chat attack list | Safe. Another pair's match, a flagged body in a foreign chat (404 before moderation, no timing signal), clientId replay across matches and across people, cursor junk, a block racing sends, unmatch against block (the same events), message text in logs and events. |
| Proxy run | Clean. See below. |

## Proxy run

mitmproxy 12 in reverse-proxy mode on `127.0.0.1`, over plain HTTP: one proxy in front of D2's own API, one in front of D2's own Supabase (Auth and the Realtime WebSocket). No certificate was installed anywhere, and the Mac's network settings were not touched. A scripted two-person journey ran through both: sign-in, Realtime subscribe, resolve, join, check-in with a real outfit photo, deck, card images, tap, mutual tap, match, match photo, Just chat, a message, unmatch.

`server/tests/security/proxy.live.test.ts` (opt-in, `D2_PROXY=1`) then scanned every exchange. Result: all 8 checks pass.

- No user ID but your own in any request, response or Realtime frame, before or after the match.
- No other person's first name, email or photo path until the match, and then only in `/api/matches/*` replies.
- The join request's coordinates appear nowhere else, in a request or reply (Realtime included).
- Photos came only as no-store JPEGs through `/api/cards/.../image?exp&sig` and `/api/matches/.../photos/n`. Nothing touched Supabase Storage.
- No cookies, no CORS header on the API, `Cache-Control: no-store` on every API reply, no stack trace, no 403, no 5xx.
- Supabase saw only `/auth/v1/*` and `/realtime/v1/*`.

**The Simulator run is not done.** All three Simulator slots on this Mac were held by another project, and the app can't sign in against the server until B1's session code is merged (only its server, #50, is). The same scan runs on the app with Glow A as person A once both are true; the commands are in the test's header. Until then, P3's phone side (blur before upload) rests on B3's `ImagingTests` and B3's review.

<a id="d2-f1"></a>

## D2-F1 · High · Pre-account takeover through password sign-up

**Status:** fixed in #46 (`0005_d2_no_passwords.sql`), retested.

**What.** Glow signs in with Apple or a 6-digit email code. Supabase Auth also accepts email and password from anyone with the public anon key, and it puts a sign-up and a later email-code sign-in for the same address into the same auth user.

**Repro** (D2's own stack, or `server/tests/security/no-passwords.live.test.ts` with the trigger disabled, which fails 5 of 7):

1. The attacker sends `POST /auth/v1/signup` with `{ "email": "<victim's address>", "password": "<theirs>" }` and the anon key.
2. The victim later signs in with an email code, which works and confirms the address.
3. `POST /auth/v1/token?grant_type=password` with the attacker's password returns a session for the victim's account. From there the attacker can read the victim's matches (first names and profile photos) and chat. This works with "Confirm email" on or off.

The same gap lets anyone holding a signed-in phone for a moment set a password (`PUT /auth/v1/user`, or the recovery flow) and keep access from anywhere.

**Fix.** Supabase has no setting that turns off passwords but keeps email codes, and it gives every new user a random password, so refusing passwords on `auth.users` would break every sign-up (D2 tried it; that version failed). Instead, a trigger on `auth.mfa_amr_claims` refuses any session made with a password. Supabase writes that row in the same transaction that issues the tokens.

- Email codes, magic links, Apple, recovery links and refresh tokens are unchanged.
- "Confirm email" must stay on, and is now on in local `config.toml` too.
- Local stacks only: `@glow.test` people can still sign in with a password when `private.settings.allow_test_passwords = 'on'`. Only `seed.sql` sets it.
- Password sessions that existed before the migration are deleted (D2-D1).

**Tests.** `supabase/tests/database/100_d2_no_passwords.test.sql` covers the setting off (cloud) and on (local). `server/tests/security/no-passwords.live.test.ts` runs through the real Auth API: email-code sign-up works; the pre-registration attack fails before and after the victim arrives; a password set through `PUT /auth/v1/user`, the recovery flow or the admin API never signs in; the `@glow.test` path dev-token and CI smoke use still works; B1's test sign-in flow still works.

**Cloud settings.** D2 found no hosted toggle that rejects password sign-up on its own. Under Providers → Email there's only the provider on/off, Confirm email, Secure email change, Secure password change, the password rules and OTP length and expiry. A Password Verification Attempt Auth Hook could reject every password, but as far as D2 knows it's limited to some plans; the migration works on any plan. Recommended settings are in `docs/HANDOFFS.md` (Needs David, item 20).

<a id="d2-f2"></a>

## D2-F2 · Medium · Email enumeration through Supabase Auth

**Status:** open. No fix inside Glow's code: it's how Supabase Auth answers. Mitigations below.

**What.** Anyone with the public anon key can ask Supabase whether an address has a Glow account:

| Request | Account exists | No account |
| --- | --- | --- |
| `POST /auth/v1/otp` `{ "email", "create_user": false }` | 200 | 422 `otp_disabled` |
| `POST /auth/v1/signup` `{ "email", "password" }` | 422 `user_already_exists` | creates an unconfirmed user and emails the address |

For a dating app, "is this person on Glow" is itself sensitive. The brief asked about "through sign-in": Glow's own API has no sign-in route, so this is Supabase's. Password login (`invalid_credentials`) and recovery do not distinguish.

Sign-up with an unknown address also sends that address a "Confirm your email" message each time, and leaves a junk unconfirmed account: harassment by email and database clutter, limited only by Auth's rate limits.

**Why it can't be closed in the database or the app.** The answers come from Auth before any hook runs. Disabling sign-up for everyone would stop the email code creating new people too.

**Mitigations** (all in Supabase's dashboard, for David):

- Turn on CAPTCHA protection for Auth (Turnstile or hCaptcha). It makes bulk checks and bulk email expensive. The app would then need to send the captcha token (a B1 change).
- Keep Auth's per-IP rate limits at their defaults or lower, and use a real SMTP provider with its own sending limits (already in Needs David).
- Accept the residual risk for the beta, and say so in the privacy policy draft.

**Alternative, if this matters more later:** put sign-in behind the Glow API (`POST /api/auth/code`, uniform answer), and close the public `/otp` and `/signup` endpoints with `enable_signup = false` plus API-created users. That is a contract change and a rewrite of Session; D2 does not recommend it for the beta.

<a id="d2-f3"></a>

## D2-F3 · Low · First names accept control, bidi and invisible characters

**Status:** open. Owner B1 (`server/src/server/profiles/profile.ts`).

**Repro** (live, against `PUT /api/me/profile`): `"firstName": "​​"` (200, an invisible name), `"Dee‮eed"` (200, text that renders reversed), `"Dee\nSmith"` (200), `"\u0007bell"` (200). `"   "` is a 400, and `<b>Dee</b>` is stored as plain text (SwiftUI and React both escape it).

**Impact.** A matched person sees the name. A blank name or one that renders backwards is spoofing, not injection.

**Fix.** Normalize to NFC, reject `\p{Cc}`, `\p{Cf}`, `\p{Zl}` and `\p{Zp}`, require at least one `\p{L}`, and count length in graphemes.

<a id="d2-f4"></a>

## D2-F4 · Low · A NUL character made the server answer 500

**Status:** fixed in #49, retested.

**What.** `{"body":"a\u0000b"}` on `POST /api/matches/{id}/messages`, and the same in a report's details, reached Postgres, which can't store a NUL, and came back as an unhandled 500 and an error report. No data leaked, but anyone signed in could make the server report errors at will.

**Fix.** The route helper refuses a NUL in any body key or value and any query value with a 400, before a handler runs. `tests/security/nul-bytes.test.ts` (unit) and the live chat and fuzz tests cover it.

<a id="d2-f5"></a>

## D2-F5 · Medium · A banned person can register again (A2's D56)

**Status:** assessed; the smallest fix is written up as D2-D2 in `docs/DECISIONS.md` and needs David's privacy call before anyone builds it.

**What D56 said:** a banned person can delete their account, which clears the ban, and come back.

**What D2 found:** that exact path is closed.

- `banPerson` sets `profiles.banned_at` and bans the auth user. A banned auth user's token stops verifying, so `DELETE /api/me` (and every other route) answers 401. Supabase has no self-delete endpoint.
- Fresh sign-in, a magic link and a refresh token for a banned user fail too.
- `ban.live.test.ts` proves it on a live stack: after a ban every route answers 401, no new token can be made, the match ended and the person left every deck.
- One edge: `banPerson` sets the profile first and bans the auth user second. If the second step fails, the admin sees an error, and until the ban is retried (it is safe to retry) the person could still delete their account and clear the ban. Low.

**What is open:** the person registers again with another email address or Apple ID and is a new, unbanned account. No server-side data links the two. This is true of any app that signs in with an email or an Apple ID.

**Smallest fix** (D2-D2): when someone is banned, keep one keyed hash of their email and of their Apple ID (`auth.identities.provider_id`) in a new `private.banned_identities` table that survives account deletion; a trigger on `auth.users` and `auth.identities` refuses a sign-up whose hash matches. It needs no profile data, but it is data about a person who deleted their account, so it needs a line in the privacy policy and David's yes. It stops the same address and the same Apple ID. It does not stop a new address or a new Apple ID. The stronger fix is Apple's App Attest or DeviceCheck, tying a ban to the device.

<a id="d2-f6"></a>

## D2-F6 · Low · Check-in test-photo hook is in Release builds

**Status:** open. Owner B3 (`FeatureCheckIn/CaptureStep.swift`, line 54).

The `GlowDebugCheckInPhoto` user default shows a "Use test photo" button that reads any file path. The photo still goes through the blur pipeline, and a Release build only sees it if a user default is set on the device, so the impact is small, but it is the only debug hook outside `#if DEBUG` (`release-surface.test.ts` allow-lists it under `KNOWN`; delete the entry when this is fixed). **Fix:** wrap lines 52 to 61 in `#if DEBUG`.

<a id="d2-f7"></a>

## D2-F7 · Medium (accepted) · What the location check can't prove

Coordinates come from the phone and the server only checks the distance. What is left:

1. **A spoofed GPS** (a developer-mode location, a jailbreak, or a script calling the API with made-up numbers) passes from anywhere. Nothing server-side can tell a real fix from a chosen one. `accuracy` is also client-supplied; it only helps by up to 100 m (GEO_ACCURACY_CREDIT).
2. **A leaked QR.** The rotating token (30 s, two windows) only gets someone to the location check. A printed poster's static token lasts until an admin makes a new one, and a photo of it works from anywhere. Together with 1, that is a way into a room without being there.
3. **What it buys an attacker.** A card in the deck, taps (3 a day a room), and a match, which reveals a first name and photos. It does not reveal anyone's location, and the admin can remove anyone (cards, bans, "End room").
4. **Checks already in place:** accuracy over 500 m is refused, the join ticket lasts 10 minutes and is bound to the person and the room, Find repeats the check (2 minutes), joins and Find checks are rate limited, and admins can switch off posters and see check-in counts.

Residual risk is accepted for the beta because the room is small and watched. If it matters later: shorter-lived poster tokens, a Bluetooth or Ultra Wideband nearby check (Wave 4, E1 and E2) and App Attest.

<a id="d2-f8"></a>

## D2-F8 · Low · Signing out may leave the phone registered for push

Found by reading B5's `LivePushService` (not reproduced on a device). `unregister()` works only when the in-memory registration exists. It isn't saved, so after a relaunch it is empty until the token uploads again; a failed `DELETE` (offline) is not retried; and `sessionChanged(.signedOut)` clears the registration. If Session doesn't await `unregister()` before it clears the tokens, the server keeps the device row, and the signed-out phone keeps showing "Someone you noticed noticed you back" for the old account. **Fix:** keep the device ID in the Keychain, and have B1's Session await `push.unregister()` before it signs out, retrying a pending delete on the next launch.

<a id="d2-f9"></a>

## D2-F9 · Low · Two things in the deck PR (#25, not merged)

1. `DeckPrivacy` listens for screenshots for as long as the deck screen exists, including while the mutual takeover or the report screen is on top. A screenshot of those screens would be logged to `/api/abuse/capture` as a deck screenshot, a false signal against the person and a log of a screenshot of a match screen. **Fix:** only report while the deck is on screen and the scene is active.
2. `deck_tap` sends `result: "sent" | "mutual"` and a duration to PostHog. It's anonymous, but it records on the device that a one-sided tap happened, which is what migration 0002 took out of room metrics for the same reason (P5's spirit). **Fix:** drop `result` from `deck_tap` (the takeover has its own event).

The rest of #25 looked right: it hides the deck for any capture, mirror or AirPlay, hides the app-switcher snapshot, sends only `{kind, roomId}`, and keeps cards in memory over an ephemeral session. P12's UI test is still to come.

<a id="d2-f10"></a>

## D2-F10 · Low · Email codes are valid for an hour

`config.toml` has `otp_expiry = 3600` (Supabase's default; the cloud project has its own setting). With the per-IP verification limits, guessing a 6-digit code across many addresses gets an hour per code. **Fix:** 600 seconds in the cloud settings (Needs David, item 20), and change "expires in an hour" in B1's email templates.

<a id="d2-f11"></a>

## D2-F11 · Info · Smaller notes

- **Realtime outlives a check-in.** Supabase checks the private-channel policy when a channel is joined, so someone who joined `room:{id}` keeps receiving `deck.changed` until the app leaves or the token refreshes. The payload is only `{type, roomId}`.
- **APNs tokens move.** Registering a token that another account holds moves it to the caller (by contract). It needs the token, which the API never returns.
- **Profile photos aren't re-encoded** (B1's `stripJpegMetadata` drops metadata segments, but keeps the JFIF header, which can hold a thumbnail). Match viewers get a sharp re-encode (B3), so only the owner sees the raw bytes. Re-encode with sharp, as B3's card upload does.
- **The rate limiter fails open** if Upstash is down (B8-D3). For `signIn`, `checkin` (it spends Claude calls) and `messages`, failing closed is worth considering.
- **`lastMessageAt` counts flagged messages** (`match_json` in 0001), so the recipient's match list moves for a message B8 hid. Filter with `moderation <> 'flagged' or sender_id = viewer`.
- **`location_fresh` accepts any purpose, and a later `fail` doesn't cancel an earlier `pass`** within 2 minutes (`0001`). Make it use the latest check for the person and room.
- **Unmatch can be told from a block** by the other person if both stay in the room: after an unmatch the pair is eligible again (D16), after a block never. The events are identical (`chat.live.test.ts`). The spec says "looks exactly like a block"; it could say "sends the same events".

## What was not covered

- **P12** and the phone side of **P3** (needs the Simulator or a device; see Proxy run).
- B1's iOS code (Session, email sign-in screens): not merged, so client-side enumeration and Release behaviour at runtime were not reviewed. Server side of B1 is covered above.
- Real Claude moderation (no API key): the tests use B8's local stand-in, which approves anything without a marker. Hosted deploys refuse to start without a key (`hosted-env.test.ts`).
- Upstash, APNs and the hosted Supabase: none exists yet. The cloud settings that matter are in Needs David, item 20.

## Retest

After the two fixes merged (#46, #49) the full `server/tests/security/` suite, B4's and B8's integration tests, the pgTAP suite (465 tests) and `scripts/ci-local.sh D2` pass on D2's stack. With each fix reverted, its tests fail (D2-F1: 5 of 7 live tests; D2-F4: the NUL tests).
