import SwiftUI

// Owner: B6. A deck card: today's-look photo (already face-blurred and watermarked by the server),
// a slot for an on-device watermark, the outfit tags, and a "noticed" state. No faces, names or
// distances (spec).
//
//     GlowCardTile(phase: .ready, tags: card.tags.map(\.glowTag), isNoticed: tapped,
//                  accessibilityLabel: Text("Green hoodie, short brown hair, glasses")) {
//         CardImage(url: card.imageURL)          // C1's loader, no caching
//     } watermark: {
//         GlowWatermark(viewerCode)
//     }
//
// The photo is hidden while the screen is recorded or mirrored (`glowHiddenWhenCaptured`, P12).

public struct GlowCardTile<Photo: View, Watermark: View>: View {
    public enum Phase: String, CaseIterable, Sendable {
        case loading, ready, failed
    }

    private let phase: Phase
    private let tags: [GlowTag]
    private let isNoticed: Bool
    private let accessibilityLabel: Text
    private let photo: Photo
    private let watermark: Watermark

    public init(
        phase: Phase = .ready,
        tags: [GlowTag],
        isNoticed: Bool = false,
        accessibilityLabel: Text,
        @ViewBuilder photo: () -> Photo,
        @ViewBuilder watermark: () -> Watermark = { EmptyView() },
    ) {
        self.phase = phase
        self.tags = tags
        self.isNoticed = isNoticed
        self.accessibilityLabel = accessibilityLabel
        self.photo = photo()
        self.watermark = watermark()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: GlowRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Color.glowSurfaceRaised
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay { photoLayer }
                .overlay { watermark.allowsHitTesting(false).accessibilityHidden(true) }
                .clipped()
                .glowHiddenWhenCaptured()

            if !tags.isEmpty {
                GlowFlowLayout(spacing: GlowSpacing.xxs, rowSpacing: GlowSpacing.xxs) {
                    ForEach(tags, id: \.self) { tag in
                        GlowCardTagLabel(tag: tag)
                    }
                }
                .padding(GlowSpacing.sm)
                .accessibilityHidden(true)
            }
        }
        .background(.glowSurface)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(isNoticed ? AnyShapeStyle(.glowAccent) : AnyShapeStyle(.glowLine), lineWidth: isNoticed ? 2 : 1)
        }
        .overlay(alignment: .topTrailing) {
            if isNoticed {
                Label("Noticed", systemImage: "checkmark")
                    .glowFont(.caption)
                    .foregroundStyle(.glowOnAccent)
                    .padding(.horizontal, GlowSpacing.xs)
                    .padding(.vertical, GlowSpacing.xxs)
                    .background(.glowAccent, in: Capsule())
                    .padding(GlowSpacing.xs)
                    .accessibilityHidden(true)
            }
        }
        .glowAnimation(value: isNoticed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(phase == .failed ? Text("Photo didn't load") : isNoticed ? Text("Noticed") : Text(verbatim: ""))
        .accessibilityAddTraits(isNoticed ? .isSelected : [])
    }

    @ViewBuilder private var photoLayer: some View {
        switch phase {
        case .loading:
            ProgressView().tint(.glowTextSecondary)
        case .ready:
            photo
        case .failed:
            VStack(spacing: GlowSpacing.xs) {
                Image(systemName: "photo")
                    .font(.glow(.title))
                Text("Couldn't load this look")
                    .glowFont(.footnote)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.glowTextSecondary)
            .padding(GlowSpacing.md)
        }
    }
}

/// A small, quiet tag under a card photo.
struct GlowCardTagLabel: View {
    let tag: GlowTag

    var body: some View {
        HStack(spacing: GlowSpacing.xxs) {
            if let swatch = tag.swatch {
                GlowSwatchDot(swatch)
            }
            if let systemImage = tag.systemImage {
                Image(systemName: systemImage)
            }
            Text(verbatim: tag.title)
        }
        .glowFont(.caption)
        .foregroundStyle(.glowTextPrimary)
        .padding(.horizontal, GlowSpacing.xs)
        .padding(.vertical, GlowSpacing.xxs)
        .background(.glowSurfaceRaised, in: Capsule())
    }
}

/// A faint, repeated diagonal watermark of the viewer's code, so a leaked screenshot can be traced
/// (spec: viewer_code). Decorative: hidden from VoiceOver and never tappable.
public struct GlowWatermark: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Canvas { context, size in
            let label = context.resolve(
                Text(verbatim: text).font(.glow(.caption)).foregroundStyle(Color.white.opacity(0.14)),
            )
            let measured = label.measure(in: size)
            let step = CGSize(width: measured.width + 36, height: measured.height + 44)
            context.rotate(by: .degrees(-28))
            let reach = max(size.width, size.height) * 1.6
            var y = -reach
            var row = 0
            while y < reach {
                var x = -reach + (row.isMultiple(of: 2) ? 0 : step.width / 2)
                while x < reach {
                    context.draw(label, at: CGPoint(x: x, y: y))
                    x += step.width
                }
                y += step.height
                row += 1
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
