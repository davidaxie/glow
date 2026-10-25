# Design changes to layout and copy

Presentation only. Behaviour, data flow, API calls and privacy rules are unchanged (DIRECTION.md, "Rules for every design agent"). Each agent adds its own section.

## U1 · Foundation, shell, onboarding, settings

- **Welcome**: the sparkles icon became a breathing light; "Glow" is now a New York wordmark (`GlowWordmark`); a new one-line subtitle, "Notice someone. Find out if it's mutual."; the three promise lines are unchanged, now with glass icon wells, rising in one by one (40 ms stagger). The 18+ line and Get started are unchanged.
- **Onboarding screens**: on the canvas with a faint accent light at the top, 24 pt margins, the actions float in the thumb zone over a soft fade instead of a solid bar.
- **Settings**: a new **Sound** section with a "Sounds" toggle (on by default) and the footer "A soft chime when it's mutual, a swell when the glow arrives. Your silent switch turns them off too." Rows sit on glass, the screen on the canvas.
- **Shell**: the tab bar keeps the system bar, tinted with the accent; every tab's stack and pushed screen sits on the canvas (iOS 18 and later); the launch color is the canvas `#0B0A0F`, and while the session resolves a breathing light shows instead of a flat color.
- **Everywhere, through DesignSystem**: warm neutrals (U1-D1), capsule buttons with a soft light under filled ones, `.display` and the code word in New York, empty states breathe and title in New York.
