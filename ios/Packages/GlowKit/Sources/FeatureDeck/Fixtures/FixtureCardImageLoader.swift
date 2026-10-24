import AppCore
import DesignSystem
import SwiftUI
import UIKit

// Owner: C1. Draws a stand-in "today's look" for fixture cards: a faceless figure in the card's top
// color. Never a real photo. The deck draws the viewer's code over it, like it does over real ones.

struct FixtureCardImageLoader: CardImageLoading {
    /// Fail every load, to draw the failed tile state.
    var fails = false

    @MainActor
    func load(_ signedURL: String) async throws(CardImageFailure) -> UIImage {
        if fails {
            throw .failed
        }
        let top = URLComponents(string: signedURL)?.queryItems?.first { $0.name == "top" }?.value
        let swatch = top.flatMap(GlowSwatch.init(rawValue:)) ?? .gray
        let renderer = ImageRenderer(content: FixtureLook(swatch: swatch))
        renderer.scale = 2
        guard let image = renderer.uiImage else { throw .failed }
        return image
    }
}

/// The fixture look itself, 300 by 400 points.
struct FixtureLook: View {
    let swatch: GlowSwatch

    var body: some View {
        ZStack {
            LinearGradient(colors: [.glowSurfaceRaised, .glowSurface], startPoint: .top, endPoint: .bottom)
            Image(systemName: "figure.stand")
                .resizable()
                .scaledToFit()
                .padding(.vertical, 40)
                .foregroundStyle(swatch.rgb.color)
        }
        .frame(width: 300, height: 400)
    }
}
