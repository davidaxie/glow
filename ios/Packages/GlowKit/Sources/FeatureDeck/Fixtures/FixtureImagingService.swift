import AppCore
import DesignSystem
import Foundation
import SwiftUI
import UIKit

// Owner: C1. Card photos for fixture rooms: a faceless figure in the card's top color, drawn on the
// phone. Never a real photo, never the network. Used by previews, snapshot tests and Debug launches
// with `-GlowDebugDeckFixture`; the deck draws the viewer's code over it like over real ones.

struct FixtureImagingService: ImagingService {
    func prepareCardPhoto(from _: Data) async throws -> PreparedCardPhoto {
        throw ImagingError.processingFailed
    }

    func loadPrivateImage(_ source: PrivateImageSource) async throws(PrivateImageError) -> PrivateImage {
        guard case let .card(signedURL) = source else { throw .notFound }
        let top = URLComponents(string: signedURL)?.queryItems?.first { $0.name == "top" }?.value
        let swatch = top.flatMap(GlowSwatch.init(rawValue:)) ?? .gray
        let image = await MainActor.run { () -> PrivateImage? in
            let renderer = ImageRenderer(content: FixtureLook(swatch: swatch))
            renderer.scale = 2
            return renderer.uiImage.map(PrivateImage.init(image:))
        }
        guard let image else { throw .unreadable }
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
