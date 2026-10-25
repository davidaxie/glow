import APIClient
import AppCore
import DesignSystem
import SwiftUI

// U3 (design revamp): the glow's entrance and type, with the exact values from
// docs/design/DIRECTION.md. Module-local until U1's DesignSystem `Motion` presets and serif styles
// land; then these become aliases for them (docs/design/CHANGES.md). Presentation only.

enum GlowMoment {
    /// `Motion.smooth`: things arriving.
    static let smooth = Animation.spring(response: 0.5, dampingFraction: 0.9)
    /// `Motion.gentle`: the color filling the screen from the middle.
    static let gentle = Animation.spring(response: 0.8, dampingFraction: 0.95)
    /// The calm crossfade every movement turns into under Reduce Motion.
    static let fade = Animation.easeOut(duration: 0.25)
    /// Between items appearing one after another.
    static let stagger: Double = 0.04
    /// The light at the heart of the bloom: 600 ms, then settle.
    static let bloom = Animation.easeOut(duration: 0.6)
    /// One breath of a waiting state, in seconds.
    static let breathPeriod: Double = 4

    /// 0 → 1 → 0 over one breath.
    static func breath(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: breathPeriod) / breathPeriod
        return 0.5 - 0.5 * cos(2 * Double.pi * phase)
    }

    /// New York at a point size; pair it with `@ScaledMetric`.
    static func serif(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// New York, scaling with Dynamic Type.
    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
    }
}

/// The code word, set large in New York capitals. Same word and same color on both phones: both
/// draw the server's glow through this view. VoiceOver reads "Code word: lantern".
struct GlowWordmark: View {
    let word: String
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 80

    var body: some View {
        Text(verbatim: word)
            .font(GlowMoment.serif(size: size, weight: .semibold))
            .kerning(size * 0.02)
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .accessibilityLabel(Text("Code word: \(word)"))
            .accessibilityAddTraits(.isHeader)
    }
}

/// Rises into place a beat after the item before it.
struct GlowRise: ViewModifier {
    let index: Int
    let isShown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : 18)
            .animation(
                (reduceMotion ? GlowMoment.fade : GlowMoment.smooth).delay(0.18 + Double(index) * GlowMoment.stagger),
                value: isShown,
            )
    }
}

extension View {
    func glowRise(_ index: Int, shown: Bool) -> some View {
        modifier(GlowRise(index: index, isShown: shown))
    }
}

// MARK: - Debug fixtures

#if DEBUG
    /// Debug builds only: `-GlowGlowFixtures <color>` (`aqua`, `sun`, …) shows a made-up glow for
    /// that color instead of calling the API, so a Simulator can record the mutual moment into the
    /// glow without a server. Every phone launched with the same color shows the same word and spot.
    enum GlowLaunchFixture {
        static let hue: GlowHue? = UserDefaults.standard.string(forKey: "GlowGlowFixtures").flatMap(GlowHue.init(rawValue:))

        @MainActor
        static func model(for matchID: MatchID, environment: AppConfig.Environment) -> GlowModel? {
            guard environment == .debug, let hue else { return nil }
            let now = Date()
            let session = GlowSession(
                id: "453803c0-4199-465b-a12d-1981639daadd",
                status: .active,
                hue: hue,
                codeWord: "lantern",
                meetingSpot: "Water station",
                startedAt: now,
                endsAt: now.addingTimeInterval(15 * 60),
            )
            return GlowModel(
                matchID: matchID,
                client: PreviewGlowClient(session),
                liveActivities: NoopGlowLiveActivities(),
                analytics: NoopAnalytics(),
            )
        }
    }
#endif
