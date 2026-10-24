import APIClient
import SwiftUI

// MARK: - Tags

struct TagsStep: View {
    @Bindable var model: CheckInModel

    private var uploading: Bool {
        model.step == .uploading
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    if let image = model.previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A few details")
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("They help the person who noticed you find your card.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                TagSection(title: "Top color", subtitle: "Required") {
                    ForEach(Components.Schemas.TopColor.allCases, id: \.self) { color in
                        Chip(
                            title: CheckInCopy.name(color),
                            swatch: TopColorSwatch.color(color),
                            selected: model.tags.topColor == color,
                        ) {
                            model.tags.topColor = color
                        }
                        .accessibilityIdentifier("checkin.top.\(color.rawValue)")
                    }
                }

                TagSection(title: "Hair length", subtitle: "Optional") {
                    ForEach(Components.Schemas.HairLength.allCases, id: \.self) { length in
                        Chip(title: CheckInCopy.name(length), selected: model.tags.hairLength == length) {
                            model.tags.hairLength = model.tags.hairLength == length ? nil : length
                        }
                    }
                }

                TagSection(title: "Hair color", subtitle: "Optional") {
                    ForEach(Components.Schemas.HairColor.allCases, id: \.self) { color in
                        Chip(title: CheckInCopy.name(color), selected: model.tags.hairColor == color) {
                            model.tags.hairColor = model.tags.hairColor == color ? nil : color
                        }
                    }
                }

                TagSection(title: "Anything else", subtitle: "Pick any") {
                    ForEach(Components.Schemas.CardExtra.allCases, id: \.self) { extra in
                        Chip(title: CheckInCopy.name(extra), selected: model.tags.extras.contains(extra)) {
                            if model.tags.extras.contains(extra) {
                                model.tags.extras.remove(extra)
                            } else {
                                model.tags.extras.insert(extra)
                            }
                        }
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        Task { await model.submit() }
                    } label: {
                        Group {
                            if uploading {
                                ProgressView()
                            } else {
                                Text("Check in")
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSubmit)
                    .accessibilityLabel(Text(uploading ? "Checking in" : "Check in"))
                    .accessibilityIdentifier("checkin.submit")

                    Button {
                        model.backToPreview()
                    } label: {
                        Text("Back to photo").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(uploading)
                }
            }
            .padding(24)
            .disabled(uploading)
        }
    }
}

private struct TagSection<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 8) {
                content
            }
        }
    }
}

private struct Chip: View {
    let title: LocalizedStringKey
    var swatch: Color?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let swatch {
                    Circle()
                        .fill(swatch)
                        .overlay(Circle().strokeBorder(.secondary.opacity(0.6), lineWidth: 1))
                        .frame(width: 16, height: 16)
                }
                Text(title)
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(selected ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.quaternary), in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
