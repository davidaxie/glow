import SwiftUI
import UIKit

// MARK: - Preview

struct PreviewStep: View {
    let image: UIImage?
    let facesBlurred: Int
    let onConfirm: () -> Void
    let onRetake: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("This is what others will see")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .frame(maxHeight: 460)
                        .accessibilityLabel(Text(facesBlurred > 0
                                ? "Your outfit photo, with faces blurred"
                                : "Your outfit photo"))
                        .accessibilityIgnoresInvertColors()
                }
                Text(facesBlurred > 0
                    ? "Faces are blurred. Your original photo never leaves your phone."
                    : "No faces found. Your original photo never leaves your phone.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 12) {
                    Button(action: onConfirm) {
                        Text("Use this photo").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("checkin.usePhoto")
                    Button(action: onRetake) {
                        Text("Retake").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("checkin.retake")
                }
            }
            .padding(24)
        }
    }
}
