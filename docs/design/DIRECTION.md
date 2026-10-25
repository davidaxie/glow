# Design direction: light as the language

David's brief (2026-10-25): completely revamp the UI, UX and animation so the app is innovative, pristine and elegant. It should feel like a funded startup shipped it, warm and low-pressure, never like a generic dating app. This document is the shared vision for every design agent (U1, U2, U3, and X2/U4 for Blind mode). Concrete numbers here are the contract between agents: use them, so the app feels like one hand made it.

## The idea

The product is named after light, and the wow moment is two phones glowing the same color. So light is the design language. Everything is a quiet, warm dark room, and meaning arrives as light: a soft bloom when something matters, a slow breath when something is waiting, a full glow only at the mutual moment. Nothing shouts. Nothing bounces for fun. Elegance comes from restraint, exact spacing, beautiful type and motion that feels physical.

Blind mode shares the same room but adds one motif: **the veil**. Before reveal, people exist as frosted, soft, out-of-focus light with a codename. Reveal is the veil lifting.

## Visual system

- **Canvas:** a warm near-black, never pure #000 (around #0B0A0F), with a very subtle vertical gradient and a faint film grain (2 to 3 percent) on full-screen surfaces so blacks feel rich, not flat.
- **Light:** one signature accent family (keep Glow's existing glow palette, the shared color comes from the match), used sparingly: primary actions, the active state, and the moments. Secondary text is warm grey, not blue grey.
- **Surfaces:** layered glass. Cards and sheets are slightly lifted surfaces with a 1 px inner highlight on the top edge and soft shadow, large continuous corner radii (24 to 32 for cards, 20 for sheets' top corners, full capsules for buttons).
- **Type:** an editorial pairing. Display moments (codenames, the code word, names at reveal, big empty-state lines) use the system serif, New York (`.serif` design), in regular or semibold, tight tracking. Everything else is SF Pro (text) with Dynamic Type. Numbers that change (countdown, counters) use monospaced digits and `contentTransition(.numericText())`.
- **Spacing:** a 4 pt grid, generous margins (20 to 24 pt), never cramped. One primary action per screen, at the bottom, in the thumb zone.
- **Iconography:** SF Symbols, thin to regular weight, with symbol effects (`.symbolEffect`) only where meaningful.

## Motion system (use these exact values)

- **Springs only for UI movement.** `Motion.snappy` = `.spring(response: 0.35, dampingFraction: 0.86)`, `Motion.smooth` = `.spring(response: 0.5, dampingFraction: 0.9)`, `Motion.gentle` = `.spring(response: 0.8, dampingFraction: 0.95)`. No default linear or easeInOut for movement; opacity-only fades may use `.easeOut(duration: 0.25)`.
- **Stagger:** 40 ms between items in a list or a set of cards appearing.
- **Breathing:** waiting states breathe at a resting heart rate, a 4 s cycle (scale 1.0 to 1.03, glow opacity 0.6 to 1.0), never a spinner where a breath will do.
- **Bloom:** important arrivals bloom: a radial light from the point of interaction, 600 ms, then settle.
- **Matched geometry** between related screens (a deck card into its detail, a chat row into its chat, a codename into the reveal) so the app feels continuous.
- **Reduce Motion:** every animation has a calm crossfade alternative. Respect it everywhere.
- **Performance:** 120 Hz smooth. Prefer `TimelineView`, `Canvas`, `MeshGradient` (iOS 18 where available, gradient fallback on 17), `.visualEffect` and shaders only where they earn it. Never drop frames on the stage path.

## Haptics and sound

- Haptics are choreographed with motion, never random: light tick on selection, soft impact when a card leaves, a two-beat "heartbeat" (two soft impacts 120 ms apart) at the mutual moment, success notification at reveal.
- Sound (new): three tiny, warm, synthesized sounds, generated in code or by a script in the repo (no downloaded assets): a soft chime for a mutual tap, a low airy swell for the glow and for a reveal, a faint tick for a sent message. They respect the silent switch and a Settings toggle. Off is always fine; never required to understand anything.

## Signature moments (the demo lives here)

1. **Mutual tap to glow (Rooms).** Both phones: the heartbeat haptic, then the screen fills with the shared color as a bloom from the center, breathing slowly; the code word set large in New York; the meeting spot below; brightness up. This is the single most important animation in the app.
2. **One-sided tap.** A quiet acknowledgement only on the tapper's screen (a soft ripple through the card and "Noted. Only you know."), then it settles. Never anything on the other phone.
3. **Joining a room.** The room "warms up": a soft light gathers as you check in; the deck arrives with a staggered rise.
4. **Blind drop.** Codename cards arrive face down as frosted glass and turn over one by one (staggered), each codename shimmering once in New York italic.
5. **Blind reveal.** The veil lifts: blur and frost dissolve from the center outward over about 1.2 s, the name typesets in, both photos settle side by side, heartbeat haptic.
6. **Empty and waiting states** feel intentional and warm (a breathing light and one honest sentence), never a blank screen or a bare spinner.

## Rules for every design agent

- Do not change behaviour, data flow, API calls or privacy rules (Glow's P1 to P12, Blind's B1 to B12). This is presentation and motion only. If a flow is confusing, you may change layout and copy; note it in `docs/design/CHANGES.md`.
- Keep existing public DesignSystem names working (add new tokens and components; do not rename or delete ones other modules use).
- Use Glow's fixtures and debug routes to reach every screen on a headless Simulator. Before and after screenshots for every screen you touch go in `docs/shots/design/<id>/`, and you must look at them with the Read tool and judge them like a top design studio would. Record a short screen recording of each signature moment you own.
- Accessibility: contrast at least 4.5:1 for text, Dynamic Type up to XXL without clipping, VoiceOver labels, Reduce Motion.
