import SwiftUI
import UIKit

// Owner: B6. Code entry: one box per character, for room codes and email codes.
//
//     GlowCodeField("Room code", code: $code, length: GlowConstants.ROOM_CODE_LENGTH, format: .roomCode) { full in
//         join(code: full)
//     }
//     GlowCodeField("Code from your email", code: $code, length: 6, format: .digits, error: failed ? "That code didn't work." : nil)

/// What a code field accepts.
public enum GlowCodeFormat: String, CaseIterable, Sendable {
    /// Digits only, like a 6-digit email code. Offers iOS's one-time code autofill.
    case digits
    /// Room codes: `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no I, O, 0 or 1), typed in any case.
    case roomCode

    /// The room code alphabet, as the contract's `RoomCode` describes it.
    public static let roomCodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    /// `input` with anything this format doesn't accept dropped, uppercased, and cut to `length`.
    public func sanitize(_ input: String, length: Int) -> String {
        let kept: [Character] = switch self {
        case .digits:
            input.filter { $0.isASCII && $0.isNumber }
        case .roomCode:
            input.uppercased().filter { Self.roomCodeAlphabet.contains($0) }
        }
        return String(kept.prefix(max(length, 0)))
    }

    var keyboard: UIKeyboardType {
        switch self {
        case .digits: .numberPad
        case .roomCode: .asciiCapable
        }
    }

    var contentType: UITextContentType? {
        switch self {
        case .digits: .oneTimeCode
        case .roomCode: nil
        }
    }

    var capitalization: TextInputAutocapitalization {
        switch self {
        case .digits: .never
        case .roomCode: .characters
        }
    }
}

/// A row of character boxes over one real text field, so typing, pasting, autofill and VoiceOver
/// all work like any text field. The text field draws nothing itself; the boxes show the code.
public struct GlowCodeField: View {
    @Binding private var code: String
    private let label: Text
    private let length: Int
    private let format: GlowCodeFormat
    private let error: Text?
    private let onComplete: ((String) -> Void)?

    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .title) private var boxHeight: CGFloat = 60

    /// - Parameters:
    ///   - label: what VoiceOver reads for the field.
    ///   - length: from `GlowConstants`, never typed in by hand.
    ///   - error: shown under the boxes, in the danger color, and read by VoiceOver.
    ///   - onComplete: called once the last character is typed.
    public init(
        _ label: LocalizedStringKey,
        code: Binding<String>,
        length: Int,
        format: GlowCodeFormat,
        error: LocalizedStringKey? = nil,
        onComplete: ((String) -> Void)? = nil,
    ) {
        _code = code
        self.label = Text(label)
        self.length = max(length, 1)
        self.format = format
        self.error = error.map { Text($0) }
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: GlowSpacing.xs) {
            ZStack {
                boxes
                    .accessibilityHidden(true)
                // No placeholder: the empty boxes are the prompt. The label is for VoiceOver.
                TextField(text: sanitized, prompt: Text(verbatim: "")) { label }
                    .keyboardType(format.keyboard)
                    .textContentType(format.contentType)
                    .textInputAutocapitalization(format.capitalization)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .foregroundStyle(.glowClear)
                    .tint(.glowClear)
                    .frame(maxWidth: .infinity, minHeight: boxHeight)
                    .contentShape(Rectangle())
                    .accessibilityHint(error ?? Text(verbatim: ""))
            }
            .onTapGesture { isFocused = true }

            if let error {
                Label { error } icon: { Image(systemName: "exclamationmark.circle.fill") }
                    .glowFont(.footnote)
                    .foregroundStyle(.glowDanger)
                    .accessibilityHidden(true)
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
    }

    private var sanitized: Binding<String> {
        Binding {
            code
        } set: { newValue in
            let clean = format.sanitize(newValue, length: length)
            let wasComplete = code.count == length
            code = clean
            if clean.count == length, !wasComplete {
                onComplete?(clean)
            }
        }
    }

    private var boxes: some View {
        let characters = Array(code)
        return HStack(spacing: GlowSpacing.xs) {
            ForEach(0 ..< length, id: \.self) { index in
                let isCurrent = isFocused && index == min(characters.count, length - 1)
                GlowCodeBox(
                    character: index < characters.count ? characters[index] : nil,
                    state: error != nil ? .error : isCurrent ? .current : .idle,
                    height: boxHeight,
                )
            }
        }
    }
}

/// One character box. Internal so the Gallery can draw every state.
struct GlowCodeBox: View {
    enum State {
        case idle, current, error
    }

    let character: Character?
    let state: State
    let height: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GlowRadius.control, style: .continuous)
        Text(verbatim: character.map(String.init) ?? "")
            .glowFont(.code)
            .foregroundStyle(.glowTextPrimary)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(.glowSurfaceRaised, in: shape)
            .overlay {
                shape.strokeBorder(border, lineWidth: state == .idle ? 1 : 2)
            }
    }

    private var border: Color {
        switch state {
        case .idle: .glowLine
        case .current: .glowAccent
        case .error: .glowDanger
        }
    }
}
