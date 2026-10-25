import AppCore
import Foundation

// Owner: X2. The JSON on the wire for `LiveBlindService`, as X1's contract (`/api/blind/*`) sends
// it. Only what the app reads; unknown fields are ignored. Optional fields are absent, never null
// (X1-D2).

enum Wire {
    struct Empty: Codable {}

    struct Ok: Decodable {
        let ok: Bool
    }

    struct ErrorEnvelope: Decodable {
        struct Body: Decodable {
            let code: String
        }

        let error: Body
    }

    struct Me: Decodable {
        let member: Bool
        let rightRemaining: Int
        let rightCount: Int
        let canDrop: Bool

        var model: BlindMe {
            BlindMe(isMember: member, rightRemaining: rightRemaining, rightCount: rightCount, canDrop: canDrop)
        }
    }

    struct Card: Decodable {
        let id: String
        let photoUrl: String

        var model: BlindCard? {
            BlindCardID(validating: id).map { BlindCard(id: $0, photo: BlindPhoto(url: photoUrl)) }
        }
    }

    struct Cards: Decodable {
        let cards: [Card]
    }

    struct SwipeRequest: Encodable {
        let targetId: String
        let kind: String
    }

    struct Counters: Decodable {
        let rightRemaining: Int
        let rightCount: Int
    }

    struct Pool: Decodable {
        let rightCount: Int
        let rightRemaining: Int
        let canDrop: Bool
    }

    struct DropStatus: Decodable {
        let ready: Bool
        let demo: Bool
        let nextDropAt: Date
        let rightCount: Int
        let canDrop: Bool
    }

    struct DropChat: Decodable {
        let id: String
        let codename: String
    }

    struct DropResult: Decodable {
        let opened: Int
        let chats: [DropChat]?
    }

    struct LastMessage: Decodable {
        let mine: Bool
        let text: String
        let at: Date
    }

    struct ChatSummary: Decodable {
        let id: String
        let codename: String
        let status: String
        let lastMessage: LastMessage?
        let unread: Bool

        var model: BlindChatSummary? {
            guard let chatID = BlindChatID(validating: id) else { return nil }
            return BlindChatSummary(
                id: chatID,
                codename: codename,
                status: BlindChatStatus(rawValue: status) ?? .open,
                lastMessage: lastMessage.map { BlindLastMessage(mine: $0.mine, text: $0.text, at: $0.at) },
                unread: unread,
            )
        }
    }

    struct ChatList: Decodable {
        let chats: [ChatSummary]
    }

    struct Partner: Decodable {
        let name: String
        let photos: [String]
    }

    struct ChatDetail: Decodable {
        let id: String
        let codename: String
        let status: String
        let iTappedReveal: Bool
        let theyLeft: Bool
        let partner: Partner?
        /// Three states on the wire: absent (no guess, or not revealed), true or false.
        let guessCorrect: Bool? // swiftlint:disable:this discouraged_optional_boolean

        var model: BlindChatDetail? {
            guard let chatID = BlindChatID(validating: id) else { return nil }
            let status = BlindChatStatus(rawValue: status) ?? .open
            // B1, belt and braces: a partner is only ever shown on a revealed chat.
            let partner = status == .revealed
                ? partner.map { BlindPartner(name: $0.name, photos: $0.photos.map(BlindPhoto.init)) }
                : nil
            return BlindChatDetail(
                id: chatID,
                codename: codename,
                status: status,
                iTappedReveal: iTappedReveal,
                theyLeft: theyLeft,
                partner: partner,
                guessCorrect: status == .revealed ? guessCorrect : nil,
            )
        }
    }

    struct Message: Decodable {
        let id: Int
        let mine: Bool
        let text: String
        let at: Date

        var model: BlindMessage {
            BlindMessage(id: id, mine: mine, text: text, at: at)
        }
    }

    struct Messages: Decodable {
        let messages: [Message]
    }

    struct SendRequest: Encodable {
        let text: String
        let confirm: Bool
    }

    struct Warning: Decodable {
        let reason: String
    }

    struct SendResult: Decodable {
        let message: Message?
        let warning: Warning?
    }

    struct Status: Decodable {
        let status: String
    }

    struct GuessRequest: Encodable {
        let guessId: String
    }

    struct ReportRequest: Encodable {
        let reason: String
    }
}
