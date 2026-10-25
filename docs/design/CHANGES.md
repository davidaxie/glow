# Design changes to layout and copy

Presentation only. Behaviour, data flow, API calls and privacy rules are unchanged (DIRECTION.md, "Rules for every design agent"). Each agent adds its own section.

## U1 · Foundation, shell, onboarding, settings

- **Welcome**: the sparkles icon became a breathing light; "Glow" is now a New York wordmark (`GlowWordmark`); a new one-line subtitle, "Notice someone. Find out if it's mutual."; the three promise lines are unchanged, now with glass icon wells, rising in one by one (40 ms stagger). The 18+ line and Get started are unchanged.
- **Onboarding screens**: on the canvas with a faint accent light at the top, 24 pt margins, the actions float in the thumb zone over a soft fade instead of a solid bar.
- **Settings**: a new **Sound** section with a "Sounds" toggle (on by default) and the footer "A soft chime when it's mutual, a swell when the glow arrives. Your silent switch turns them off too." Rows sit on glass, the screen on the canvas.
- **Shell**: the tab bar keeps the system bar, tinted with the accent; every tab's stack and pushed screen sits on the canvas (iOS 18 and later); the launch color is the canvas `#0B0A0F`, and while the session resolves a breathing light shows instead of a flat color.
- **Everywhere, through DesignSystem**: warm neutrals (U1-D1), capsule buttons with a soft light under filled ones, `.display` and the code word in New York, empty states breathe and title in New York.

# Design changes: layout and copy

Each design agent notes here any layout or copy change that goes beyond restyling (DIRECTION.md, "Rules for every design agent"). Behaviour, data flow and privacy rules are unchanged.

## U3 · The mutual moment, the glow and the chat

- **Mutual moment (FeatureMatch).** The two drifting cards are now two points of light that meet in the middle with U1's `GlowMoment.mutual` (two-beat heartbeat and chime) and a 600 ms bloom; the headline is set in New York with an "It's mutual" overline. The light then rises behind the name. The match details gain the same overline above the existing headline. The takeover uses its own stage (warm dark room, one light, a glass Close button) instead of DesignSystem's `GlowTakeover`, so the light can be continuous from the intro into the details. Copy kept word for word, including "Someone you noticed noticed you back." (D1's UI tests and the push-tap test look for it).
- **Waiting.** The countdown sits on a breathing light (4 s, scale 1.0 to 1.03) instead of an accent-colored number; the panel and photos use 28 pt continuous corners with a top-edge highlight. A loading match breathes instead of spinning.
- **Glow (FeatureGlow).** The shared color blooms from the middle of the screen (U1's `Motion.gentle`), with one soft white light at its heart, then the words rise in a 40 ms stagger; U1's `GlowMoment.glowArrives` plays the swell. The code word is set in New York capitals (was SF Pro Rounded heavy). "Meet at {spot}" is split into a "Meet at" overline and the spot in New York, on frosted glass (white over the color, so ink contrast only goes up). The say-aloud lines are quotes in New York italic separated by hairlines instead of outlined pills. "We met" is a capsule. The countdown and hide button sit on frosted capsules.
- **Chat (FeatureChat).** The empty state is replaced by a header that stays at the top of every thread: a small breathing light, "You and {name}" in New York, "Matched in {room}", and the two existing lines ("It's just the two of you here." / "Nobody else can read this chat."). Bubbles have 22 pt corners that tighten to 8 where a run joins; new messages land with `Motion.snappy`. The send button is a filled circle; the composer bar is frosted.
- **Not yet touched:** the block and report sheets (FeatureSafety), the matches list, the glow ended and unavailable states, and the Live Activity.
- **Debug only:** `-GlowGlowFixtures <color>` and `-GlowChatFixtures thread|empty` show made-up data on the glow and chat screens without a server, for screenshots and recordings (compiled out of Release, like `-GlowMatchFixtures`).
