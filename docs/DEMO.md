# Demo and launch kit

D5's hand-off: how to run the 3-minute demo so it can't break, how to get the first 50 people into the room, what to say about privacy, and the Devpost draft. Decisions are D5-D1 to D5-D9 in [`DECISIONS.md`](DECISIONS.md).

**Status, 2026-10-24.** The seed script, this script, the fallbacks and the checklists are done. Three things wait on others: the venue (David), the full loop on `main` (B1, B3, C1 to C4, then the backup video), and real iPhones with TestFlight (the Apple Developer account, then the two dry runs). See [Done when](#done-when).

Contents: [Before the event](#before-the-event) · [The two rooms](#the-two-rooms) · [The seeded room](#the-seeded-room) · [The 3-minute demo](#the-3-minute-demo) · [The 75-second cut](#the-75-second-cut) · [Fallback plan](#fallback-plan) · [Stage setup](#stage-setup) · [Dry runs](#dry-runs-on-real-phones) · [Backup video](#backup-video) · [First 50 people](#the-first-50-people) · [Pitch points](#pitch-points) · [Devpost draft](#devpost-draft)

## Before the event

In this order. Each line says who does it.

1. **David: confirm the venue, the meeting spots and the table.** Today the venue is a placeholder, the Palace of Fine Arts in San Francisco (37.8029, -122.4484). To change it, edit `VENUE` at the top of [`scripts/seed-demo.ts`](../scripts/seed-demo.ts), and nothing else (D5-D4). Then `scripts/seed-demo.ts --print-venue` prints the values to type into the admin web, and the two `GLOW_DEMO_LAT` and `GLOW_DEMO_LNG` lines for `ios/fixtures/demo-room.env` (A1's file, so `sim.sh at venue` follows). A test fails until both match, so they can't drift.
2. **David: ask the Cal Hacks organizers** whether Glow may put up posters, post once in the Discord and have a table. Nothing goes up or out without a yes.
3. **David: Apple and the cloud** (HANDOFFS, Needs David items 1 to 11): the Supabase cloud project, Vercel, the Apple Developer account, the first TestFlight build, and the external review as early as possible. Without the public link, attendees can't install Glow (see [TestFlight not approved](#fallback-plan)).
4. **David or Robin: make both stage accounts admins.** Each signs up in the app once, then in the Supabase SQL editor: `insert into public.admins (user_id) select id from auth.users where email in ('you@…', 'robin@…');` (B7's note). Each adds 1 to 3 real profile photos: the reveal on stage shows them.
5. **Make the two rooms** ([The two rooms](#the-two-rooms)), the night before or at doors.
6. **Two dry runs on real phones, on the venue Wi-Fi** ([checklist](#dry-runs-on-real-phones)).
7. **Print the posters** at 100% (no "fit to page"), after the public link works.

## The two rooms

The stage demo and the attendees use different rooms (D5-D2).

| | Attendee room | Stage room |
| --- | --- | --- |
| Who's in it | Real attendees, and nobody else | The two stage phones, plus the seeded test people |
| Made with | The admin web (B7), by hand, once | `scripts/seed-demo.ts --remote --slug stage` |
| Name | "Cal Hacks" (or whatever the event is called) | "Glow stage room (test data)" |
| Center and radius | `VENUE` (`--print-venue`), radius to cover the hall and no more | The same |
| Meeting spots | `VENUE.meetingSpots` | The same (the seed sets them) |
| Demo mode | **Off.** Everyone passes a real location check. | **On.** The admin stage phones skip it, and each skip is logged. |
| Printed posters | On, for the posters | Off |
| Shown on stage | The rotating QR (display screen) and the live numbers | The phones themselves |

Why two: projecting a deck would show real attendees' outfits to the whole hall, and real attendees could tap the presenters. The stage room only ever holds people who agreed to be on stage, and test data. Its live numbers are seeded, so they're never what's projected; the attendee room's are real.

**Making the attendee room** (B7's steps, HANDOFFS, "Room setup at the venue"): sign in at `https://{DOMAIN}/admin/sign-in`, **New room**, stand in the middle of the hall and tap **Set center to my location** (check it against `--print-venue`), slide the radius until the circle covers the hall, rename the meeting spots to `VENUE.meetingSpots`, times from doors to the end of hacking, **Printed posters** on, **Demo mode** off, **Create room**. Then **Open display screen** and **Full screen** on the table laptop.

**Making the stage room**, from a laptop with the cloud project's keys (never committed):

```
SUPABASE_URL=https://<project>.supabase.co SUPABASE_SERVICE_ROLE_KEY=<service role key> \
  scripts/seed-demo.ts --remote --slug stage
```

It prints the room code. The stage phones join with that code (or by scanning `/display/stage` from the admin web), and skip the location check because they're admins in a demo-mode room. Run it again with `--refresh` 30 minutes before going on stage, so every seeded card has a fresh 3 hours. After the event: `scripts/seed-demo.ts --remote --slug stage --remove` deletes the seeded people and their photos, then **End room** in the admin web.

## The seeded room

`scripts/seed-demo.ts` (D5) makes a realistic room on a local or any Supabase. Everything in it is test data.

```
scripts/seed-demo.ts                    # the local `demo` room (A2's seed.sql made it)
scripts/seed-demo.ts --slug stage-2     # another test room, made if it doesn't exist
scripts/seed-demo.ts --refresh          # replace every card, each good for 3 more hours
scripts/seed-demo.ts --demo-mode        # turn demo mode on for an existing room
scripts/seed-demo.ts --remove           # delete the seeded people and their card photos
scripts/seed-demo.ts --print-venue      # the venue values
scripts/seed-demo.ts --remote …         # needed for anything that isn't localhost
```

- **People.** Twelve, all `{slug}-{name}@glow.test`, first names "Test River", "Test Sage" and so on, `test_data` in their auth metadata, all adults, a mix of genders and show me so whoever is on stage sees 3 to 5 cards. No profile photos, and they never tap anyone, so a match with a seeded person can't happen (D5-D8).
- **Cards.** From the three public-domain NASA crops in `ios/fixtures/photos/` (`outfit-real-*`: neck down, name tags pixelated), each mirrored, cropped and lit a little differently, at most 1920 px, JPEG 80, no metadata. No other photos of real people, ever.
- **Safe by construction.** It refuses any Supabase that isn't on this machine without `--remote`. It only touches a room whose name ends in "(test data)", so it can't put test people into a real event room (D5-D1). Join checks are recorded as `demo_skip`, never as a pass (D5-D3). A room it creates has demo mode on; an existing one keeps its setting unless `--demo-mode` (D5-D9).
- **Idempotent.** People have fixed IDs per room, the room and spots are updated in place, and cards with an hour left are kept. A second run makes nothing new.
- **On the shared local stack**, use `--slug` (for example `--slug d5-try`), so other agents' tests on the `demo` room don't suddenly see twelve more people.
- **Tests:** `pnpm --filter server exec vitest run tests/seed-demo` (14 unit tests), plus 6 integration tests with `GLOW_INTEGRATION=1` (and in CI): seeding, the live deck, a second run, `--refresh`, refusing a real room, `--remove`.

Checked on D5's own stack (2026-10-24): the second run made 0 people and 0 cards; through the real API, `POST /api/rooms/{demo}/deck` as Test Rowan (a man who shows women) and Test Quinn (nonbinary, shows everyone) returned 5 cards each, with only `id`, `image`, `tags` and `tappedByMe`, no name, email or user ID (P1); the admin metrics answered `activeCheckins: 12`. Card images answer 501 until B3's #7 merges.

## The 3-minute demo

Two presenters: **D** (David, phone A) and **R** (Robin, phone B), both admins, both checked in to the stage room before going on. A document camera (or a phone on a gooseneck) shows phone A on the projector; the laptop shows the attendee room's display screen and live numbers in two tabs. Timings are from the first word.

| Time | Who | On screen | Say (roughly) |
| --- | --- | --- | --- |
| 0:00 to 0:20 | D | Title slide, then the display screen's QR | "You've noticed someone at a hackathon. Maybe they noticed you too. Neither of you will ever say it. In 1998 [verify: possibly 1997, by Erfolg], Japan bought a gadget for exactly this: the Lovegety [verify]. It beeped when someone nearby was open to talking too [verify]. It never said who, and never whether it was you they'd noticed [verify]. Glow finishes that idea." |
| 0:20 to 0:40 | D | Phone A: scan, "You're in the room" | "Scan the room's code. Glow checks you're actually here, once, and then forgets where you are. We keep pass or fail, never your location." |
| 0:40 to 1:05 | D | Phone A: outfit photo, the blur preview | "Check in with a photo of today's outfit. Any face in this photo is blurred on the phone, before anything is uploaded. This is what others will see." (Show the preview. If it's already checked in, show the preview and cancel: the existing card stays.) |
| 1:05 to 1:35 | D | Phone A: What did you notice, then the deck | "I noticed someone in [R's outfit]. No names, no faces, no distances: just today's look. I tap. They aren't told. Nobody ever finds out about a tap that isn't mutual. Not them, not the room, not us on the dashboard." Tap R's card. |
| 1:35 to 1:50 | R, D | Both phones: the mutual takeover | R taps D's card. "If they tap me too..." both phones buzz. "Someone you noticed noticed you back. Only now do we see each other's real profile." |
| 1:50 to 2:20 | R, D | Both phones held up: same color, code word, meeting spot | Both pick Find each other. "Find only happens if both say yes. Now both screens glow the same color with the same code word, and Glow picks a meeting spot." Hold both phones up to the room. "In a crowded hall, you look for the color. Then you walk up and say the code word: 'Are you maple?' No pickup line needed. The app hands you the excuse." |
| 2:20 to 2:35 | R, D | Both tap We met; the chat | "We met. The chat stays open." |
| 2:35 to 3:00 | D | Laptop: live numbers for the attendee room | "Everything you saw is real and running now. [Number] people are checked in to this room. You'll notice there's no tap count, on purpose. Scan the poster by the food line to join." |

## The 75-second cut

For a judging table or a short slot. Same two phones and the same stage room as the 3-minute demo, with the check-in already done during setup (see [Stage setup](#stage-setup)). It opens on the one-sided beat, not on history, and it leaves the Lovegety line out. The glow lands in the last third, so keep the opening tight. Timings are estimates until the first dry run [verify].

| Time | Who | On screen | Say (roughly) |
| --- | --- | --- | --- |
| 0:00 to 0:10 | D, R | Both phones held up, screens dark or on the room home | "One of us has tapped the other. Neither of us knows which." |
| 0:10 to 0:30 | D | Phone A on the document camera: the deck is already open, filtered to what D noticed, with R's card and a few seeded cards. D taps R's card: "They won't know unless they tap you too." | "This is our stage room, so the other cards are seeded test people. The two real people are us. I noticed Robin's jacket. I tap. They weren't told." R holds up phone B: nothing has happened. |
| 0:30 to 0:50 | R, D | R taps D's card. Both phones buzz. Both show the takeover, then each other's real profile. | "Now Robin taps me. Someone you noticed noticed you back. Only now do we see each other." |
| 0:50 to 1:10 | R, D | Both pick Find each other. Both screens go to full brightness, the same color, the same code word, a meeting spot. Hold both phones up to the room. | "Find only happens if both say yes." |
| 1:10 to 1:15 | D | Both phones up | "Look for the color, say the code word. No pickup line needed. The app hands you the excuse." |

**If there is a second or two to spare**, add one line before the first tap: "Faces on outfit cards are blurred on your phone before upload. Your profile photos are shown only after a mutual match."

**Rules.** The "Rules on stage" below apply to this cut too. The stage phones skip the location check because they are admins in a demo-mode room (each skip is logged); don't say the location was verified on stage.

**Rules on stage.** (These apply to the 3-minute demo and the 75-second cut.) Never lock either phone (push may not be set up, see below). Never AirPlay or screen-share phone A while the deck is open: the deck hides itself when the screen is captured (P12). That's a feature worth one line if it happens: "See? The moment the screen is shared, the deck hides." Keep R's card findable: R checks in in something distinctive and sets the matching tags.

**Between runs (rehearsals and dry runs), reset the pair:** unmatch from the chat menu (an active match keeps both out of each other's deck), and seed a new stage room with `--slug stage-dry-1`, `stage-dry-2` and so on, then `stage` for the real show. Taps are capped at 3 per person per room per day, and a re-tap after an unmatch uses a new one (D53), so a fresh room per run means the cap can't bite on stage.

## Fallback plan

Decide the fallback before going on stage, not during it. Each risky step has one.

| Risk | How you'll know | Fallback |
| --- | --- | --- |
| **Venue Wi-Fi** is slow or blocks things | Dry run: the deck takes more than 2 s, or the mutual moment doesn't arrive | Both stage phones on a personal hotspot from a third phone (cellular), set up before going on, Wi-Fi off. The laptop on the same hotspot. If the hotspot fails too: the backup video. |
| **Indoor GPS** is fuzzy | "Looks like you're not in this room yet" in a dry run | Stage phones: demo mode in the stage room, and both are admins, so they skip the check (each skip is logged). Attendees: a radius that covers the whole hall (the accuracy credit already subtracts up to 100 m, and fixes worse than 500 m are retried). Never turn on demo mode in the attendee room: it only helps admins anyway. |
| **TestFlight not approved** | No public link by the morning of the event | Stage phones install as internal testers (no review needed; RELEASE.md step 9). Attendees can't install, so: no posters and no Discord post, and the last line of the demo becomes "it's in TestFlight review; follow along on Devpost." Don't collect emails as a workaround (D5-D6). |
| **No Apple Developer account at all** | Can't make a TestFlight build | Run the live demo on two Simulators on the laptop, side by side, mirrored to the projector (Debug builds use the photo picker for check-in), or play the backup video. Say so on stage: "running in the Simulator today". |
| **Push without an APNs key** | `APNS_*` not set in Vercel production | Nothing on stage needs push: the mutual moment and the glow arrive over Realtime while the app is open, the tapper also gets it in the tap reply, and the Live Activity starts on the phone. So keep both apps open and never lock the phones. Lock-screen pushes are the only thing missing; don't show them. |
| **Moderation (Claude) slow or down** | Check-in fails after about 2.5 s ("try again") | Card photos fail closed. Both phones check in during setup, before going on stage. On stage, show the blur preview and cancel: the card from setup stays. |
| **Supabase or Vercel down** | The deck won't load in the last check backstage | The backup video. |
| **The document camera fails** | No picture of phone A | Hold the phones up for the glow (it's visible from the back of the room anyway) and play the backup video for the deck. |
| **A card won't show** | R's card isn't in D's deck | R's tags don't match D's filters, or they still have an active match from a rehearsal: clear the filters, or unmatch. Last resort: R taps D first, then D finds R. |
| **Battery** | Below 50% before going on | Both phones charged to 100% and on low power mode off; the glow runs at full brightness. |

**The backup video** plays from the laptop's desktop, already open and paused on its first frame, sound off. Switching to it should take one click.

## Stage setup

At least 30 minutes before.

- [ ] Both phones: latest TestFlight build, signed in, charged, Do Not Disturb on (except Glow), auto-lock set to Never, brightness up, on the hotspot.
- [ ] `scripts/seed-demo.ts --remote --slug stage --refresh`, then both phones join the stage room by its code and check in. R wears something distinctive and tags it.
- [ ] **Pre-set the tags and the deck filters.** R's check-in tags are set (top color, hair, extras) and D has already picked What did you notice so R's card shows near the top. Live filter picking costs about 20 s on stage. Don't relaunch the app afterwards: the filters live in the app's memory, not on the server [verify against the C1 build; PR #25 is still a draft].
- [ ] D opens the deck once and checks R's card is there (then leaves it: card views count).
- [ ] Neither phone has an active match with the other (Matches tab is empty).
- [ ] Laptop: admin web signed in, tab 1 the attendee room's display screen (Full screen), tab 2 its live numbers. Backup video open and paused. Plugged in.
- [ ] Document camera on phone A, focused, the projector showing it.
- [ ] After the demo: sign out of the admin web on the laptop when the event ends (B7).

## Dry runs on real phones

**Blocked** until the Apple Developer account, a TestFlight build and the cloud project exist. David runs this twice, on the venue's Wi-Fi, ideally in the hall, the day before or at doors. Each run takes about 15 minutes. Write the result in HANDOFFS under D5.

Before the first run: both stage accounts are admins with profile photos; the stage room exists (`--slug stage-dry-1` for run 1, `stage-dry-2` for run 2); the attendee room exists.

1. [ ] Phones on the **venue Wi-Fi** (not the hotspot), Wi-Fi only, cellular off.
2. [ ] Scan the attendee room's display QR with the iPhone Camera: Glow opens to that room. Standing in the hall, the location check passes (no demo mode there). Note how long it took.
3. [ ] Scan a printed poster: same. Leave the attendee room again (Leave on the room screen).
4. [ ] Both join the stage room by code; both skip the location check (admins, demo mode).
5. [ ] Both check in with the camera: the face blur preview takes under a second, the upload passes moderation.
6. [ ] D's deck shows R's card and some seeded cards, with watermarks. Time from tap to deck: under 2 s.
7. [ ] Try mirroring phone A with Screen Mirroring: the deck hides. Stop mirroring.
8. [ ] D taps R; R taps D: both phones buzz and show the mutual takeover within 2 s. Lock one phone first in run 2 only, to see whether push arrives (needs the APNs key).
9. [ ] Both choose Find: both glow the same color with the same code word and meeting spot; the Live Activity is on the lock screen; brightness is full; the glow is visible from 20 m away in the hall's light.
10. [ ] Both tap We met; send one chat message each way.
11. [ ] The attendee room's live numbers on the laptop update within 10 s.
12. [ ] Reset: unmatch from the chat. Note anything slow, wrong or confusing, with the time.
13. [ ] To film a dry run of a real phone, use a **second camera** (another phone, filming over the shoulder). Don't screen-record a real phone with the deck open: the deck hides itself while the screen is recorded (P12), so the video would show the cover, not the cards.
14. [ ] Run 2 only: everything again on the **hotspot**, and time the whole demo against the script (3:00 or under).

## Backup video

**Blocked** until the full loop works on `main` (needs B1's sign-in, B3's check-in, and C1 to C4's deck, mutual moment, glow and chat). Recorded on two Simulators with `sim.sh record`. D5 asks main before taking two Simulator slots.

Shot list, about 90 seconds, both screens side by side: Glow A scans the demo room, checks in with `outfit-real-white-suit.jpg` (tagged white) and shows the blur preview; Glow B checks in with `outfit-real-lightblue-suit.jpg` (tagged blue); A picks What did you notice (blue) and taps B's card ("They won't know unless they tap you too"); B taps A; the mutual takeover on both; both choose Find; both glow; both tap We met; one chat message each way. The seeded crowd uses the same three photos, so a few cards look alike; that's expected.

```
scripts/sim.sh setup && scripts/sim.sh build && scripts/sim.sh install
scripts/seed-demo.ts --slug demo --refresh       # own stack, so the deck has a crowd
scripts/sim.sh at venue && scripts/sim.sh photos
# sign in as alex@glow.test on A and blake@glow.test on B (A2's seed; B1's Debug test sign-in), then:
scripts/sim.sh scan demo
scripts/sim.sh record d5-backup-full-loop         # Ctrl-C when done
scripts/sim.sh release
```

Record on Simulators, not on real phones: P12 hides the deck during any screen capture of a real phone, so a screen recording of a real phone shows the cover instead of the cards. A real-phone video must be filmed with a second camera.

The result goes in `docs/shots/d5-backup-full-loop-A.mp4` and `-B.mp4`, plus one side-by-side cut for the stage laptop. The same recording can be `GLOW_REVIEW_VIDEO_URL` for Apple's beta reviewers (RELEASE.md, step 8). The Simulator's recording shows the deck (it isn't a screen capture from iOS's point of view), and every card in it is seeded test data, so it's safe to show anywhere.

## The first 50 people

The goal is 50 real people checked in to the attendee room on the first day, measured on the live numbers page (joins, checked in now, matches), never by anything personal. Only once the public TestFlight link works and the organizers have said yes (D5-D6).

1. **Posters** (B7's PDF, printed at 100%, at least 4-inch QR). Where people stand still with their phones out: the food line (two, at eye level, at the start and the middle of the line), the coffee and water station, the entrance and the Glow table. Each says: scan, check in with your outfit, tap who you noticed. All posters share the room's one poster code; we don't track which poster anyone scanned. Watch the live numbers after each meal instead.
2. **The table.** The laptop with the rotating QR full screen, both of us wearing something easy to describe, a one-line sign: "Find out, privately, if someone you noticed noticed you." Offer to walk anyone through check-in on their own phone, and never touch it.
3. **One Discord message**, posted by David in the channel the organizers pick, once, at the start of the first meal (draft below). No DMs, no @everyone, no reposting.
4. **Visit nearby teams** in the first two hours, while people are still settling in: "Hi, we're building Glow, it's in TestFlight. If you've ever noticed someone at a hackathon and never said anything, it tells you only if it's mutual. The QR's on the poster by the food line." Leave if they're busy. Aim for 10 teams, about 30 to 40 people.
5. **Meal peaks.** Dinner and the midnight snack are when the room fills: be at the table, check the live numbers at the start and end of each meal.
6. **What we never do:** seed fake people into the attendee room, show anyone else's card, collect emails or names for a waitlist, or say who is checked in.

**Discord draft** (for David to post; not posted):

> Hi all! We're building **Glow** this weekend: if you noticed someone here and they noticed you too, Glow tells you both, privately. Nobody ever finds out about a one-sided tap. Scan the poster by the food line (or the QR at our table), check in with a photo of today's outfit (any face in it is blurred on your phone before upload), and tap who you noticed. It's in TestFlight, 18+ only, and your outfit card disappears after 3 hours. Feedback very welcome at our table!

## Pitch points

**The one-liner.** Glow lets two people in the same room find out, privately, that they noticed each other.

**The Lovegety line.** "In 1998 [verify: possibly 1997, by Erfolg] Japan briefly went wild for the Lovegety [verify], a keychain that beeped when someone nearby carrying one was open to talking too [verify]. It told you somebody close by was interested in somebody: never who, and never whether it was you [verify]. Glow finishes that idea: it's about the one person you noticed, it only speaks when it's mutual, and then it helps you find each other in the crowd." (D5 wrote every Lovegety fact from memory, and the other session believes it launched in 1997 from Erfolg. Check them all before saying any on stage. The 75-second cut leaves it out.)

**The privacy story**, in the order to tell it. Each line is an invariant with an automated test (AGENTS.md).

- **You're anonymous until it's mutual.** Cards are faceless photos of today's outfit: no name, no face, no distance. Nothing the app receives before a match carries another person's ID, name or face (P1).
- **Faces on outfit cards are blurred on your phone, before upload (P3).** Your profile photos, which do show your face, are shown only after a mutual match. Every image is checked on every request, with no public links, and watermarked with the viewer's code so a leaked screenshot can be traced (P4).
- **A one-sided tap is invisible. Forever.** No response, count or event reveals it (P5), and the organizers' live dashboard has no tap count at all.
- **We check you're in the room, then forget where you are.** Only pass or fail is kept, never coordinates (P2).
- **It disappears.** Cards and check-ins are deleted within 10 minutes of expiring, after 3 hours (P9).
- **Safety is built in.** Blocks apply both ways within 5 seconds (P7), pausing or leaving takes you out of every deck within 5 seconds (P8), 18+ only (P10), the lock screen never shows a name (P6), asking for something you can't see looks exactly like asking for something that doesn't exist (P11), and the deck hides itself when the screen is recorded or shared (P12).
- **The app is the excuse.** Both screens show the same code word, so you walk up and say it ("Are you maple?"). No pickup line needed. Glow suggests no openers (C4-D5 for chat).
- **Find only happens if both say yes.** After a match, each picks Find each other or Just chat. Find needs both, plus a fresh location check.

**Why it's different.** Dating apps show you strangers far away. Glow only works for people in the same room right now, and the room is the filter. It's the opposite of swiping: you've already seen them.

**What's next.** Bluetooth and Ultra Wideband to point the way to each other (Wave 4), a Glow badge for people without the app, more event types.

## Devpost draft

A draft for David to edit and submit. Not posted (D5-D7). It says what's real and what's simulated; keep it that way.

**Glow**

*Find out, privately, that you noticed each other.*

**Inspiration.** Everyone at a hackathon has noticed someone and never said anything. Saying it first is a risk; not saying it is a loss. In 1998 [verify: possibly 1997, by Erfolg], Japan's Lovegety [verify] tried to solve this with a keychain that beeped when someone nearby carrying one was open to talking too [verify], without ever saying who [verify]. We wanted the version that only speaks up when it's mutual.

**What it does.** Scan the room's QR code. Glow checks you're in the room, then forgets where you are. Check in with a quick photo of today's outfit; any face in it is blurred on your phone before upload. Pick what you noticed (gender, top color, hair) and scroll a small deck of faceless cards. Tap the person you noticed: they aren't told. If they tap you too, both phones buzz and you see each other's real profile for the first time. If you both choose Find each other, both screens glow the same color with the same code word and a meeting spot, with a 15-minute Live Activity on the lock screen. Both screens show the same code word, so there is no pickup line to find: you walk up and say it. Tap We met, and the chat stays open.

**How we built it.** A native iPhone app in Swift 6 and SwiftUI (Vision face blur on the device, ActivityKit Live Activities, Core Haptics), a Next.js API on Vercel, and Supabase (Postgres, Auth, Storage, Realtime). The rules that must never break live in Postgres functions: who appears in your deck, the tap cap, and exactly one match when two people tap at the same moment. One OpenAPI contract generates both the Swift and TypeScript clients. Photos are moderated with Claude. [David: describe the team honestly here, for example "built by David and Robin with a team of AI coding agents (Claude Code) working in parallel waves, each owning one module, coordinated by an integrator agent."]

**Privacy.** Twelve privacy invariants, each with an automated test: anonymous until mutual, faces on outfit cards blurred on the phone before upload (profile photos are shown only after a mutual match), one-sided taps never revealed, coordinates never stored, everything gone 3 hours later, blocks both ways in 5 seconds, 18+ only, and the deck hides when the screen is recorded.

**Challenges.** Making anonymity real rather than a promise: the server never sends another person's ID or name before a match, images are checked on every request, and even timing can't reveal a one-sided tap. Indoor location is fuzzy, so the room check is generous by design and admin demo phones can skip it, with every skip logged.

**Accomplishments.** [David: fill in what's true on the day, for example "N people checked in on the first day; M mutual matches; K people met."]

**What we learned.** [David]

**What's next.** Bluetooth and Ultra Wideband to point the way to each other, a Glow badge, and more kinds of rooms.

**What's real and what's simulated.** [Keep this section. Update it on the day.]

- Real: the iPhone app, the API, the database rules, on-device face blur, moderation, the live room at this event and its numbers.
- The stage demo runs in a separate room with seeded test people ("Test River" and friends), whose cards are public-domain NASA photos cropped below the neck. They're labeled test data and can never match anyone. The two presenters are real.
- The stage phones skip the location check (admin demo mode), and every skip is logged.
- [If true on the day:] lock-screen push isn't set up yet; everything shown arrives while the app is open. / The public TestFlight link is still in Apple's review. / The demo ran on Simulators.

**Built with.** swift, swiftui, vision, activitykit, next.js, typescript, supabase, postgresql, vercel, claude, upstash, posthog, sentry

## Done when

| Box | State | Why |
| --- | --- | --- |
| Two full dry runs on real phones, on venue Wi-Fi | **Blocked** | Needs the Apple Developer account, a TestFlight build, the cloud project and the venue. The [checklist](#dry-runs-on-real-phones) is ready for David. |
| The backup video is recorded | **Blocked** | Needs the full loop on `main` (B1 #6, B3 #7, C1 #25, C2 #26, C3 #27, C4 #23 are still open). The [shot list and commands](#backup-video) are ready. |
| The Devpost draft is ready | **Done** | [Above](#devpost-draft), with the real-and-simulated section. Not posted. |
