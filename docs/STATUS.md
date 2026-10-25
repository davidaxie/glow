# Status

Running note for David and Robin. Updated by the build orchestrator whenever something changes. Last updated 2026-10-24, main `1af3364`.

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
| Match, glow and chat screens | Merged. | Server tests for every choice combination. App screens only on fixtures so far. |
| Admin web | Merged: rooms, posters, rotating QR, reports, held photos. | 112 tests; non-admins get 404 everywhere. |
| Security | One high finding fixed (account takeover through password sign-up), one low fixed. | Live test against the real local auth service. |
| Demo kit | Merged: seed script, demo script, fallbacks. | Seed script tests. |
| Release pipeline | Merged. Cannot run without an Apple account. | Lane tests only. |

## In progress

- **B1 iOS sign-in and onboarding.** The server half is merged. The app half (real sign-in, onboarding screens, a Debug launch option to sign in as a test person) is the one piece blocking every real end-to-end run.
- **C1 deck screens.** Built, waiting on tests and a merge.
- **D1 end-to-end tests** and the two-Simulator recording. Waiting on B1.
- **D2 security review.** Still going: a full-loop traffic scan, and the chat attack list.
- **Pitch pack** (60 to 90 second script, Q&A, narrative): being written.
- **Shared Simulator and build limits** for all projects on this Mac.

## Not proven yet

- The full loop for real (sign in, join, check in, tap, mutual, glow, chat) on two Simulators. Waits on B1.
- The mutual reveal within 2 seconds, and a message reaching the other phone in under 1 second. Measured only with stand-ins.
- The lock-screen countdown starting and ending on time.
- Anything on a real iPhone: camera, haptics, push while locked, location inside the venue, glow brightness in a bright hall.
- Bad network, denied location and first launch end to end. Individual screens exist; nobody has run the whole path.

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
