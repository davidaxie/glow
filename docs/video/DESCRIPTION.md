# Demo video: YouTube and Devpost

The upload file is `glow-demo.mp4` (1:45, 1920x1080, 30 fps, H.264 with AAC, about 20 MB), with a poster frame (`glow-demo-poster.png`) and a 3:2 thumbnail for Devpost (`glow-thumb-3x2.png`). They are rendered, not committed; rebuild them with the steps at the bottom.

## Title

Glow: find out, privately, that you noticed each other (Cal Hacks 13.0)

## Description

You notice someone across the room. You never find out if they noticed you too.

Glow is a native iPhone app with two modes on one account.

Rooms: check in to a room (a class, a party, this hackathon) by scanning its QR code. You see "today's look" cards of the other people there: outfits only, faces blurred on the phone, no names. Tap the one you noticed. They aren't told. If they tapped you too, both phones light up at the same moment, and if you both choose Find each other, both screens glow the same color with the same code word, so you can find each other across a loud room.

Blind: swipe on photos only. Mutual likes stay hidden until the nightly drop, when they open as chats behind codenames. Glow warns you before you send something that would give you away, and Reveal only happens when you both tap it. Then the veil lifts.

Every screen in this video was recorded from the real app running in the iOS Simulator, on its built-in demo data (made-up people and portraits, no real users).

Chapters:
0:00 The problem
0:11 Rooms: check in, today's looks, a one-sided tap
0:29 It's mutual, and the glow
0:49 Blind: swipe on photos only
1:01 The drop and a blind chat
1:18 Reveal: waiting, then the veil lifts

Built at Cal Hacks 13.0 by David Xie and Robin Dao.
Built with Swift, SwiftUI, Next.js, TypeScript, Supabase and Claude.

## Shot list

| Time | Shot | Source (real app, iOS Simulator) |
| --- | --- | --- |
| 0:00 | "You notice someone across the room. You never find out if they noticed you too." | Title card |
| 0:06 | Glow, "Notice someone. Find out if it's mutual." | Title card (the app's own welcome line) |
| 0:11 | Mode one: Rooms | Chapter card |
| 0:14 | Checked in to the room | `-GlowDebugDeckFixture normal -GlowDebugRoute room/<id>` |
| 0:19 | What did you notice, today's looks, open a look, Tap, "Noted. Only you know." | `-GlowDebugDeckAutoplay tap` on the fixture room |
| 0:29 | Both phones: "Someone you noticed noticed you back." | Glow A and Glow B, `-GlowMatchFixtures reveal` |
| 0:34 | Find each other, waiting for them to choose | Glow A, `-GlowMatchFixturesChoose find` |
| 0:40 | Both phones glow aqua, code word LANTERN, meet at Water station | Glow A and Glow B, `-GlowGlowFixtures aqua` |
| 0:49 | Mode two: Blind | Chapter card |
| 0:52 | Photo-only deck: like, love, pass | `DemoVideoUITests.testDemo1BlindDeckSwipes` |
| 1:01 | The drop: codename cards turn over (Fox, Comet, Otter) | `-GlowDebugBlind dropReady -GlowDebugBlindAutoOpen YES` |
| 1:08 | Blind chat: typing a handle brings up "This might give you away." | `DemoVideoUITests.testDemo2BlindGiveAwayAndWaiting` |
| 1:18 | One-sided Reveal: "Waiting for them" | same test |
| 1:26 | Both tapped Reveal: the veil lifts, Jordan (was Fox) | `DemoVideoUITests.testDemo3BlindMutualReveal` |
| 1:37 | Glow, the tagline, credits, "Every screen recorded from the real app in the iOS Simulator" | End card |

A small "Recorded in the iOS Simulator" line sits under every phone shot. The soundtrack is synthesized by `scripts/video/render.py` (a warm pad, Dmaj9 for Rooms and Bm9 for Blind, plus soft chimes on the one-sided tap, the mutual moment, the glow, the drop and the reveal); no music or downloaded sounds.

## Rebuild

```
export GLOW_SIM_A='Glow A (V1)' GLOW_SIM_B='Glow B (V1)' MAC_SLOTS_SIM=5
scripts/sim.sh setup both && scripts/sim.sh build && scripts/sim.sh install both
python3 scripts/video/capture.py <raw>          # Rooms, the glow, the drop (simctl recordVideo)
python3 scripts/video/ui-capture.py <raw>       # Blind's tapped moments (XCUITest, recorded)
python3 scripts/video/render.py <raw> <work> glow-demo.mp4
python3 scripts/video/poster.py glow-demo.mp4 <out dir> 45
python3 scripts/video/sheet.py <dir> 2 320 glow-demo.mp4   # contact sheets for review
scripts/sim.sh release && scripts/sim.sh teardown
```

The cut points in `render.py` are seconds into these particular recordings; a new capture needs them checked against a contact sheet.
