import SwiftUI

// Owner: B6. The Gallery's sections: every token, and every component in every state.

#if DEBUG

    // MARK: - Tokens

    struct GalleryColors: View {
        var body: some View {
            VStack(alignment: .leading, spacing: GlowSpacing.lg) {
                VStack(spacing: GlowSpacing.xs) {
                    ForEach(GlowPalette.tokens) { token in
                        GallerySwatchRow(name: token.name, rgb: token.rgb)
                    }
                }
                GalleryLabel("Glow colors and their ink")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: GlowSpacing.xs)], spacing: GlowSpacing.xs) {
                    ForEach(GlowHue.allCases) { hue in
                        VStack(alignment: .leading, spacing: GlowSpacing.xxs) {
                            Text(verbatim: hue.name).glowFont(.headline)
                            Text(verbatim: "\(hue.rgb.hex) · \(GalleryFormat.ratio(hue.ink, hue.rgb))")
                                .glowFont(.caption)
                        }
                        .foregroundStyle(hue.ink.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(GlowSpacing.sm)
                        .background(hue.color, in: RoundedRectangle(cornerRadius: GlowRadius.control, style: .continuous))
                    }
                }
                GalleryLabel("Tag swatches")
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 110), spacing: GlowSpacing.xs)],
                    alignment: .leading,
                    spacing: GlowSpacing.xs,
                ) {
                    ForEach(GlowSwatch.allCases) { swatch in
                        HStack(spacing: GlowSpacing.xs) {
                            GlowSwatchDot(swatch)
                            Text(verbatim: swatch.rawValue)
                                .glowFont(.footnote)
                                .foregroundStyle(.glowTextPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    struct GallerySwatchRow: View {
        let name: String
        let rgb: GlowRGB

        var body: some View {
            HStack(spacing: GlowSpacing.sm) {
                RoundedRectangle(cornerRadius: GlowRadius.control / 2, style: .continuous)
                    .fill(rgb.color)
                    .overlay {
                        RoundedRectangle(cornerRadius: GlowRadius.control / 2, style: .continuous)
                            .strokeBorder(.glowLine, lineWidth: 1)
                    }
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name).glowFont(.headline).foregroundStyle(.glowTextPrimary)
                    Text(verbatim: "\(rgb.hex) · on background \(GalleryFormat.ratio(rgb, GlowPalette.background))")
                        .glowFont(.footnote)
                        .foregroundStyle(.glowTextSecondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    enum GalleryFormat {
        static func ratio(_ foreground: GlowRGB, _ background: GlowRGB) -> String {
            String(format: "%.1f:1", GlowContrast.ratio(foreground, background))
        }
    }

    struct GalleryType: View {
        var body: some View {
            VStack(alignment: .leading, spacing: GlowSpacing.sm) {
                ForEach(GlowTextStyle.allCases) { style in
                    VStack(alignment: .leading, spacing: 2) {
                        GalleryLabel(style.rawValue)
                        Text(verbatim: style == .code ? "HK26XY" : style == .codeWord ? "lantern" : "Someone you noticed noticed you back.")
                            .glowFont(style)
                            .foregroundStyle(.glowTextPrimary)
                    }
                }
            }
        }
    }

    struct GallerySpacing: View {
        var body: some View {
            VStack(alignment: .leading, spacing: GlowSpacing.md) {
                ForEach(GlowSpacing.scale, id: \.name) { step in
                    HStack(spacing: GlowSpacing.sm) {
                        Text(verbatim: "\(step.name) \(Int(step.value))")
                            .glowFont(.footnote)
                            .foregroundStyle(.glowTextSecondary)
                            .frame(minWidth: 64, alignment: .leading)
                        Rectangle().fill(.glowAccent).frame(width: step.value, height: 12)
                    }
                }
                HStack(spacing: GlowSpacing.md) {
                    VStack(spacing: GlowSpacing.xxs) {
                        RoundedRectangle(cornerRadius: GlowRadius.control, style: .continuous)
                            .fill(.glowSurfaceRaised).frame(width: 64, height: 44)
                        GalleryLabel("Control 12")
                    }
                    VStack(spacing: GlowSpacing.xxs) {
                        RoundedRectangle(cornerRadius: GlowRadius.card, style: .continuous)
                            .fill(.glowSurface).frame(width: 64, height: 80)
                        GalleryLabel("Card 20")
                    }
                    VStack(spacing: GlowSpacing.xxs) {
                        Capsule().fill(.glowSurfaceRaised).frame(width: 64, height: 32)
                        GalleryLabel("Chip")
                    }
                }
            }
        }
    }

    // MARK: - Components

    struct GalleryButtons: View {
        var body: some View {
            VStack(alignment: .leading, spacing: GlowSpacing.lg) {
                ForEach(GlowButtonKind.allCases) { kind in
                    VStack(alignment: .leading, spacing: GlowSpacing.xs) {
                        GalleryLabel(kind.rawValue)
                        Button(kind == .danger ? "Block" : "Check in") {}
                            .buttonStyle(.glow(kind))
                        GlowButtonBody(label: Text(verbatim: "Pressed"), isPressed: true, kind: kind, size: .large)
                        Button("Loading") {}
                            .buttonStyle(.glow(kind))
                            .glowLoading(true)
                        Button("Disabled") {}
                            .buttonStyle(.glow(kind))
                            .disabled(true)
                        GlowFlowLayout {
                            Button("Compact") {}
                                .buttonStyle(.glow(kind, size: .compact))
                            Button {} label: {
                                Label("With icon", systemImage: "qrcode.viewfinder")
                            }
                            .buttonStyle(.glow(kind, size: .compact))
                        }
                    }
                }
            }
        }
    }

    struct GalleryChips: View {
        @State private var picked: Set<String> = ["Glasses"]

        var body: some View {
            VStack(alignment: .leading, spacing: GlowSpacing.sm) {
                GalleryLabel("Off, on, pressed, disabled")
                GlowFlowLayout {
                    GlowChip("Hat", isSelected: false) {}
                    GlowChip("Glasses", isSelected: true) {}
                    GlowChipBody(label: Text(verbatim: "Pressed"), isSelected: false, isPressed: true)
                    GlowChip("Beard", isSelected: false) {}.disabled(true)
                }
                GalleryLabel("With a swatch or an icon")
                GlowFlowLayout {
                    GlowChip("Green", swatch: .green, isSelected: true) {}
                    GlowChip("Black", swatch: .black, isSelected: false) {}
                    GlowChip("Headphones", systemImage: "headphones", isSelected: picked.contains("Headphones")) {
                        if picked.remove("Headphones") == nil {
                            picked.insert("Headphones")
                        }
                    }
                }
            }
        }
    }

    struct GallerySheets: View {
        @State private var isPresented = false

        var body: some View {
            VStack(alignment: .leading, spacing: GlowSpacing.md) {
                GalleryLabel("Tap confirmation")
                GlowSheetPreviewFrame {
                    GlowSheetContent(
                        title: "Tap this card?",
                        message: "They won't know unless they tap you too.",
                        systemImage: "hand.tap.fill",
                    ) {
                        Button("Tap") {}.buttonStyle(.glowPrimary)
                        Button("Not now") {}.buttonStyle(.glowQuiet)
                    }
                }
                GalleryLabel("Danger")
                GlowSheetPreviewFrame {
                    GlowSheetContent(
                        title: "Block this person?",
                        message: "They won't see you again, here or anywhere in Glow.",
                        systemImage: "hand.raised.fill",
                        tint: GlowPalette.danger,
                    ) {
                        Button("Block") {}.buttonStyle(.glowDanger)
                        Button("Cancel") {}.buttonStyle(.glowQuiet)
                    }
                }
                Button("Present a sheet") { isPresented = true }
                    .buttonStyle(.glowSecondary)
                    .glowSheet(isPresented: $isPresented) {
                        GlowSheetContent(
                            title: "Tap this card?",
                            message: "They won't know unless they tap you too.",
                            systemImage: "hand.tap.fill",
                        ) {
                            Button("Tap") { isPresented = false }.buttonStyle(.glowPrimary)
                            Button("Not now") { isPresented = false }.buttonStyle(.glowQuiet)
                        }
                    }
            }
        }
    }

    struct GalleryToasts: View {
        @State private var toast: GlowToastMessage?

        var body: some View {
            VStack(alignment: .leading, spacing: GlowSpacing.sm) {
                GlowToast(GlowToastMessage("Your check-in ends soon.", kind: .info))
                GlowToast(GlowToastMessage("Done. They won't see you again.", kind: .success))
                GlowToast(GlowToastMessage("Looks like you're not in this room yet. Try again inside.", kind: .error))
                GlowFlowLayout {
                    ForEach(GlowToastMessage.Kind.allCases, id: \.self) { kind in
                        Button(kind.rawValue.capitalized) {
                            toast = GlowToastMessage("A \(kind.rawValue) toast", kind: kind)
                        }
                        .buttonStyle(.glow(.secondary, size: .compact))
                    }
                }
            }
            .glowToast($toast)
        }
    }

    struct GalleryStepHeaders: View {
        var body: some View {
            VStack(alignment: .leading, spacing: GlowSpacing.xl) {
                GlowStepHeader(step: 1, of: 4, title: "What's your first name?", subtitle: "It's only shown to your matches.")
                GlowStepHeader(step: 3, of: 4, title: "Add your photos")
                GlowStepHeader(step: 4, of: 4, title: "Turn on notifications", subtitle: "So you know the moment it's mutual.")
            }
        }
    }

    struct GalleryEmptyStates: View {
        var body: some View {
            VStack(spacing: GlowSpacing.md) {
                GlowEmptyState(systemImage: "sparkles", title: "Nobody fits that yet.", message: "Try fewer details.") {
                    Button("Change what you noticed") {}.buttonStyle(.glowSecondary)
                }
                .background(.glowSurface, in: RoundedRectangle(cornerRadius: GlowRadius.card, style: .continuous))
                GlowEmptyState(systemImage: "heart", title: "No matches yet.", message: "When it's mutual, they'll show up here.")
                    .background(.glowSurface, in: RoundedRectangle(cornerRadius: GlowRadius.card, style: .continuous))
            }
        }
    }

#endif
