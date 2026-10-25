import AppCore
import DesignSystem
import SwiftUI

// U3 (design revamp): the chat's motion, type and the quiet header at the top of the thread, with
// the exact values from docs/design/DIRECTION.md. Module-local until U1's DesignSystem `Motion`
// presets and serif styles land; then these become aliases for them (docs/design/CHANGES.md).

enum ChatStyle {
    /// `Motion.snappy`: a message landing.
    static let snappy = Animation.spring(response: 0.35, dampingFraction: 0.86)
    /// The calm crossfade every movement turns into under Reduce Motion.
    static let fade = Animation.easeOut(duration: 0.25)
    /// Bubbles: large continuous corners, tighter where a run of messages joins.
    static let bubbleRadius: CGFloat = 22
    static let joinedRadius: CGFloat = 8
    /// One breath of a waiting light, in seconds.
    static let breathPeriod: Double = 4

    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    /// 0 → 1 → 0 over one breath.
    static func breath(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: breathPeriod) / breathPeriod
        return 0.5 - 0.5 * cos(2 * Double.pi * phase)
    }
}

/// The top of the thread: a small breathing light, "You and Sam" in New York, and the promise
/// that nobody else reads this. Replaces the bare empty state; stays above the first message.
struct ChatThreadIntro: View {
    let firstName: String?
    let roomName: String?
    let breathes: Bool

    @ScaledMetric(relativeTo: .title) private var light: CGFloat = 64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: GlowSpacing.sm) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !breathes)) { context in
                let wave = breathes ? ChatStyle.breath(at: context.date) : 1
                Circle()
                    .fill(EllipticalGradient(
                        stops: [
                            .init(color: GlowPalette.accent.mixed(with: .white, amount: 0.6).color, location: 0),
                            .init(color: GlowPalette.accent.color.opacity(0.55), location: 0.25),
                            .init(color: GlowPalette.accent.color.opacity(0), location: 1),
                        ],
                        center: .center,
                        startRadiusFraction: 0,
                        endRadiusFraction: 0.5,
                    ))
                    .frame(width: light, height: light)
                    .scaleEffect(reduceMotion ? 1 : 1 + 0.03 * wave)
                    .opacity(0.6 + 0.4 * wave)
            }
            .accessibilityHidden(true)

            if let firstName {
                Text("You and \(Text(verbatim: firstName))")
                    .font(ChatStyle.serif(.title2, weight: .medium))
                    .foregroundStyle(.glowTextPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: GlowSpacing.xxs) {
                if let roomName {
                    Text("Matched in \(Text(verbatim: roomName))")
                }
                Text("It's just the two of you here.")
                Text("Nobody else can read this chat.")
            }
            .glowFont(.footnote)
            .foregroundStyle(.glowTextSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, GlowSpacing.xl)
        .padding(.bottom, GlowSpacing.md)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    /// Debug builds only: `-GlowChatFixtures thread` (or `empty`) shows made-up messages instead
    /// of calling the API, so a Simulator can show the chat without a server.
    enum ChatLaunchFixture {
        static let scenario: String? = UserDefaults.standard.string(forKey: "GlowChatFixtures")

        static func api(environment: AppConfig.Environment) -> (any ChatAPI)? {
            guard environment == .debug, let scenario else { return nil }
            let header = ChatHeader(firstName: "Blake", roomName: "Glow demo room", codeWord: "lantern", meetingSpot: "Water station")
            switch scenario {
            case "thread": return PreviewChatAPI(thread: PreviewChatAPI.sampleThread, header: header)
            case "empty": return PreviewChatAPI(thread: [], header: header)
            default: return nil
            }
        }
    }
#endif
