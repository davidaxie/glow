import APIClient
import DesignSystem
import SwiftUI

/// Every word the check-in flow shows. Warm, calm, never pushy (spec: Voice).
enum CheckInCopy {
    static func message(for notice: CheckInModel.Notice) -> String {
        switch notice {
        case .noPerson:
            message(for: .rejected(.noPerson))
        case .unreadable:
            message(for: .rejected(.unreadable))
        case let .rejected(reason):
            retake(reason)
        case .processingFailed:
            String(localized: "We couldn't blur that photo, so we didn't use it. Try again.")
        case .roomCheckExpired:
            String(localized: "Your room check timed out. Join the room again to check in.")
        case .roomNotLive:
            String(localized: "This room isn't open right now.")
        case .unavailable:
            String(localized: "We couldn't check your photo just now. Try again in a moment.")
        case .rateLimited:
            String(localized: "That's a lot of tries. Wait a minute, then try again.")
        case .offline:
            String(localized: "You're offline. Check your connection and try again.")
        case .failed:
            String(localized: "That didn't go through. Try again.")
        }
    }

    /// What to say when moderation refuses a photo. Each one ends in what to do next.
    static func retake(_ reason: PhotoRejection) -> String {
        switch reason {
        case .faceVisible:
            String(localized: "A face is still visible. Retake it from the neck down.")
        case .noOutfit:
            String(localized: "We couldn't see your outfit. Step back so more of it is in the frame.")
        case .noPerson:
            String(localized: "We couldn't find you in that photo. Try again with your outfit in the frame.")
        case .unreadable:
            String(localized: "That photo didn't come through. Try another one.")
        case .nudity, .possiblyMinor:
            String(localized: "That photo can't be used. Try another outfit photo.")
        }
    }

    static func name(_ color: Components.Schemas.TopColor) -> LocalizedStringKey {
        switch color {
        case .black: "Black"
        case .white: "White"
        case .gray: "Gray"
        case .red: "Red"
        case .pink: "Pink"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .purple: "Purple"
        }
    }

    static func name(_ length: Components.Schemas.HairLength) -> LocalizedStringKey {
        switch length {
        case .short: "Short"
        case .medium: "Medium"
        case .long: "Long"
        }
    }

    static func name(_ color: Components.Schemas.HairColor) -> LocalizedStringKey {
        switch color {
        case .black: "Black"
        case .brown: "Brown"
        case .blonde: "Blonde"
        case .red: "Red"
        case .gray: "Gray"
        case .dyed: "Dyed"
        }
    }

    static func name(_ extra: Components.Schemas.CardExtra) -> LocalizedStringKey {
        switch extra {
        case .glasses: "Glasses"
        case .hat: "Hat"
        case .beard: "Beard"
        case .headphones: "Headphones"
        case .backpack: "Backpack"
        }
    }

    /// The swatch dot for a top color chip.
    static func swatch(_ color: Components.Schemas.TopColor) -> GlowSwatch {
        GlowSwatch(rawValue: color.rawValue) ?? .gray
    }

    /// The swatch dot for a hair color chip.
    static func swatch(_ color: Components.Schemas.HairColor) -> GlowSwatch {
        GlowSwatch(rawValue: color.rawValue) ?? .gray
    }
}
