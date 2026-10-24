import APIClient
import SwiftUI

/// Every word the check-in flow shows. Warm, calm, never pushy (spec: Voice).
enum CheckInCopy {
    static func message(for notice: CheckInModel.Notice) -> String {
        switch notice {
        case .noPerson, .rejected(.noPerson):
            String(localized: "We couldn't find you in that photo. Try again with your outfit in the frame.")
        case .unreadable, .rejected(.unreadable):
            String(localized: "That photo didn't come through. Try another one.")
        case .processingFailed:
            String(localized: "We couldn't blur that photo, so we didn't use it. Try again.")
        case .rejected(.faceVisible):
            String(localized: "A face is still visible. Retake it from the neck down.")
        case .rejected(.noOutfit):
            String(localized: "We couldn't see your outfit. Step back so more of it is in the frame.")
        case .rejected(.nudity), .rejected(.possiblyMinor):
            String(localized: "That photo can't be used. Try another outfit photo.")
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
}

/// What each top color chip shows. These are clothing colors (content), not theme colors.
enum TopColorSwatch {
    static func color(_ top: Components.Schemas.TopColor) -> Color {
        switch top {
        case .black: Color(red: 0.07, green: 0.07, blue: 0.08)
        case .white: Color(red: 0.96, green: 0.96, blue: 0.95)
        case .gray: Color(red: 0.55, green: 0.56, blue: 0.58)
        case .red: Color(red: 0.86, green: 0.16, blue: 0.18)
        case .pink: Color(red: 0.98, green: 0.55, blue: 0.72)
        case .orange: Color(red: 0.98, green: 0.52, blue: 0.13)
        case .yellow: Color(red: 0.99, green: 0.84, blue: 0.22)
        case .green: Color(red: 0.18, green: 0.62, blue: 0.33)
        case .blue: Color(red: 0.16, green: 0.42, blue: 0.86)
        case .purple: Color(red: 0.52, green: 0.30, blue: 0.82)
        }
    }
}
