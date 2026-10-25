import AppCore
import DesignSystem
import SwiftUI

// Owner: C3, revamped by U3. The glow itself: the shared color blooming from the middle of the
// screen, the code word in New York, frosted glass for the meeting spot, and the actions.

struct GlowOnView: View {
    let session: GlowSession
    let isSending: Bool
    let actionFailed: Bool
    let controlsScreen: Bool
    let frozenAt: Date?
    let onMet: () -> Void
    let onSwitchToChat: () -> Void
    let onEnd: () -> Void
    let onHide: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The color has filled the screen.
    @State private var filled = false
    /// The surface and its words are on top of the color.
    @State private var surfaced = false
    /// The single soft light at the heart of the bloom.
    @State private var lightOn = false

    /// Snapshot tests hold time still and get the settled glow, with no entrance.
    private var isStill: Bool {
        frozenAt != nil
    }

    var body: some View {
        ZStack {
            // The dark room the color blooms into.
            Rectangle().fill(.glowBackground).ignoresSafeArea()
            colorBloom
            GlowSurface(session.hue, isPulsing: frozenAt == nil, controlsScreen: controlsScreen) {
                layout
            }
            .opacity(surfaced || isStill ? 1 : 0)
            heartLight
        }
        .task { await enter() }
    }

    // MARK: Entrance

    /// The shared color, growing from the middle of the screen until it fills it.
    private var colorBloom: some View {
        GeometryReader { proxy in
            let diameter = max(proxy.size.width, proxy.size.height) * 2.4
            Circle()
                .fill(session.hue.color)
                .frame(width: diameter, height: diameter)
                .scaleEffect(filled || isStill || reduceMotion ? 1 : 0.01)
                .opacity(filled || isStill ? 1 : 0)
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.42)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// One soft white bloom where the color starts, 600 ms, then it settles. Never repeats.
    private var heartLight: some View {
        GeometryReader { proxy in
            let side = max(proxy.size.width, proxy.size.height)
            Circle()
                .fill(EllipticalGradient(
                    colors: [GlowRGB.white.color.opacity(0.5), GlowRGB.white.color.opacity(0)],
                    center: .center,
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.5,
                ))
                .frame(width: side, height: side)
                .scaleEffect(lightOn || reduceMotion ? 1.2 : 0.2)
                .opacity(lightOn ? 1 : 0)
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.42)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func enter() async {
        guard !isStill, !filled else { return }
        if reduceMotion {
            withAnimation(GlowLook.fade) { filled = true }
            withAnimation(GlowLook.fade.delay(0.15)) { surfaced = true }
            return
        }
        // U1's glow cue: the low airy swell as the color fills the screen.
        GlowHaptics.shared.play(GlowMoment.glowArrives)
        withAnimation(GlowLook.bloom) { lightOn = true }
        withAnimation(GlowLook.gentle) { filled = true }
        try? await Task.sleep(for: .milliseconds(360))
        withAnimation(GlowLook.fade) { surfaced = true }
        try? await Task.sleep(for: .milliseconds(240))
        withAnimation(.easeOut(duration: 0.9)) { lightOn = false }
    }

    private var shown: Bool {
        surfaced || isStill
    }

    // MARK: Layout

    private var layout: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, GlowSpacing.screenMargin)
                .padding(.top, GlowSpacing.xs)
                .glowRise(0, shown: shown)
            // The word and the spot scroll at large text sizes; the actions below never do, so
            // We met is always on screen.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: GlowSpacing.xl) {
                        word
                        spot
                            .glowRise(4, shown: shown)
                        GlowSayAloudView(lines: GlowSayAloud.lines(codeWord: session.codeWord, meetingSpot: session.meetingSpot))
                            .glowRise(5, shown: shown)
                    }
                    .padding(.horizontal, GlowSpacing.screenMargin)
                    .padding(.vertical, GlowSpacing.lg)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
            actions
                .padding(.horizontal, GlowSpacing.screenMargin)
                .padding(.bottom, GlowSpacing.xs)
                .glowRise(6, shown: shown)
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            Button(action: onHide) {
                Image(systemName: "chevron.down")
                    .font(.glow(.headline))
                    .frame(width: GlowSize.minimumTapTarget, height: GlowSize.minimumTapTarget)
                    .background(GlowFrost.fill, in: Circle())
            }
            .accessibilityLabel(Text("Hide glow"))
            .accessibilityHint(Text("The glow keeps going. Find it again in Matches."))
            Spacer()
            GlowCountdown(start: session.startedAt, end: session.endsAt, frozenAt: frozenAt)
        }
    }

    private var word: some View {
        VStack(spacing: GlowSpacing.sm) {
            Text("Your code word")
                .glowFont(.footnote)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .kerning(1.6)
                .glowRise(1, shown: shown)
            GlowWordmark(word: session.displayWord)
                .scaleEffect(shown || reduceMotion ? 1 : 0.94)
                .glowRise(2, shown: shown)
            // The color's name too, for anyone who can't tell the colors apart.
            Text("\(session.hue.name) glow")
                .glowFont(.headline)
                .accessibilityLabel(Text("Color: \(session.hue.name)"))
                .glowRise(3, shown: shown)
        }
        .multilineTextAlignment(.center)
    }

    private var spot: some View {
        VStack(spacing: GlowSpacing.xs) {
            if let meetingSpot = session.meetingSpot {
                Label {
                    Text("Meet at")
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                }
                .glowFont(.footnote)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .kerning(1.2)
                Text(verbatim: meetingSpot)
                    .font(GlowLook.serif(.title, weight: .medium))
                    .padding(.bottom, GlowSpacing.xxs)
            }
            Text("Hold your phone up. They're looking for this color too.")
                .glowFont(.callout)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, GlowSpacing.lg)
        .padding(.vertical, GlowSpacing.md)
        .frame(maxWidth: .infinity)
        .background(GlowFrost.fill, in: .rect(cornerRadius: GlowFrost.radius, style: .continuous))
        .overlay { GlowFrost.edge }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: GlowSpacing.sm) {
            if let note {
                Text(note)
                    .glowFont(.callout)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Button(action: onMet) {
                Text(session.youMet ? "Waiting for them" : "We met")
            }
            .buttonStyle(.glowOnSurface)
            .clipShape(Capsule())
            .glowLoading(isSending && !session.youMet)
            .disabled(session.youMet || isSending)
            .accessibilityHint(session.youMet ? Text("") : Text("It counts once you've both tapped it."))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: GlowSpacing.xl) { secondaryButtons }
                VStack(spacing: GlowSpacing.xs) { secondaryButtons }
            }
        }
    }

    @ViewBuilder private var secondaryButtons: some View {
        Button("Switch to chat", action: onSwitchToChat)
            .glowFont(.callout)
            .fontWeight(.semibold)
            .frame(minHeight: GlowSize.minimumTapTarget)
            .disabled(isSending)
        Button("End glow", action: onEnd)
            .glowFont(.callout)
            .fontWeight(.semibold)
            .frame(minHeight: GlowSize.minimumTapTarget)
            .disabled(isSending)
    }

    private var note: LocalizedStringKey? {
        if actionFailed {
            return "Couldn't reach Glow. Try again."
        }
        switch (session.youMet, session.theyMet) {
        case (true, false): return "Waiting for them to tap We met too."
        case (false, true): return "They tapped We met. Tap it when you've found each other."
        default: return nil
        }
    }
}

/// Frosted glass on a glow color: white mixed over the color, so the ink on it only gains
/// contrast (it never darkens the color under text).
enum GlowFrost {
    static let radius: CGFloat = 28
    static let fill = GlowRGB.white.color.opacity(0.2)

    static var edge: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [GlowRGB.white.color.opacity(0.55), GlowRGB.white.color.opacity(0.1)],
                    startPoint: .top,
                    endPoint: .bottom,
                ),
                lineWidth: 1,
            )
            .accessibilityHidden(true)
    }
}

/// Minutes and seconds left, counting down to the glow's end.
struct GlowCountdown: View {
    let start: Date
    let end: Date
    let frozenAt: Date?

    var body: some View {
        Label {
            if let frozenAt {
                Text(Self.remaining(from: frozenAt, to: end))
                    .monospacedDigit()
            } else {
                Text(timerInterval: min(start, end) ... end, countsDown: true)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: "timer")
        }
        .glowFont(.headline)
        .padding(.horizontal, GlowSpacing.md)
        .frame(minHeight: GlowSize.minimumTapTarget)
        .background(GlowFrost.fill, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Time left"))
    }

    /// "12:34", for a frozen snapshot.
    nonisolated static func remaining(from now: Date, to end: Date) -> String {
        let seconds = max(Int(end.timeIntervalSince(now).rounded(.down)), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
