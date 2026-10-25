import AppCore
import DesignSystem
import SwiftUI

/// Guess Who: my own right swipes as photo cards. Pick who I think this chat is and lock it in.
/// The sheet never says whether I'm right; the reveal screen does, after we both reveal. The list is
/// exactly my pool, unchanged by blocks or matches, so it can't give the answer away (B1).
public struct BlindGuessView: View {
    let chatID: BlindChatID

    @Environment(\.dependencies) private var dependencies
    @Environment(\.blindService) private var override
    @Environment(\.dismiss) private var dismiss
    @State private var cards: [BlindCard] = []
    @State private var images: BlindImageStore?
    @State private var selected: BlindCardID?
    @State private var locked: BlindCardID?
    @State private var errorText: String?
    @State private var saving = false

    public init(chatID: BlindChatID) {
        self.chatID = chatID
    }

    private var service: any BlindService {
        dependencies.blindService(override: override)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.md) {
            Text("Guess who").font(BlindType.codenameHero).foregroundStyle(.glowTextPrimary)
            Text("Which of the people you liked is this? You find out if you're right when you both reveal.")
                .glowFont(.body)
                .foregroundStyle(.glowTextSecondary)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: GlowSpacing.xs), count: 3), spacing: GlowSpacing.xs) {
                    ForEach(cards) { card in
                        if let images {
                            Button {
                                selected = card.id
                            } label: {
                                BlindPhotoView(photo: card.photo, store: images, cornerRadius: 16)
                                    .aspectRatio(3 / 4, contentMode: .fit)
                                    .overlay {
                                        if selected == card.id {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.glowAccent, lineWidth: 3)
                                        }
                                    }
                                    .opacity(selected == nil || selected == card.id ? 1 : 0.6)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(selected == card.id ? Text("Selected photo") : Text("Photo"))
                            .accessibilityIdentifier("blind.guess.card")
                        }
                    }
                }
            }
            if let errorText {
                Text(errorText).glowFont(.footnote).foregroundStyle(.glowDanger)
            }
            if locked != nil, locked == selected {
                Label("Locked in. You can change it until you both reveal.", systemImage: "checkmark.circle")
                    .glowFont(.footnote)
                    .foregroundStyle(.glowAccent)
            }
            Button(locked == nil ? "Lock in my guess" : "Change my guess") { Task { await lockIn() } }
                .buttonStyle(.glowPrimary)
                .glowLoading(saving)
                .disabled(selected == nil || selected == locked)
                .accessibilityIdentifier("blind.guess.lock")
            Button("Done") { dismiss() }.buttonStyle(.glowQuiet)
        }
        .padding(GlowSpacing.screenMargin)
        .background { BlindCanvas() }
        .task {
            if images == nil {
                images = BlindImageStore(service: service)
            }
            do throws(BlindError) {
                cards = try await service.poolCards()
            } catch {
                errorText = error.message
            }
        }
    }

    private func lockIn() async {
        guard let selected else { return }
        saving = true
        defer { saving = false }
        do throws(BlindError) {
            try await service.guess(chatID, card: selected)
            locked = selected
            errorText = nil
        } catch {
            errorText = error.message
        }
    }
}

/// Report (and block) the person behind a blind chat. Neither reveals who they are, and they learn
/// nothing beyond "they left" after a block. Reports go into Glow's own reports.
public struct BlindReportView: View {
    let chatID: BlindChatID

    @Environment(\.dependencies) private var dependencies
    @Environment(\.blindService) private var override
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigate) private var navigate
    @State private var choice: String?
    @State private var details = ""
    @State private var sent = false
    @State private var working = false
    @State private var confirmBlock = false
    @State private var errorText: String?

    public init(chatID: BlindChatID) {
        self.chatID = chatID
    }

    private var service: any BlindService {
        dependencies.blindService(override: override)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.md) {
            Text(sent ? "Report sent" : "Report").font(BlindType.codenameHero).foregroundStyle(.glowTextPrimary)
            Text(
                sent
                    ? "Thanks. They won't know it was you, and you won't find out who they are."
                    : "We never tell them it was you, and you never learn who they are.",
            )
            .glowFont(.body)
            .foregroundStyle(.glowTextSecondary)
            if !sent {
                GlowFlowLayout {
                    ForEach(BlindSafetyRules.reasons, id: \.self) { reason in
                        GlowChip(reason, isSelected: choice == reason) { choice = reason }
                    }
                }
                TextField("Add details (optional)", text: $details, axis: .vertical)
                    .lineLimit(2 ... 4)
                    .glowFont(.body)
                    .foregroundStyle(.glowTextPrimary)
                    .padding(GlowSpacing.md)
                    .blindGlass(cornerRadius: 16)
            }
            Spacer(minLength: 0)
            if let errorText {
                Text(errorText).glowFont(.footnote).foregroundStyle(.glowDanger)
            }
            if !sent {
                Button("Send report") { Task { await send() } }
                    .buttonStyle(.glowPrimary)
                    .glowLoading(working)
                    .disabled(BlindSafetyRules.reportText(
                        choice: choice,
                        details: String(details.prefix(BlindSafetyRules.maxDetailsLength)),
                    ) == nil)
                    .accessibilityIdentifier("blind.report.send")
            }
            Button(sent ? "Also block them" : "Block and leave") { confirmBlock = true }
                .buttonStyle(.glowDanger)
                .accessibilityIdentifier("blind.report.block")
            Button(sent ? "Done" : "Cancel") { dismiss() }.buttonStyle(.glowQuiet)
        }
        .padding(GlowSpacing.screenMargin)
        .background { BlindCanvas() }
        .confirmationDialog("Block this person?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { Task { await block() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This closes the chat. You won't see each other again anywhere in Glow, and you won't find out who they were.")
        }
    }

    private func send() async {
        guard let text = BlindSafetyRules.reportText(choice: choice, details: String(details.prefix(BlindSafetyRules.maxDetailsLength)))
        else {
            return
        }
        working = true
        defer { working = false }
        do throws(BlindError) {
            try await service.report(chatID, reason: text)
            sent = true
            errorText = nil
        } catch {
            errorText = error.message
        }
    }

    private func block() async {
        do throws(BlindError) {
            try await service.block(chatID)
            navigate(.blind)
        } catch .notFound {
            navigate(.blind)
        } catch {
            errorText = error.message
        }
    }
}
