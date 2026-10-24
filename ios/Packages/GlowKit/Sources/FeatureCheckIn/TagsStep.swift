import APIClient
import DesignSystem
import SwiftUI

/// Step 3: a few details that help the person who noticed you find your card.
struct TagsStep: View {
    @Bindable var model: CheckInModel

    private var uploading: Bool {
        model.step == .uploading
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlowSpacing.lg) {
                HStack(alignment: .top, spacing: GlowSpacing.md) {
                    GlowStepHeader(
                        step: 3,
                        of: 3,
                        title: "A few details",
                        subtitle: "They help the person who noticed you find your card.",
                    )
                    if let image = model.previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: GlowRadius.control))
                            .accessibilityHidden(true)
                    }
                }

                TagSection(title: "Top color", note: "Required") {
                    ForEach(Components.Schemas.TopColor.allCases, id: \.self) { color in
                        GlowChip(CheckInCopy.name(color), swatch: CheckInCopy.swatch(color), isSelected: model.tags.topColor == color) {
                            model.tags.topColor = color
                        }
                        .accessibilityIdentifier("checkin.top.\(color.rawValue)")
                    }
                }

                TagSection(title: "Hair length", note: "Optional") {
                    ForEach(Components.Schemas.HairLength.allCases, id: \.self) { length in
                        GlowChip(CheckInCopy.name(length), isSelected: model.tags.hairLength == length) {
                            model.tags.hairLength = model.tags.hairLength == length ? nil : length
                        }
                    }
                }

                TagSection(title: "Hair color", note: "Optional") {
                    ForEach(Components.Schemas.HairColor.allCases, id: \.self) { color in
                        GlowChip(CheckInCopy.name(color), swatch: CheckInCopy.swatch(color), isSelected: model.tags.hairColor == color) {
                            model.tags.hairColor = model.tags.hairColor == color ? nil : color
                        }
                    }
                }

                TagSection(title: "Anything else", note: "Pick any") {
                    ForEach(Components.Schemas.CardExtra.allCases, id: \.self) { extra in
                        GlowChip(CheckInCopy.name(extra), isSelected: model.tags.extras.contains(extra)) {
                            if model.tags.extras.contains(extra) {
                                model.tags.extras.remove(extra)
                            } else {
                                model.tags.extras.insert(extra)
                            }
                        }
                    }
                }

                VStack(spacing: GlowSpacing.sm) {
                    Button("Check in") {
                        Task { await model.submit() }
                    }
                    .buttonStyle(.glowPrimary)
                    .glowLoading(uploading)
                    .disabled(!model.canSubmit && !uploading)
                    .accessibilityIdentifier("checkin.submit")

                    Button("Back to photo") {
                        model.backToPreview()
                    }
                    .buttonStyle(.glowQuiet)
                    .disabled(uploading)
                }
            }
            .padding(.horizontal, GlowSpacing.screenMargin)
            .padding(.vertical, GlowSpacing.md)
        }
    }
}

private struct TagSection<Content: View>: View {
    let title: LocalizedStringKey
    let note: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: GlowSpacing.xs) {
                Text(title)
                    .glowFont(.headline)
                    .foregroundStyle(Color.glowTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(note)
                    .glowFont(.footnote)
                    .foregroundStyle(Color.glowTextSecondary)
            }
            GlowFlowLayout {
                content
            }
        }
    }
}
