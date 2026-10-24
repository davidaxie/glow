# Wave 4 · Stretch

Only after Checkpoint 4 passes. Everything here needs real iPhones, because the Simulator has no Bluetooth or Ultra Wideband.

## E1 · Point to them with Ultra Wideband

**Mission.** After both people pick Find, show an arrow and a distance pointing at the other person, like finding an AirTag.

**Read first.** C3's brief and hand-off notes. Privacy invariant P1.

**You own.** A `Precision` folder inside FeatureGlow (agree the boundary with C3 first), and the route `/api/matches/:id/ni-token`.

**Build.**

1. A Nearby Interaction peer session between the two iPhones.
2. Exchange discovery tokens through the server, and only after both chose Find.
3. An arrow and distance on the glow screen, sitting above the color.
4. A quiet fallback to the plain glow on iPhones without Ultra Wideband.

**Done when.**

- [ ] The arrow works on two Ultra Wideband iPhones within 10 m
- [ ] A test proves no token is sent before both chose Find

## E2 · Nearby filter with Bluetooth

**Mission.** In a big room, shrink the deck to people within a few meters, while the app is open.

**Read first.** C1's brief. Build plan: Privacy invariants.

**You own.** A new GlowKit module, Proximity, and a `nearbyOnly` deck filter (a contract change, approved by A1).

**Build.**

1. CoreBluetooth advertising and scanning while the app is open.
2. Rotating identifiers: an HMAC of a per-check-in secret over 15-minute windows, which only the server can match to a check-in.
3. A Near me filter in the deck.
4. Nothing stored after the session ends.

**Done when.**

- [ ] Two iPhones see each other within about 5 m in under 10 seconds
- [ ] Identifiers from different windows can't be linked without the server

## E3 · Glow badge hardware

**Mission.** A wearable that glows when a mutual match is close, no phone needed.

**Read first.** The Hardware option section of the Geo-Lock PRD, and C3's brief.

**You own.** `hardware/badge/` (firmware), `server/src/server/badges`, and the routes under `/api/badges`.

**Build.**

1. Firmware for an ESP32-S3 with an LED ring (NimBLE): advertise a rotating ID and scan nonstop.
2. Every 30 seconds, fetch the badge's active match keys from the server over Wi-Fi or a phone hotspot.
3. Glow in the match's color when the signal strength shows the other badge is close.
4. A claim code on each badge to pair it with a person in the app.
5. For the demo, two badges set up ahead of time as a match.

**Done when.**

- [ ] Two paired badges light up within about 3 m of each other
- [ ] Badge IDs change every 15 minutes
