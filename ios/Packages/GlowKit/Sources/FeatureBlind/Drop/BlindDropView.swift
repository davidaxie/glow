import AppCore
import DesignSystem
import SwiftUI

/// The drop. Before it: a countdown to tonight's drop inside a ring that fills with my pool (5
/// right swipes to get in). With the stage's demo mode, or once the time has come, a button opens
/// it; the new chats then arrive face down as frosted glass and turn over one at a time.
public struct BlindDropView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.blindService) private var override
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigate) private var navigate
    @State private var model: BlindDropModel?

    public init() {}

    public var body: some View {
        ZStack {
            BlindCanvas()
            if let model {
                switch model.phase {
                case .loading:
                    BlindVeilOrb(seed: "drop", size: 88).blindBreathing()
                case let .unavailable(message):
                    unavailable(message, model)
                case .idle:
                    BlindDropIdleView(
                        status: model.status,
                        errorText: model.errorText,
                        onOpen: { Task { await model.open() } },
                        onSwipe: { close(to: .swipe) },
                        onClose: { dismiss() },
                        onRefresh: { Task { await model.load() } },
                    )
                case .opening:
                    BlindDropOpeningView()
                case let .revealing(names):
                    BlindDropRevealView(names: names, onChats: { close(to: .chats) }, onBack: { Task { await model.finish() } })
                }
            }
        }
        .task {
            if model == nil {
                model = BlindDropModel(service: dependencies.blindService(override: override), analytics: dependencies.analytics)
            }
            await model?.load()
            #if DEBUG
                // `-GlowDebugBlindAutoOpen YES` presses Open my drop by itself, for screenshots.
                if UserDefaults.standard.bool(forKey: "GlowDebugBlindAutoOpen"), model?.status?.canDrop == true {
                    try? await Task.sleep(for: .seconds(1))
                    await model?.open()
                }
            #endif
        }
    }

    private func close(to section: BlindTabState.Section) {
        BlindTabState.shared.section = section
        navigate(.blind)
    }

    private func unavailable(_ message: String, _ model: BlindDropModel) -> some View {
        VStack(spacing: GlowSpacing.lg) {
            Spacer()
            Text("Your drop").font(BlindType.codenameHero).foregroundStyle(.glowTextPrimary)
            Text(message).glowFont(.body).foregroundStyle(.glowTextSecondary).multilineTextAlignment(.center)
            Spacer()
            Button("Try again") { Task { await model.retry() } }.buttonStyle(.glowPrimary)
            Button("Close") { dismiss() }.buttonStyle(.glowQuiet)
        }
        .padding(GlowSpacing.screenMargin)
    }
}

/// The countdown, the pool ring and the button. Pure drawing from a `BlindDropStatus`.
private struct BlindDropIdleView: View {
    let status: BlindDropStatus?
    let errorText: String?
    let onOpen: () -> Void
    let onSwipe: () -> Void
    let onClose: () -> Void
    let onRefresh: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.blindClock) private var clock

    var body: some View {
        VStack(spacing: GlowSpacing.lg) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .glowFont(.headline)
                        .foregroundStyle(.glowTextSecondary)
                        .frame(width: GlowSize.minimumTapTarget, height: GlowSize.minimumTapTarget)
                        .background(.glowSurface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
                .accessibilityIdentifier("blind.drop.close")
            }

            Spacer(minLength: 0)

            if let status {
                let mode = BlindDropRules.mode(for: status)
                VStack(spacing: GlowSpacing.xl) {
                    Text(eyebrow(mode))
                        .glowFont(.caption)
                        .tracking(2)
                        .foregroundStyle(.glowTextSecondary)
                    ring(status, mode)
                    VStack(spacing: GlowSpacing.sm) {
                        BlindDropMarks(filled: BlindDeckRules.filledDots(rightCount: status.rightCount))
                        Text(BlindDropRules.progressText(rightCount: status.rightCount))
                            .glowFont(.body)
                            .foregroundStyle(.glowTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    Text(caption(mode))
                        .glowFont(.footnote)
                        .foregroundStyle(.glowTextSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer(minLength: 0)

            if let errorText {
                Text(errorText)
                    .glowFont(.footnote)
                    .foregroundStyle(.glowDanger)
                    .multilineTextAlignment(.center)
            }
            buttons
        }
        .padding(.horizontal, GlowSpacing.screenMargin)
        .padding(.bottom, GlowSpacing.lg)
        .padding(.top, GlowSpacing.sm)
        // Refresh the moment the clock passes the drop time, and whenever the app comes back.
        .task(id: status?.nextDropAt) {
            guard let next = status?.nextDropAt else { return }
            let wait = next.timeIntervalSince(clock()) + 1
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            if !Task.isCancelled {
                onRefresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                onRefresh()
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        switch status.map(BlindDropRules.mode(for:)) {
        case .needSwipes:
            Button("Keep swiping", action: onSwipe)
                .buttonStyle(.glowPrimary)
                .accessibilityIdentifier("blind.drop.keepSwiping")
        case .demo, .ready:
            Button("Open my drop", action: onOpen)
                .buttonStyle(.glowPrimary)
                .accessibilityIdentifier("blind.drop.open")
        case .waiting:
            Text("We'll let you know when it's ready.")
                .glowFont(.footnote)
                .foregroundStyle(.glowTextSecondary)
        case nil:
            EmptyView()
        }
    }

    private func eyebrow(_ mode: BlindDropRules.Mode) -> String {
        switch mode {
        // Demo mode looks exactly like a live drop whose time has come.
        case .ready, .demo: String(localized: "YOUR DROP IS READY")
        default: String(localized: "TONIGHT'S DROP")
        }
    }

    private func caption(_ mode: BlindDropRules.Mode) -> String {
        switch mode {
        case .needSwipes: String(localized: "Drops open for people with 5 right swipes.")
        case .waiting, .demo, .ready: String(localized: "Everyone in your drop is someone you liked.")
        }
    }

    private func ring(_ status: BlindDropStatus, _ mode: BlindDropRules.Mode) -> some View {
        let progress = min(1, Double(status.rightCount) / Double(BlindRulesConstants.dropMinimumRightSwipes))
        let isNow = mode == .ready || mode == .demo
        return ZStack {
            Circle().stroke(.glowLine, lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.glowAccent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(BlindMotion.gentle, value: progress)
            if isNow {
                BlindVeilOrb(seed: "now", size: 150).blindBreathing()
            }
            VStack(spacing: GlowSpacing.xxs) {
                if isNow {
                    Text("Now")
                        .font(BlindType.codenameHero)
                        .foregroundStyle(.glowTextPrimary)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, status.nextDropAt.timeIntervalSince(context.date))
                        Text(BlindDropRules.countdown(remaining))
                            .font(BlindType.counter)
                            .foregroundStyle(.glowTextPrimary)
                            .contentTransition(.numericText(countsDown: true))
                            .accessibilityLabel(Text("Drop opens in \(BlindDropRules.countdownSpoken(remaining))"))
                    }
                    Text("until the drop")
                        .glowFont(.footnote)
                        .foregroundStyle(.glowTextSecondary)
                }
            }
        }
        .frame(width: 260, height: 260)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("blind.drop.ring")
    }
}

/// While the drop opens: light breathing outward from a frosted center. Never a spinner.
private struct BlindDropOpeningView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: GlowSpacing.xxl) {
            Spacer()
            TimelineView(.animation(paused: reduceMotion)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0 ..< 3, id: \.self) { index in
                        let phase = (time / 2.4 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                        Circle()
                            .stroke(.glowAccent.opacity(0.6 * (1 - phase)), lineWidth: 1.5)
                            .frame(width: 80 + 180 * phase, height: 80 + 180 * phase)
                    }
                    BlindVeilOrb(seed: "opening", size: 84)
                }
            }
            .frame(height: 280)
            .blindBreathing()
            Text("Opening your drop")
                .font(BlindType.statement)
                .foregroundStyle(.glowTextPrimary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Opening your drop"))
    }
}

/// The reveal: codename cards arrive face down as frosted glass (40 ms apart), then turn over one
/// by one, each name shimmering once in New York italic, with a tick each.
private struct BlindDropRevealView: View {
    let names: [String]
    let onChats: () -> Void
    let onBack: () -> Void

    @State private var arrived = false
    @State private var turned = 0
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.lg) {
            VStack(alignment: .leading, spacing: GlowSpacing.xs) {
                Text(headline)
                    .font(BlindType.codenameHero)
                    .foregroundStyle(.glowTextPrimary)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("blind.drop.headline")
                Text(subline)
                    .glowFont(.body)
                    .foregroundStyle(.glowTextSecondary)
            }
            .padding(.top, GlowSpacing.xxl)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: GlowSpacing.sm) {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    BlindCodenameCard(name: name, isTurned: index < turned)
                        .opacity(arrived ? 1 : 0)
                        .offset(y: arrived || reduceMotion ? 0 : 24)
                        .animation(
                            BlindMotion.motion(BlindMotion.smooth, reduceMotion: reduceMotion)
                                .delay(Double(index) * BlindMotion.staggerSeconds),
                            value: arrived,
                        )
                }
            }

            Spacer(minLength: 0)

            if finished {
                Group {
                    if names.isEmpty {
                        Button("Back", action: onBack).buttonStyle(.glowSecondary)
                    } else {
                        Button("See my chats", action: onChats)
                            .buttonStyle(.glowPrimary)
                            .accessibilityIdentifier("blind.drop.seeChats")
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, GlowSpacing.screenMargin)
        .padding(.bottom, GlowSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glowHaptic(.lightTap, trigger: turned)
        .glowHaptic(.success, trigger: finished)
        .task { await play() }
    }

    private var headline: String {
        if names.isEmpty {
            return String(localized: "Nothing new")
        }
        return turned == 0 ? String(localized: "Here they come") : BlindDropRules.openedText(turned)
    }

    private var subline: String {
        names.isEmpty
            ? String(localized: "No new chats this time. Keep swiping and check the next drop.")
            : String(localized: "Everyone here is someone you liked. Say hello.")
    }

    private func play() async {
        guard turned == 0, !finished else { return }
        arrived = true
        try? await Task.sleep(for: .milliseconds(500))
        for index in names.indices {
            if Task.isCancelled {
                return
            }
            withAnimation(BlindMotion.motion(BlindMotion.smooth, reduceMotion: reduceMotion)) {
                turned = index + 1
            }
            try? await Task.sleep(for: .milliseconds(650))
        }
        if Task.isCancelled {
            return
        }
        withAnimation(BlindMotion.fade) { finished = true }
    }
}
