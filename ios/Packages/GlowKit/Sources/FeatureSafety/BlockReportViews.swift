import APIClient
import AppCore
import DesignSystem
import SwiftUI

// Owner: B8. The block and report sheets and the pause and delete screens. The app shows them for
// `.block`, `.report`, `.pause` and `.deleteAccount`; keep these public initializers.
// Colors, type and buttons come from DesignSystem (B6) only.

// MARK: - Block

/// Shown as a sheet from a card, a match or a chat. Blocking applies both ways, everywhere, at once
/// (P7), ends any match and chat between the two, and the other person isn't told.
public struct BlockSheet: View {
    public let context: SafetyContext
    @Environment(\.dependencies) private var dependencies
    @State private var model: BlockModel?
    @State private var reporting = false

    public init(context: SafetyContext) {
        self.context = context
    }

    public var body: some View {
        Group {
            if reporting {
                ReportForm(context: context)
            } else if let model {
                BlockContent(model: model)
            } else {
                Color.glowClear.frame(height: 1)
            }
        }
        .environment(\.safetyStartReport) { reporting = true }
        .glowSheetPresentation()
        .task {
            if model == nil {
                model = BlockModel(context: context, api: dependencies.api, analytics: dependencies.analytics)
            }
        }
    }
}

struct BlockContent: View {
    let model: BlockModel
    @Environment(\.safetyStartReport) private var startReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if model.phase == .done {
            SafetyDone(
                title: "Done. They won't see you again.",
                message: model.context.matchID == nil
                    ? "Their card is gone from your deck, and yours from theirs."
                    : "Your match and chat with them have ended.",
                context: model.context,
            )
        } else {
            GlowSheetContent(
                title: "Block this person?",
                message: model.context.matchID == nil
                    ? "You won't see each other anywhere in Glow, and they aren't told."
                    : "You won't see each other anywhere in Glow, and they aren't told. Your match and chat end too.",
                systemImage: "hand.raised",
                tint: GlowPalette.danger,
            ) {
                SafetyFailureText(phase: model.phase)
            } actions: {
                Button("Block") { Task { await model.block() } }
                    .buttonStyle(.glowDanger)
                    .glowLoading(model.phase.isWorking)
                    .accessibilityHint("They won't see you again, and they aren't told.")
                Button("Report instead") { startReport() }
                    .buttonStyle(.glowSecondary)
                    .disabled(model.phase.isWorking)
                    .accessibilityHint("Reporting also blocks them.")
                Button("Not now") { dismiss() }
                    .buttonStyle(.glowQuiet)
                    .disabled(model.phase.isWorking)
            }
        }
    }
}

// MARK: - Report

/// Shown as a sheet from a card, a match or a chat. Reporting also blocks.
public struct ReportSheet: View {
    public let context: SafetyContext

    public init(context: SafetyContext) {
        self.context = context
    }

    public var body: some View {
        ReportForm(context: context)
            .glowSheetPresentation()
    }
}

struct ReportForm: View {
    let context: SafetyContext
    @Environment(\.dependencies) private var dependencies
    @State private var model: ReportModel?

    var body: some View {
        Group {
            if let model {
                ReportContent(model: model)
            } else {
                Color.glowClear.frame(height: 1)
            }
        }
        .task {
            if model == nil {
                model = ReportModel(context: context, api: dependencies.api, analytics: dependencies.analytics)
            }
        }
    }
}

struct ReportContent: View {
    @Bindable var model: ReportModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var detailsFocused: Bool

    var body: some View {
        if model.phase == .done {
            SafetyDone(
                title: "Thanks for telling us.",
                message: "We'll look into it. They won't see you again, and they aren't told who reported.",
                context: model.context,
            )
        } else {
            GlowSheetContent(
                title: "What happened?",
                message: "Reporting also blocks them. They aren't told who reported.",
                systemImage: "flag",
                tint: GlowPalette.danger,
            ) {
                VStack(alignment: .leading, spacing: GlowSpacing.md) {
                    GlowFlowLayout {
                        ForEach(ReportReason.allCases) { reason in
                            GlowChip(reason.title, isSelected: model.reason == reason) {
                                model.reason = reason
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Reasons")

                    VStack(alignment: .leading, spacing: GlowSpacing.xxs) {
                        TextField("Anything else we should know? (optional)", text: $model.details, axis: .vertical)
                            .lineLimit(3 ... 6)
                            .glowFont(.body)
                            .foregroundStyle(.glowTextPrimary)
                            .focused($detailsFocused)
                            .padding(GlowSpacing.sm)
                            .background(.glowSurfaceRaised, in: .rect(cornerRadius: GlowRadius.control))
                            .accessibilityLabel("Details, optional")
                        Text("\(model.details.count) of \(ReportModel.maxDetails)")
                            .glowFont(.footnote)
                            .foregroundStyle(.glowTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityLabel("\(model.details.count) of \(ReportModel.maxDetails) characters used")
                    }

                    SafetyFailureText(phase: model.phase)
                }
            } actions: {
                Button("Report and block") {
                    detailsFocused = false
                    Task { await model.submit() }
                }
                .buttonStyle(.glowDanger)
                .glowLoading(model.phase.isWorking)
                .disabled(model.reason == nil)
                .accessibilityHint(model.reason == nil ? "Choose what happened first." : "")
                Button("Not now") { dismiss() }
                    .buttonStyle(.glowQuiet)
                    .disabled(model.phase.isWorking)
            }
        }
    }
}

extension ReportReason {
    var title: LocalizedStringKey {
        switch self {
        case .harassment: "Harassment"
        case .inappropriatePhoto: "Inappropriate photo"
        case .underage: "Might be under 18"
        case .spam: "Spam or a scam"
        case .unsafe: "Made me feel unsafe"
        case .other: "Something else"
        }
    }
}

#Preview("Block") {
    Color.glowBackground
        .sheet(isPresented: .constant(true)) {
            BlockSheet(context: .card(CardID(rawValue: "00000000-0000-4000-8000-000000000003")))
        }
}

#Preview("Report") {
    Color.glowBackground
        .sheet(isPresented: .constant(true)) {
            ReportSheet(context: .chat(MatchID(rawValue: "00000000-0000-4000-8000-000000000001")))
        }
}
