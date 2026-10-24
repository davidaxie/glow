# Wave 2 · Core loop

Four agents in parallel, building the core experience on top of Wave 1.

## C1 · Deck experience

**Mission.** Make finding the person you noticed take under 20 seconds, one-handed.

**Read first.** In the Technical spec: Product flow, Core rules and numbers, Design system. B2's, B3's and B4's hand-off notes. Privacy invariants P1, P8 and P12.

**You own.** FeatureDeck.

**Build.**

1. Room home: the room's name, your check-in status and time left, a Visible or Paused toggle, and Leave.
2. A What did you notice sheet: gender (within your show me), top color, hair and extras. Any of them can be skipped.
3. The deck: a two-column grid, tap to enlarge, the watermark visible, pull to refresh, and views left today shown quietly.
4. Tapping: a That's them button opens a confirm sheet saying they won't know unless they tap you too, with taps left today.
5. Empty states: nobody fits, the room is quiet, your check-in expired (with a button to check in again).
6. Privacy: blur the whole deck while the screen is recorded or mirrored. On a screenshot, show a gentle note and report it to `/api/abuse/capture`.
7. Live updates: refresh when `deck.changed` arrives.
8. On a mutual tap, hand off to FeatureMatch's takeover by Route.

**Done when.**

- [ ] In a seeded room of 200, a tester finds a target card in under 20 seconds using filters
- [ ] A traffic check shows no user IDs in any deck response
- [ ] A UI test fakes screen recording and sees the deck blur (P12)
- [ ] Snapshot tests for every state

**Hand off.** Notes for D4's copy pass, listing every string in the module.

## C2 · Mutual moment and reveal

**Mission.** Make the moment two people find out they both noticed each other feel special.

**Read first.** In the Technical spec: Product flow, Core rules and numbers (choosing and glow), Events and push, Design system. Privacy invariant P1.

**You own.** FeatureMatch, the routes `GET /api/matches/:id` and `/api/matches/:id/choice`, and `server/src/server/choice`.

**Build.**

1. A full-screen takeover when `match.created` arrives, or when the notification is tapped: two cards drift together with a haptic, then the other person's first name and photos appear.
2. The match screen: a photo carousel, their first name, and two choices, Find each other or Just chat, each with one line explaining it.
3. The choice route: save the choice through `set_choice`. Find needs a fresh location fix. When both pick Find, call C3's `startGlow`. Anything else opens the chat.
4. A waiting state with the 10-minute countdown and live updates. If time runs out, the chat opens.
5. The matches list: active and past.

**Done when.**

- [ ] Both Simulators show the reveal within 2 seconds of the second tap
- [ ] Every combination is tested: Find and Find, Find and Chat, Chat and Chat, and timeout
- [ ] Profile photos only load after the match exists (P1)

**Hand off.** The Routes into glow and chat, for C3 and C4.

## C3 · Glow mode

**Mission.** Help two people spot each other across a crowded room in seconds.

**Read first.** In the Technical spec: Product flow, Core rules and numbers (choosing and glow), Design system (glow colors and flash safety), Events and push.

**You own.** FeatureGlow, the GlowLiveActivity extension, `server/src/server/glow`, and the routes under `/api/matches/:id/glow`.

**Build.**

1. `startGlow`: call `start_glow` to pick a color, code word and meeting spot that no other active glow in the room is using, then send `glow.started` to both people.
2. A hand-picked list of 300 short, friendly code words in `server/src/server/glow/words.ts`. Nothing romantic, rude, or easy to mishear.
3. The glow screen: GlowSurface in the match color, the code word huge in SF Pro Rounded, the meeting spot, a hold your phone up hint, and a 15-minute countdown. Keep the screen awake, turn brightness up, and restore it afterwards.
4. A haptic pulse in time with the glow.
5. A Live Activity with the color, code word, meeting spot and countdown on the lock screen and in the Dynamic Island.
6. We met (counts when both tap it), Cancel, and Switch to chat, each with a clean ending.

**Done when.**

- [ ] Glow A and Glow B show the same color, code word and meeting spot
- [ ] A database test proves no two active glows in a room share a color and code word
- [ ] The Live Activity appears, counts down and ends on time in the Simulator
- [ ] The Reduce Motion version works, and brightness is always restored

**Hand off.** Notes for D3 on what to check on real devices: brightness, haptics and visibility in a bright hall.

## C4 · Chat

**Mission.** Give matched people a calm, safe place to talk if they don't meet right away.

**Read first.** In the Technical spec: Data model (messages), Events and push, Core rules and numbers. B8's hand-off notes on moderation and rate limits.

**You own.** FeatureChat, the routes `/api/matches/:id/messages` and `/api/matches/:id/unmatch`, and `server/src/server/chat`.

**Build.**

1. A thread with instant sending, sent and failed states, and live updates from `message.created`.
2. Messages of up to 1,000 characters, rate limited and moderated through B8.
3. A header menu with report, block and unmatch.
4. A push for new messages, with the generic lock screen text.
5. No scripted openers or AI suggestions. People write their own messages.

**Done when.**

- [ ] A message shows up on the other Simulator in under a second with the app open
- [ ] Someone blocked or unmatched can't send
- [ ] Unmatching removes the thread for both people

**Hand off.** Notes for D2 on how messages are moderated and stored.
