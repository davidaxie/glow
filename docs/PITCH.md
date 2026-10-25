# Pitch

The pitch pack for Glow at Cal Hacks: tagline, a 75-second demo script, the narrative, answers to likely judge questions, what is technically impressive, and an honest table of what is real and what is simulated. Decision: PITCH-D1 in [`DECISIONS.md`](DECISIONS.md).

**Snapshot: 2026-10-24, main `1af3364`.** Everything here comes from the repo's docs ([`SPEC.md`](SPEC.md), [`BUILD_PLAN.md`](BUILD_PLAN.md), [`DEMO.md`](DEMO.md), [`DECISIONS.md`](DECISIONS.md), [`HANDOFFS.md`](HANDOFFS.md), [`SECURITY_REVIEW.md`](SECURITY_REVIEW.md)). Nothing here says something works unless a test or a run in those docs proved it. Anything the repo can't back is marked **[verify]**. Re-read the [real-and-simulated table](#6-what-is-real-and-what-is-simulated) on the day, because it changes every time a PR merges.

Contents: [1. Tagline](#1-tagline-and-description) · [2. Demo script](#2-the-75-second-demo-script) · [3. Narrative](#3-problem-solution-why-now) · [4. Judge questions](#4-likely-judge-questions) · [5. Technically impressive](#5-what-is-technically-impressive) · [6. Real and simulated](#6-what-is-real-and-what-is-simulated)

## 1. Tagline and description

Three options:

1. **Find out, privately, that you noticed each other.**
2. **Notice someone. They only know if they noticed you too.**
3. **Two phones. One color. No pickup line.**

**Recommended: option 1.** It is plain, it is true of the build, and it matches the one-liner in the Devpost draft in `DEMO.md`. Option 3 is a good spoken closer for the stage, not a tagline.

**Description (one sentence).** Glow is a native iPhone app that lets two people in the same room find out, only if both are interested, that they noticed each other, and then turns both screens the same color with the same code word so they can find each other.

## 2. The 75-second demo script

Built on the real flow in [`DEMO.md`](DEMO.md#the-75-second-cut) (the same table lives there, next to the 3-minute script). Two presenters: **D** (David, phone A, shown on the document camera) and **R** (Robin, phone B). Both are admins, both are already checked in to the **stage room** before going on (setup: [`DEMO.md`](DEMO.md#stage-setup)).

**Where the seeded test people appear.** In the **stage room's deck only**, on D's phone (and R's). The stage room is called "Glow stage room (test data)". It holds the two stage phones plus twelve seeded test people ("Test River", "Test Sage" and so on). Their cards are cropped public-domain photos, they have no profile photos, and they never tap, so nobody can match one (D5-D1, D5-D2, D5-D8). Say so out loud when the deck first shows. The real attendee room never holds seeded people. The two presenters are real.

| Time | D (phone A) | R (phone B) | What the judge sees |
| --- | --- | --- | --- |
| 0:00 to 0:10 | Holds up phone A. "One of us has tapped the other. Neither of us knows." | Holds up phone B. Nods. | Two phones, nothing on either to give it away. The tension line, with no slide. |
| 0:10 to 0:20 | The deck is already open and filtered. Says: "The other cards are seeded test people. The two real people are us. I tap Robin. They weren't told." Taps R's card. | Flashes phone B to the judge: nothing happened. Then taps D's card at once. | The deck on the projector: three to five faceless outfit cards, no names, no faces. The tap confirmation. Phone B unchanged. This is the one-sided beat. |
| 0:20 to 0:30 | "Someone you noticed noticed you back." | Holds phone B up. | Both phones buzz about 0:20. Both show the mutual takeover, then each other's real profile for the first time. |
| 0:30 to 0:40 | Picks Find each other. "Find only happens if both say yes." | Picks Find each other. | Both screens go to full brightness, the same color, the same code word, the same meeting spot (about 0:35 to 0:40). Hold both up to the room. |
| 0:40 to 0:55 | "Look for the color. Say the word that is actually on the screen. No pickup line needed. The app hands you the excuse." | Says the word shown on the screen to D, as a question. | Both phones side by side, glowing the same color. |
| 0:55 to 1:15 | "Faces on outfit cards are blurred on your phone before upload. Your profile photos are shown only after a mutual match. Find out, privately, that you noticed each other." | Holds phone B up. | The glow stays up behind the close. |

**Close (if the slot allows more).** If the attendee room is live and TestFlight is approved: "Scan the poster by the food line." Otherwise say where to follow along. Never promise a public link that isn't approved.

**The excuse is the code word.** The code word is picked to be said aloud across a loud room (a comment in `words.ts` gives "Are you lantern?" as the example). On stage, say the word actually shown on the screen. The server picks it from 300 words, so a rehearsed example may not be the one on the phones.. Words are never romantic, never a first name, never a color (C3-D1). Glow offers no scripted openers. The chat has none either (C4-D5).

**Honest notes for the presenters.**

- The stage phones skip the location check: they are admins in a demo-mode room, and every skip is logged (SPEC, Location check, step 7; D5-D3). Don't say location was verified on stage. Attendees in the real room pass a real check.
- Never lock either phone, and never AirPlay or screen-share phone A with the deck open. The deck hides itself when the screen is captured (P12). If it happens, that is a feature: "The moment the screen is shared, the deck hides."
- No sound. Glow has haptics and light only. Don't promise sound. See [table](#6-what-is-real-and-what-is-simulated).
- These timings are estimates. Nobody has run the whole loop on two devices yet [verify in the first dry run].
- Lovegety is left out of the 75-second cut. If it comes up, treat every fact about it as **[verify]**: D5 wrote them from memory, and the 1998 date may be 1997 (Erfolg).
- Fallbacks (Wi-Fi, GPS, TestFlight, push, moderation, document camera) are in [`DEMO.md`](DEMO.md#fallback-plan). If the phones can't be used, play the backup video, recorded on Simulators. A real phone can't be screen-recorded with the deck open (P12); film a real phone with a second camera.

## 3. Problem, solution, why now

**Problem.** At a hackathon, a conference or a party, you notice someone and say nothing. Saying it first is a risk. Not saying it is a loss. They may have noticed you too, and neither of you will ever know. Glow makes no claim about what other apps do here **[verify before saying anything about competitors]**.

**Solution.** Glow works only inside one room, right now. You scan the room's QR code, and Glow checks once that you are inside, then keeps only pass or fail. You check in with a photo of today's outfit. Faces on that card are blurred on your phone before upload. You pick what you noticed and see a small deck of faceless cards: no names, no faces, no distances. You tap the one you noticed. They aren't told. If they tapped you too, both phones buzz and you see each other's real profile for the first time. Then each of you picks Find each other or Just chat. If both pick Find, both screens go to full brightness in the same color with the same code word and a meeting spot, for 15 minutes. You say the word and the excuse is made. (SPEC, Product flow.)

**Why now.** What makes this buildable today, from the spec's own stack choices:

- On-device face detection (Apple's Vision framework) means the face blur happens before upload, so the privacy promise doesn't rest on a server.
- Live Activities put the glow countdown on the lock screen, and Time Sensitive notifications can reach someone who is looking for a match.
- Fast vision models can check a photo inside a 2.5 second budget (MODERATION_TIMEOUT), so check-in feels instant while still failing closed. The spec uses `claude-haiku-5-5`.
- Universal links let the iPhone camera open Glow straight from a poster or a screen.

Why people want it now: in-person events are where strangers share a room and a phone is in every hand. This is a belief, not a measurement **[verify: no user research in the repo]**.

## 4. Likely judge questions

Each answer says what the repo does and what proved it. "Proved" means a test or run recorded in `HANDOFFS.md`, not a claim.

### Privacy

**Q. You use location. Can you see where people are?**
No. The phone sends one fix to `POST /api/rooms/:id/join`. The server compares it to the room's center, keeps pass or fail plus a rough accuracy bucket, and never stores or logs the coordinates (P2; SPEC, Location check). Proved: B2's `p2-no-coordinates` test spies on the logger, the console, error reports, database writes and replies, and audits the database columns. A room's own location is a public venue, so that is stored. The admin web shows no person's location.

**Q. Are faces uploaded?**
It depends on the photo. Faces on **outfit cards** are blurred on the phone before upload (P3). The card is a neck-down outfit photo. Vision finds faces, a strong blur plus pixelation covers each, a second check blurs any survivor, and the upload stops if one survives twice (B3-D5). The server then re-encodes, strips metadata, and runs Claude moderation that rejects a visible face. **Profile photos do show your face.** They are uploaded, moderated, and shown only to a person you have an active match with (P4; SPEC, data model). Say it that way: "Faces on outfit cards are blurred on your phone before upload; your profile photos are shown only after a mutual match." Proved: 22 `ImagingTests` on face fixtures (every face comes out blurred, no metadata) and 11 `FeatureCheckInTests`, on the Simulator. Not yet proved on a real camera.

**Q. What stops someone seeing a card or photo they shouldn't?**
Every image is checked on every request (P4). There are no public storage links. A card link is signed, lasts 60 seconds, and is bound to one viewer. The server checks `card_visible_to` and adds a faint watermark of the viewer's code. A card ID from anywhere else is useless, because the deck must have shown it to that person (D14). Proved: B3's tests against the local database: the anon key can't read the card bucket, an expired link answers 404, another person's link answers 404.

**Q. Can anyone learn who tapped them?**
No. A one-sided tap is invisible (P5). The reply to a tap is `sent` and promises nothing. No response, count or event reveals it, and the organizer dashboard has no tap count at all (D52, B7-D7). Proved: B4's contract tests, plus timing checks that compare a tapped and an untapped person (B4-D7).

**Q. Does the server know who you are before a match?**
It knows your account, as any app does. What the app receives before a match never carries another person's ID, name or face (P1). The API never returns a user ID other than your own (D20); a codegen check fails the build if a response gains a field like that. Proved: contract tests, and `codegen.sh`. **Not yet proved:** D2's proxy scan of all traffic during a full end-to-end run (D2 is still working; the full loop has not run).

**Q. How do you know all twelve invariants hold?**
Be exact. The rules are P1 to P12 in `AGENTS.md`. As of this snapshot:

| Invariant | Evidence on main today | Not yet proved |
| --- | --- | --- |
| P1 no other user's ID, name or face before a match | Contract tests; codegen check | Full-loop proxy scan (D1, D2) |
| P2 no coordinates stored or logged | B2 logger, console, database and column tests | |
| P3 only blurred card photos leave the phone | B3 unit tests on the upload payload | End-to-end traffic check |
| P4 every image checked per request | B3 tests (anon key, expired and foreign links) | |
| P5 one-sided taps never revealed | B4 contract and timing tests | |
| P6 no name on the lock screen | B5 snapshots of every push payload | A real push through Apple |
| P7 blocks both ways within 5 s | B8 live test: both decks lose each other | |
| P8 paused or departed leave decks within 5 s | B8 live test (pause) | C1's side (deck screen is an unmerged draft) |
| P9 cards and check-ins deleted within 10 minutes | B8 live purge test | The 5-minute cron needs Vercel Pro or an outside scheduler (Needs David) |
| P10 nobody under 18 finishes onboarding | Database trigger refuses the birthdate (D24); server check | B1's phone-side UI test (unmerged) |
| P11 not allowed returns 404, never 403 | The route helper turns 403 into 404; contract tests | |
| P12 deck hides while recorded or mirrored | B6 `glowHiddenWhenCaptured` and its tests | C1's deck screen and UI test (unmerged draft) |

### Safety and consent

**Q. Who can use it? How do you keep minors out?**
18+ only, and Glow does **not** check ID. Age is a **self-declared birthday** plus **photo screening**. The phone refuses under-18 birthdays first (B1-D2). The server refuses before writing (422 `under_18`). A database trigger refuses any under-18 birthdate, so a minor's birthdate is never stored (D24, P10). Profile photos go through Claude moderation, and a photo of someone who **may be under 18 is held for human review** and never shown until an admin approves it (B8-D2, B7-D11). Card photos of someone who may be under 18 are rejected. A determined minor who lies about a birthday and uploads a photo that looks adult would get through. That is a real limit.

**Q. What happens when someone blocks or reports?**
A block applies both ways, everywhere, within 5 seconds (P7). It ends any match, removes both people from each other's deck, and sends `match.ended` to both, exactly what an unmatch sends, so the other person can't tell a block from an unmatch (B8-D6, C4-D6). The screen says "Done. They won't see you again." A report is also a block. It keeps the reported person's last 20 messages as evidence for review (D23). Admins see reports in a queue, named only by watermark code, and can remove a card or ban (B7-D5). Proved: B8's live test.

**Q. What about harassment in chat?**
Chat opens only after a mutual match and a choice. Messages are moderated: a flagged message is refused and never stored. If moderation is slow, the message goes through as `pending` and is reviewed afterwards by the purge job, then hidden from the recipient if flagged (B8-D2, C4-D2, C4-D3). Chat is limited to 30 messages a minute. Either person can unmatch, which deletes the thread for both. Today moderation runs on a **fake** until an Anthropic key exists.

**Q. Is anyone ever told they were rejected?**
No. See "When interest isn't mutual" below.

**Q. Can people delete their data?**
Yes. `DELETE /api/me` removes every row, every stored photo, the device tokens and the auth user, then deletes Supabase Auth's audit entries about the person (B8-D4). A live test checks every uuid column of every public table, both buckets, the auth user and the audit log. Cards and check-ins also expire after 3 hours and are purged (P9).

### Abuse prevention

**Q. What stops spam, scraping or stalking?**
Limits, enforced in the database where it matters:

- 3 taps per person per room per day (`TAPS_PER_ROOM_PER_DAY`), counted exactly in `room_days` (A2's Checkpoint 1 fixes).
- 50 different cards a person can be shown per room per day (`CARD_VIEWS_PER_ROOM_PER_DAY`). Refreshing is free; browsing the whole room is not (D13).
- The deck order is shuffled with a seed from your ID, the room and the date, so refreshing gives the same order and nobody can work out who arrived when.
- Cards last 3 hours and carry no name, face or distance.
- Rate limits on every route (B8). In production these need Upstash; locally they are in memory (see the table). They fail open if Upstash is down, but the caps that matter for privacy (taps, views) are in the database regardless (B8-D3).
- A watermark of the viewer's code is on every card and match photo, and screenshots are logged (3 in 24 hours flags the account for review) (B8-D7, B7).

**Q. Can someone fake being in the room?**
Honest answer: partly. A QR code, poster or room code only gets you to the location check; it never gets you in by itself (SPEC). The screen QR rotates every 30 seconds (HMAC-SHA256, current and previous window accepted), so a photo of a screen stops working. A poster QR is a static token the organizer can rotate. The check itself trusts the fix the phone sends. We built no spoof detection **[verify: none in the repo]**. What a spoofer gets is a deck of cards in a room they aren't in, limited by 3 taps and 50 views a day.

**Q. Can a banned person come back?**
Known gap (D56): a ban lives on the profile, and deleting the account deletes it, so a banned person can sign up again as a new account. Fixing it would mean keeping a hash of an Apple ID or an email after deletion, which needs its own privacy decision. Not fixed.

**Q. Has anyone tried to break it?**
D2's security review found one **high** issue and fixed it: Supabase accepts password sign-up from anyone with the public key, which allowed a pre-account takeover of an email-code user (D2-F1). A trigger now refuses password sessions, with 7 live tests (5 fail with the trigger off). One low finding was fixed. D2's review is still going (a full-loop traffic scan and a chat attack list). Cloud settings that migration depends on (Confirm email on) can't be tested without a cloud project **[verify on the cloud project]** (`SECURITY_REVIEW.md`).

### Cold start

**Q. What if only a few people are in the room?**
The room is the filter, and the organizer's poster QR is the install funnel. The deck only ever holds people who are here now. That is the product's strength and its limit.

With few people, the deck is short. The server says why a page is empty (`emptyReason`), and the C1 deck shows, for `quiet`: "It's quiet here. Nobody else fits you yet. New looks appear as people check in." For filters that match nobody: "Nobody fits that yet. Try fewer details." This is the C1 build in draft PR #25, **not yet on main**. There is **no** "you're one of the first here" state, and in a room with zero to two other people that quiet message is what a judge would see. Gender and show-me rules shrink the visible pool further.

Small rooms also weaken anonymity: with very few cards, a card is easier to place. Cards are faceless, but this is a real tradeoff, and no minimum room size is enforced **[verify: none in the repo]**.

What we plan: posters at the food line and coffee station, a rotating QR on a laptop at the table, one Discord post, visits to nearby teams, with a target of 50 people checked in on day one, read from the anonymous live numbers (DEMO.md, The first 50 people). That is a target, not a result. We never seed fake people into the attendee room, and collect no emails (D5-D6).

### When interest isn't mutual

**Q. What does the other person see if they didn't tap back?**
Nothing. There is no rejection, no notification, no count and no "seen". A tap is invisible to the person tapped (P5), to the room, and to organizers (no tap count). Your tap lasts 24 hours and is gone. Nobody learns anything unless both tap. After an unmatch, the pair can see each other again but needs two fresh taps to match again (D16).

### Business model

**Q. How does it make money?**
**Proposed, David to confirm:** Glow is free for attendees. The organizer, venue or event pays per room. The admin web, printable posters, rotating display QR, live numbers and reports already exist for that role (B7). No numbers and no revenue claims: nothing in the repo sets a price, and there is no revenue. What the repo does show: rooms are made and run by organizers (admin web, printable posters, a rotating display QR, live numbers, reports; B7). That fits selling a room to an event organizer, a conference or a venue. It also has real running costs: Vercel Pro (for the 5-minute cleanup), Supabase, Anthropic moderation, Upstash, Apple Developer **[verify: actual costs]**. Don't quote revenue, pricing or user numbers. There are none.

### Why now

See [section 3](#3-problem-solution-why-now). Technical enablers are from the spec. The social claim is a belief **[verify]**.

### Why native iPhone

The spec chose native for the camera, Vision (face blur on the device), push, haptics and Live Activities (SPEC, Stack). The privacy promise depends on blurring before upload, which is on the phone. The glow needs full brightness, keep-awake and a lock-screen countdown. Whether a web app could do each of these on iOS was not tested **[verify]**. The cost: iPhone only, and attendees must install through TestFlight until the app is in the store, which needs the Apple Developer account (not yet).

### How it is different

- **Dating-app swiping (Tinder, Bumble) [verify specifics]:** these are built around a pool of strangers at a distance, with profiles. Glow works only in one room right now, shows no faces, names or distances until a mutual tap, and then helps you find the person in the crowd. Don't claim a one-sided like is revealed or hidden in those apps **[verify]**; the mutual-only reveal is not unique to Glow.
- **Lovegety [verify every fact]:** D5's notes say it was a 1998 Japanese keychain that beeped when someone nearby carrying one was open to talking too, and never said who or whether it was you. The 1998 date may be 1997 (Erfolg). Glow's difference is that it is about the one person you noticed, speaks only when mutual, and helps you find them.
- **What is Glow's own:** the room as the filter, faceless outfit cards, and the shared color and code word as the way to find each other.

### What if people aren't on the app

**Today, everyone in the room who is to match must be on the app and checked in.** If the person you noticed hasn't installed Glow, nothing happens and nothing can. Crossed Paths (finding people who aren't on the app) is named on the roadmap in the spec and **is not built**; no design for it is in the repo. A hardware Glow badge for people without the app is a Wave 4 idea, also not started **[verify]**. The organizer's poster QR is the install funnel for the room (see Cold start). Say this plainly if asked.

### Other questions to expect

**Q. Is it running on real iPhones?**
No. Nothing has run on a real iPhone. The camera, haptics, push while locked, indoor GPS and glow brightness in a bright hall are untested on devices. All app runs so far are on Simulators. There is no Apple Developer account, so no TestFlight build exists yet (Needs David).

**Q. Is the whole loop proven?**
Not end to end. The server side of every step is merged and tested against a real local database. The sign-in screens (B1) and the deck screen (C1) are unmerged draft PRs. Individual screens (rooms, check-in, mutual moment, glow, chat) run on the Simulator. The first run of the full loop on two Simulators waits on B1.

**Q. How was it built?**
By David and Robin with a team of AI coding agents (Claude Code) working in parallel waves, each owning one module, coordinated by an integrator agent: 24 agents in five waves (BUILD_PLAN). The contract came first (`openapi.yaml`), so each agent built against it. **[David: confirm how to describe the team.]**

## 5. What is technically impressive

- **Rules in Postgres that can't be skipped.** Who appears in your deck, the tap cap, one match per pair, and unique glow colors live in security-definer functions, with row level security on and no client policies. A route bug can't skip them. Proof: 443 pgTAP tests at Checkpoint 1 (plus later ones **[verify current count]**), including a lockdown test on every table, function and bucket.
- **Simultaneous taps make exactly one match.** `record_tap` takes an advisory lock on the pair. 50 pairs tapping at the same moment make exactly 50 matches, and each pair gets one `sent` and one `mutual` (B4-D4). The database test fails with the lock removed (41 of 50 matches), and B4's integration tests run the same race twice.
- **A deck in milliseconds.** The deck rules are written once as views and read by both the per-card checks and a set-based `get_deck` (B4-D5). About 2 ms of database time per deck with 300 people, down from about 25 ms (HANDOFFS, B4).
- **On-device face blur, then private signed images.** Vision finds faces, they're grown by 30% and blurred plus pixelated, a second pass catches survivors, metadata is stripped. Cards are served only through a viewer-bound 60-second signed link with a per-viewer watermark.
- **Rotating QR plus a location check.** A screen QR is an HMAC of a 30-second window, compared in constant time. The QR only gets you to the location check, which keeps pass or fail.
- **Per-viewer watermark.** A faint tiled code of the viewer on every card and match photo, drawn with a built-in pixel font, so a leaked screenshot can be traced. Snapshot-tested.
- **Flash-safe glow.** A 1.25 second pulse (0.8 a second, far from the 3 a second seizure limit) that brightens and never darkens: the dimmest moment is 76% of the brightest on the darkest color, tested against a 70% floor for all eight colors. Dark ink passes WCAG AA on every color (B6-D1, B6-D3). Reduce Motion only fades, slowly.
- **Unique color and word per glow.** 300 hand-picked code words, checked by tests for rhymes, near-homophones and names (C3-D1). 40 glows started at once in one room are all unique.
- **Agent-built, contract-first.** 24 agents in five waves built against one OpenAPI contract (52 operations) that generates both the Swift and TypeScript clients, with a CI check that fails when generated code is stale, and a check that ties the contract's limits to `constants.json`. A codegen check also refuses a contract whose responses could carry a user ID.

## 6. What is real and what is simulated

Taken from `HANDOFFS.md`, `DEMO.md`, `DECISIONS.md`, and the repo as of main `1af3364`. "Proved" means a test or run recorded there. **Nothing has run on a real iPhone.**

| Piece | State | What the docs prove | Say on stage |
| --- | --- | --- | --- |
| Database rules, API, contract | Real, merged | Tested on a **local** Supabase only. 443 pgTAP tests at Checkpoint 1; a server test suite **[verify current counts]**. | "The rules run in the database." |
| Cloud deployment | **Does not exist** | No Supabase cloud project, no Vercel project, no preview URL, no domain. The web domain is a placeholder. QR links don't open the app yet. | Don't say it is live online. |
| Full loop (sign in, join, check in, tap, mutual, glow, chat) | **Never run end to end** | Each server step is tested. The B1 sign-in screens and the C1 deck screens are unmerged drafts (PRs #6, #25). The app's session is a preview mock until B1 merges. | Describe the flow; don't claim a recording of the full loop unless one exists. |
| Mutual reveal in 2 seconds, message in under 1 second | Measured only with stand-ins | Message arrived 21 to 79 ms after broadcast with a local stand-in (C4). | Don't quote timings. |
| Face blur on the phone | Real, merged | Tested on fixture photos on the Simulator. | "Blurred on the phone." Not tested with a real camera. |
| Photo and chat moderation | **Simulated** until an Anthropic key exists | A deterministic fake rejects only marked test photos. Fails closed with a key; the live test has not run (Needs David 14). Synthetic outfit drawings are rejected by the real model as "no person". | Say it is a fake today. |
| Rate limits | In memory locally; **Upstash not set up** | Real policies, tested in memory. Required on Vercel by env checks. | Don't claim production rate limiting. |
| Purge every 5 minutes (P9) | Real code, tested | Live purge test passes. Needs Vercel Pro or an outside scheduler (Needs David 3, 13). | |
| Push through Apple | **Not run** | Payloads snapshot-tested (no names). No APNs key. A real sandbox push test skips until the key exists. Fixture pushes shown in the Simulator. | "Pushes arrive while the app is open." Don't show lock-screen pushes. |
| Realtime | Real, merged | Tested against the local Supabase (private channels, can't join another's). | |
| Sign in with Apple | Built, **untested** | Needs an Apple account. The email 6-digit code path is built; the email template change is an unmerged draft (PR #11). | |
| Location check | Real, merged | Tested with simulated location on the Simulator. Indoor GPS on a device untested. | Stage phones skip it (admins, demo mode, logged). |
| Live Activity (lock screen countdown) | Built and unit-tested | Not yet shown running in the Simulator. | |
| Haptics, glow brightness, brightness restore | Built | Brightness restore tested in six ways out. Simulator can't play haptics or change brightness. Untested on a device. | |
| **Sound** | **None exists** | There is no sound code and no brief for it. Glow has haptics and light only. | Don't promise sound. |
| Stage room | **Seeded test data** | 12 clearly marked test people, public-domain card photos, no profile photos, never tap. Seed script tests pass (14 unit, 6 integration). | Say the other cards are test people. |
| Stage phones | Real people, special mode | Admin accounts in a demo-mode room skip the location check. Each skip is logged. | Say it. |
| Attendee room and live numbers | Real, **not created yet** | Needs the venue, a domain, a TestFlight build. | |
| TestFlight, public link | **None** | No Apple Developer account. Release pipeline is built and tested up to the first Apple call. | |
| Security review | In progress | One high finding fixed with live tests; a full-loop traffic scan still to do. | |
| CI | GitHub Actions down (billing) | Merges were gated on a local CI run on David's Mac. | |
| Real iPhone | **Nothing has run on one** | Dry runs on real phones are blocked on the Apple account. | Don't say "tested on iPhone". |

**Before you pitch:** re-check B1 and C1 (are they merged and has the loop run on two Simulators?), whether TestFlight is approved, whether an Anthropic key and Upstash exist, and whether the venue, domain and attendee room exist. Update this table. If any claim above isn't true that day, say less.
