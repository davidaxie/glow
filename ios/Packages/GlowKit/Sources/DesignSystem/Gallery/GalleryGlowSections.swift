import SwiftUI

// Owner: B6. Gallery sections for the tag picker, card tile, code fields, takeover, glow surface
// and haptics. Static samples hold still (no pulse, no entrance) so snapshots are repeatable; the
// buttons open the live versions.

#if DEBUG

    // MARK: - Tag picker

    enum GalleryTop: String, CaseIterable {
        case black, white, gray, red, pink, orange, yellow, green, blue, purple

        var tag: GlowTag {
            GlowTag(rawValue.capitalized, swatch: GlowSwatch(rawValue: rawValue))
        }
    }

    enum GalleryExtra: String, CaseIterable {
        case glasses, hat, beard, headphones, backpack

        var tag: GlowTag {
            let symbols = [
                "glasses": "eyeglasses",
                "hat": "hat.cap",
                "beard": "mustache",
                "headphones": "headphones",
                "backpack": "backpack",
            ]
            return GlowTag(rawValue.capitalized, systemImage: symbols[rawValue])
        }
    }

    struct GalleryTagPickers: View {
        @State private var top: GalleryTop? = .green
        @State private var extras: Set<GalleryExtra> = [.glasses, .headphones]
        @State private var hair: GlowSwatch?

        var body: some View {
            VStack(alignment: .leading, spacing: GlowSpacing.lg) {
                GlowTagPicker("Top color", options: GalleryTop.allCases, selection: $top) { $0.tag }
                GlowTagPicker("Extras, up to 2", options: GalleryExtra.allCases, selection: $extras, limit: 2) { $0.tag }
                GlowTagPicker(
                    "Hair color (optional)",
                    options: [GlowSwatch.black, .brown, .blonde, .red, .gray, .dyed],
                    selection: $hair,
                    allowsNone: true,
                ) { GlowTag($0.rawValue.capitalized, swatch: $0) }
            }
        }
    }

    // MARK: - Card tile

    /// A stand-in for a card photo: a faceless figure on a soft gradient. No real person.
    struct GalleryOutfitPhoto: View {
        let swatch: GlowSwatch

        var body: some View {
            ZStack {
                LinearGradient(colors: [swatch.rgb.color.opacity(0.55), .glowSurfaceRaised], startPoint: .top, endPoint: .bottom)
                Image(systemName: "figure.stand")
                    .resizable()
                    .scaledToFit()
                    .padding(GlowSpacing.lg)
                    .foregroundStyle(swatch.rgb.color)
            }
        }
    }

    struct GalleryCardTiles: View {
        private let tags = [GlowTag("Green", swatch: .green), GlowTag("Short brown hair"), GlowTag("Glasses", systemImage: "eyeglasses")]
        private let label = Text(verbatim: "Green top, short brown hair, glasses")

        var body: some View {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: GlowSpacing.sm, alignment: .top)], spacing: GlowSpacing.md) {
                sample("Ready, with watermark") {
                    GlowCardTile(phase: .ready, tags: tags, accessibilityLabel: label) {
                        GalleryOutfitPhoto(swatch: .green)
                    } watermark: {
                        GlowWatermark("V7K2Q")
                    }
                }
                sample("Noticed") {
                    GlowCardTile(phase: .ready, tags: tags, isNoticed: true, accessibilityLabel: label) {
                        GalleryOutfitPhoto(swatch: .blue)
                    }
                }
                sample("Loading") {
                    GlowCardTile(phase: .loading, tags: tags, accessibilityLabel: label) { EmptyView() }
                }
                sample("Failed") {
                    GlowCardTile(phase: .failed, tags: tags, accessibilityLabel: label) { EmptyView() }
                }
                sample("Screen being recorded") {
                    GlowCardTile(phase: .ready, tags: tags, accessibilityLabel: label) {
                        GalleryOutfitPhoto(swatch: .red)
                    }
                    .environment(\.isSceneCaptured, true)
                }
            }
        }

        private func sample(_ title: String, @ViewBuilder content: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: GlowSpacing.xs) {
                GalleryLabel(title)
                content()
            }
        }
    }

    // MARK: - Code fields

    struct GalleryCodeFields: View {
        @State private var empty = ""
        @State private var partial = "HK2"
        @State private var full = "HACK26"
        @State private var wrong = "ABCDEF"
        @State private var digits = "4821"

        var body: some View {
            VStack(alignment: .leading, spacing: GlowSpacing.md) {
                GalleryLabel("Room code, empty")
                GlowCodeField("Room code", code: $empty, length: 6, format: .roomCode)
                GalleryLabel("Room code, part typed")
                GlowCodeField("Room code", code: $partial, length: 6, format: .roomCode)
                GalleryLabel("Room code, full")
                GlowCodeField("Room code", code: $full, length: 6, format: .roomCode)
                GalleryLabel("Error")
                GlowCodeField("Room code", code: $wrong, length: 6, format: .roomCode, error: "That code didn't match a room.")
                GalleryLabel("Email code")
                GlowCodeField("Code from your email", code: $digits, length: 6, format: .digits)
                GalleryLabel("Disabled")
                GlowCodeField("Room code", code: $full, length: 6, format: .roomCode).disabled(true)
                GalleryLabel("Box states")
                HStack(spacing: GlowSpacing.xs) {
                    GlowCodeBox(character: "A", state: .idle, height: 56)
                    GlowCodeBox(character: nil, state: .current, height: 56)
                    GlowCodeBox(character: "Z", state: .error, height: 56)
                }
            }
        }
    }

    // MARK: - Takeover

    struct GalleryTakeovers: View {
        @State private var isShowing = false
        private let samples: [(name: String, backdrop: GlowBackdrop)] = [
            ("Bloom (the mutual moment)", .bloom), ("Night", .night), ("Glow color (Aqua)", .hue(.aqua)),
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: GlowSpacing.md) {
                ForEach(samples, id: \.name) { sample in
                    GalleryLabel(sample.name)
                    GlowTakeover(sample.backdrop, startsRevealed: true) {
                        GalleryMutualMoment(onGlow: sample.backdrop != .bloom && sample.backdrop != .night)
                    } onClose: {}
                        .frame(height: 380)
                        .clipShape(RoundedRectangle(cornerRadius: GlowRadius.card, style: .continuous))
                }
                Button("Show the takeover") { isShowing = true }
                    .buttonStyle(.glowSecondary)
            }
            .fullScreenCover(isPresented: $isShowing) {
                GlowTakeover(.bloom) {
                    GalleryMutualMoment()
                } onClose: {
                    isShowing = false
                }
            }
        }
    }

    struct GalleryMutualMoment: View {
        var onGlow = false

        var body: some View {
            VStack(spacing: GlowSpacing.lg) {
                Spacer(minLength: 0)
                Text(verbatim: "Someone you noticed noticed you back.")
                    .glowFont(.display)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                if onGlow {
                    Button("See who") {}.buttonStyle(.glowOnSurface)
                } else {
                    Button("See who") {}.buttonStyle(.glowPrimary)
                }
            }
        }
    }

    // MARK: - Glow surface

    struct GalleryGlowSurfaces: View {
        @State private var live: GlowHue?

        var body: some View {
            VStack(alignment: .leading, spacing: GlowSpacing.md) {
                GalleryLabel("At rest, every color")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: GlowSpacing.xs)], spacing: GlowSpacing.xs) {
                    ForEach(GlowHue.allCases) { hue in
                        GlowSurface(hue, isPulsing: false, controlsScreen: false) {
                            VStack(spacing: GlowSpacing.xxs) {
                                GlowCodeWord("lantern")
                                Text(verbatim: hue.name).glowFont(.footnote)
                            }
                            .padding(GlowSpacing.sm)
                        }
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: GlowRadius.control, style: .continuous))
                    }
                }
                GalleryLabel("A button on a glow")
                GlowSurface(.violet, isPulsing: false, controlsScreen: false) {
                    Button("We met") {}.buttonStyle(.glowOnSurface).padding(GlowSpacing.md)
                }
                .frame(height: 96)
                .clipShape(RoundedRectangle(cornerRadius: GlowRadius.control, style: .continuous))
                Button("Open a live glow") { live = .aqua }
                    .buttonStyle(.glowSecondary)
            }
            .fullScreenCover(item: $live) { hue in
                GalleryLiveGlow(hue: hue) { live = nil }
            }
        }
    }

    /// The real thing: pulsing, full brightness, screen kept awake. Tap a dot to change color.
    struct GalleryLiveGlow: View {
        @State private var hue: GlowHue
        let close: () -> Void

        init(hue: GlowHue, close: @escaping () -> Void) {
            _hue = State(initialValue: hue)
            self.close = close
        }

        var body: some View {
            GlowSurface(hue) {
                VStack(spacing: GlowSpacing.lg) {
                    Spacer()
                    GlowCodeWord("lantern")
                    Text(verbatim: "Meet at the food line").glowFont(.headline)
                    Spacer()
                    HStack(spacing: GlowSpacing.xs) {
                        ForEach(GlowHue.allCases) { option in
                            Button { hue = option } label: {
                                Circle()
                                    .fill(option.color)
                                    .overlay(Circle().strokeBorder(option.ink.color, lineWidth: option == hue ? 3 : 1))
                                    .frame(width: 32, height: 32)
                            }
                            .accessibilityLabel(Text(verbatim: option.name))
                            .accessibilityAddTraits(option == hue ? .isSelected : [])
                        }
                    }
                    Button("Close", action: close).buttonStyle(.glowOnSurface)
                }
                .padding(GlowSpacing.screenMargin)
            }
        }
    }

    // MARK: - Haptics

    struct GalleryHaptics: View {
        @State private var taps = 0
        @State private var successes = 0
        @State private var mutuals = 0

        var body: some View {
            VStack(alignment: .leading, spacing: GlowSpacing.sm) {
                Text(verbatim: GlowHaptics
                    .isSupported ? "Tap to feel each one." : "This device can't play haptics (the Simulator never can).")
                    .glowFont(.callout)
                    .foregroundStyle(.glowTextSecondary)
                GlowFlowLayout {
                    Button("Light tap") { taps += 1 }
                        .buttonStyle(.glow(.secondary, size: .compact))
                        .glowHaptic(.lightTap, trigger: taps)
                    Button("Success") { successes += 1 }
                        .buttonStyle(.glow(.secondary, size: .compact))
                        .glowHaptic(.success, trigger: successes)
                    Button("Mutual") { mutuals += 1 }
                        .buttonStyle(.glow(.secondary, size: .compact))
                        .glowHaptic(.mutual, trigger: mutuals)
                    Button("Glow pulse") { GlowHaptics.shared.play(.glowPulse) }
                        .buttonStyle(.glow(.secondary, size: .compact))
                }
            }
        }
    }

#endif
