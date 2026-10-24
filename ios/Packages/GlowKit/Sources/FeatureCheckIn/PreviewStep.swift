import DesignSystem
import SwiftUI
import UIKit

/// Step 2: "This is what others will see." The blurred photo, exactly as it will be uploaded.
struct PreviewStep: View {
    let image: UIImage?
    let facesBlurred: Int
    let onConfirm: () -> Void
    let onRetake: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: GlowSpacing.lg) {
                GlowStepHeader(
                    step: 2,
                    of: 3,
                    title: "This is what others will see",
                    subtitle: facesBlurred > 0
                        ? "Faces are blurred. Your original photo never leaves your phone."
                        : "Your original photo never leaves your phone.",
                )
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: GlowRadius.card))
                        .frame(maxWidth: 360, maxHeight: 480)
                        .accessibilityLabel(Text(facesBlurred > 0
                                ? "Your outfit photo, with faces blurred"
                                : "Your outfit photo"))
                        .accessibilityIgnoresInvertColors()
                        .accessibilityIdentifier("checkin.preview")
                }
                VStack(spacing: GlowSpacing.sm) {
                    Button("Use this photo", action: onConfirm)
                        .buttonStyle(.glowPrimary)
                        .accessibilityIdentifier("checkin.usePhoto")
                    Button("Retake", action: onRetake)
                        .buttonStyle(.glowSecondary)
                        .accessibilityIdentifier("checkin.retake")
                }
            }
            .padding(.horizontal, GlowSpacing.screenMargin)
            .padding(.vertical, GlowSpacing.md)
        }
    }
}
