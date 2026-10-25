# Status

Running note for David and Robin. Updated by the build orchestrator whenever something changes. Last updated 2026-10-24, main `c9cb615`.

Nothing here says "works" unless a test or a run proved it. "Proven" means a test ran against the real local database or the app on a Simulator. No part of this has run on a real iPhone.

## Wow moment

Two people in one room both tap each other. Both phones buzz, then both screens go to full brightness in the **same color** with the **same code word** and a meeting spot, so they can find each other across a loud hall. It needs no sound and is visible from across the room, so a judge can see it from the back. The quiet "someone here noticed you" notification is the setup; the shared glow is the payoff. The first 30 seconds of the demo should end on it, with one beat before it that shows nothing happens when interest is one-sided.

## Done and proven

| Area | State | Proof |
| --- | --- | --- |
| Database and API contract | Merged. Every rule lives in Postgres (deck rules, taps, one match per pair, blocks both ways, expiry). | 443 database tests, including 50 pairs tapping at once making exactly 50 matches. |
| Server (every endpoint) | Merged: profile and photos, rooms, check-in, deck, taps, matches, choice, glow, chat, safety, admin, push. | About 700 server tests. |
| Rooms and joining | Merged: QR, room code, rotating screen QR, location check that keeps only pass or fail. | Tests, including that no coordinates reach logs, replies or the database. |
| Private images | Merged: faces blurred on the phone, signed 60-second links, per-viewer watermark. | Face fixtures (1 to 13 faces) all blurred; expired or foreign links answer 404. |
| Deck and matching | Merged. | Deck under 300 ms with 300 people (161 ms at 50 in flight). |
| Safety | Merged: block, report, pause, delete account, purge every 5 minutes, held photos. | Live tests: block removes both people within 5 s; deletion leaves no rows or files. |
| Push and realtime | Merged: live realtime channels, push sender, notification routing. | Payload snapshots show no names; one person can't join another's channel. |
| Design system | Merged: tokens, components, glow surface, takeover, haptics, card tile. | 45 tests; contrast checked for every pairing. |
| Match, glow and chat screens | Merged, with the icebreaker chips (#55, say-aloud lines on the glow screen, tap-to-fill openers in chat). | Server tests for every choice combination; snapshot and unit tests; Simulator screenshots. |
| Full loop on the Simulator | Merged (B1 sign-in and the deck are in). Person B is a script, not a second phone. | D1's journey passed 10 of 10 in a row on one warm Simulator (1198 s). The verification pass re-ran it once warm and it passed (64 s). After the #58 fix, one cold first run on an erased Simulator also passed (83 s). Recording: `docs/shots/d1-e2e-full.mp4`, two Simulators. |
| Admin web | Merged: rooms, posters, rotating QR, reports, held photos. | 112 tests; non-admins get 404 everywhere. |
| Security | One high finding fixed (account takeover through password sign-up), one low fixed. | Live test against the real local auth service. |
| Demo kit | Merged: seed script, demo script, fallbacks. | Seed script tests. |
| Release pipeline | Merged. Cannot run without an Apple account. | Lane tests only. |

## Blind mode and the design revamp (branch `integrate/y1`, not on main)

`blind-mode` merges X1 (Blind backend), X2 (Blind tab, FeatureBlind), U1 (design foundation), U2 (rooms, check-in, deck) and U3 (mutual moment, glow, chat). Y1 integrated it; details in `docs/qa/y1.md`. R1 re-ran the Rooms journey on it (`verify/r1`, from `blind-mode` `734d3ea`); details in `docs/qa/r1.md`.

| Area | State | Proof |
| --- | --- | --- |
| Builds and lint | iOS build and SwiftLint/SwiftFormat clean after Y1's fixes | `scripts/sim.sh build`, `lint` on `integrate/y1`, and again on `verify/r1` |
| Tests | Server Vitest 1019 passed; pgTAP 672/672 on a clean stack (Y1). iOS unit tests on `verify/r1`: 466 in 20 runs, all pass, no recording. R1 froze the two flaky snapshots (Glow loading, Match waiting: live breathing lights) and fixed the hairline outside capsule buttons (79 snapshots re-recorded, looked at) | `docs/qa/y1.md`, `docs/qa/r1.md` |
| **Rooms on the redesign, live** | D1's full journey (check in, today's looks, B's card, secret tap, mutual, both Find, the same code word, We met) passes with no selector or copy change. Person B is a script on the API | `scripts/e2e/run.sh full` on R1's own stack: 4 of 4 runs passed (the last on the final code, recording both Simulators: Glow B showed the same code word and color as Glow A), no privacy violations from player B; screenshots `docs/shots/combined/rooms-live-*.png` |
| Blind backend | Every `/api/blind/*` route live | X1's stage script 27/27 on Y1's own stack, no leaks before reveal |
| **Blind on two Simulators, live** | Opt-in, 5 likes, drop, chat both ways, one-sided reveal (the other phone unchanged), mutual reveal | XCUITest on Glow A and Glow B against the real server and database (no mocks); 19 screenshots in `docs/shots/combined/` |

Not proven on this branch: D1's chat, block, expiry and push journeys after the redesign (only the full journey was re-run), Blind's give-away warning, Guess Who, Report and Block on a live server, and anything on a real iPhone.

## In progress

- **First run on a fresh Simulator: fixed, proven once.** The verification pass found the first full run on a brand-new Simulator failed (the location-permission dialog covered the Join screen). D1's fix (#58) installs the app before granting permission; D1 reproduced the failure on the old script and passed run 1 from a cold Simulator on the new one (83 s). One cold pass, not ten.
- **Review of the pitch against what actually ran.** Pitch and demo docs updated in this change; the verification pass's full report is in the orchestrator's notes.
- **Shared Simulator and build limits** for all projects on this Mac.

## Not proven yet

- The full loop on two real phones, and 10 cold first runs in a row (one cold run has passed).
- Timing of the 5-second rules (block, pause), push, haptics, the camera, P3 traffic, P6, P9, P12 on a real run: the verification pass did not check them. What it did check: 465 of 465 database tests, 6 of 6 end-to-end checks, the public keys can read nothing, and no coordinates in the server log.
- The mutual reveal within 2 seconds, and a message reaching the other phone in under 1 second. Measured only with stand-ins.
- The lock-screen countdown starting and ending on time.
- Anything on a real iPhone: camera, haptics, push while locked, location inside the venue, glow brightness in a bright hall.
- Bad network and denied location ("Don't Allow"). Nobody has run either path.

## What is simulated

| Piece | What stands in | Why |
| --- | --- | --- |
| Photo and chat moderation | A deterministic fake (rejects only marked test photos) | No Anthropic API key yet. With a key, the real model runs and card photos fail closed. |
| Rate limits | In memory | No Upstash yet. |
| Push through Apple | Fixture notifications in the Simulator | No Apple Developer account, so no push key. |
| Sign in with Apple | Built, untested | Needs the Apple account. |
| Stage room | 12 clearly marked test people, faceless cards, never tap | So the demo never shows real attendees. The attendee room is real. |
| Stage phones | Admin accounts in a demo-mode room, skipping the location check | Indoor GPS is unreliable on stage. Every skip is logged. |

## Risky

- **GitHub Actions is down** (billing). Everything merged on a local CI run instead. Fix: GitHub billing.
- **No Apple Developer account**: no TestFlight, no real push, no real-iPhone check. This is the biggest risk to a winning demo.
- **The cloud database must accept the password-session rule** (migration 0005) and keep "Confirm email" on. Not testable locally.
- **Cold start**: today everyone in a room must be on the app. "Crossed Paths" (works when others aren't) is on the roadmap and not built.
- **No sound design** yet. Haptics exist; sound is in no brief.
- **Account usage limit** has stopped all agents once. Resumed from saved work each time.

## Needs David or Robin (answer once)

1. Join the Apple Developer Program and share the Team ID. Then the steps in `docs/RELEASE.md` (about 12 clicks).
2. Fix GitHub billing (github.com/settings/billing), then tell me so I re-check CI.
3. Confirm the Cal Hacks venue, meeting spots and table location (one edit in `scripts/seed-demo.ts`).
4. Give me an Anthropic API key for real moderation (or say to keep the fake for the demo).
5. Choose a web domain (needed for QR links to open the app).
6. Create the cloud projects: Supabase (keep "Confirm email" on), Vercel, Upstash. Steps are under "Needs David" in `docs/HANDOFFS.md`.
7. Add Robin as a collaborator on `davidaxie/glow`.
8. Make both stage accounts admins and give each real profile photos.
9. Ask the organizers about posters, a Discord post and a table.
