import AppCore
import DesignSystem
import SwiftUI
import UIKit

// Owner: C1. Draws a stand-in "today's look" for fixture cards: a faceless figure in the card's top
// color, with a faint repeated viewer code like the server's watermark. Never a real photo.

struct FixtureCardImageLoader: CardImageLoading {
    /// The code the server would print in the watermark (the preview person's `viewerCode`).
    var viewerCode = "YTVFCREQ"
    /// Fail every load, to draw the failed tile state.
    var fails = false

    @MainActor
    func load(_ signedURL: String) async throws(CardImageFailure) -> UIImage {
        if fails {
            throw .failed
        }
        let top = URLComponents(string: signedURL)?.queryItems?.first { $0.name == "top" }?.value
        let swatch = top.flatMap(GlowSwatch.init(rawValue:)) ?? .gray
        let renderer = ImageRenderer(content: FixtureLook(swatch: swatch, viewerCode: viewerCode))
        renderer.scale = 2
        guard let image = renderer.uiImage else { throw .failed }
        return image
    }
}

/// The fixture look itself, 300 by 400 points.
struct FixtureLook: View {
    let swatch: GlowSwatch
    let viewerCode: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [.glowSurfaceRaised, .glowSurface], startPoint: .top, endPoint: .bottom)
            Image(systemName: "figure.stand")
                .resizable()
                .scaledToFit()
                .padding(.vertical, 40)
                .foregroundStyle(swatch.rgb.color)
            FixtureWatermark(text: viewerCode)
        }
        .frame(width: 300, height: 400)
    }
}

/// A faint diagonal watermark, drawn the way the server draws its own (spec: viewer code).
struct FixtureWatermark: View {
    let text: String

    var body: some View {
        Canvas { context, size in
            let label = context.resolve(Text(verbatim: text).font(.glow(.caption)).foregroundStyle(.glowTextPrimary.opacity(0.18)))
            let measured = label.measure(in: size)
            let step = CGSize(width: measured.width + 30, height: measured.height + 36)
            context.rotate(by: .degrees(-28))
            let reach = max(size.width, size.height) * 1.6
            var row = 0
            var y = -reach
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
