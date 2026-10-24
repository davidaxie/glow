import CryptoKit
import Foundation
import Security

/// The nonce for one Sign in with Apple attempt. Apple gets its SHA-256 (`hashed`) in the
/// request, and Supabase gets the raw value with the ID token, so a stolen token can't be replayed.
public struct AppleSignInNonce: Sendable, Hashable {
    public let raw: String

    public init(raw: String) {
        self.raw = raw
    }

    /// 32 random bytes, base64url.
    public static func make() -> AppleSignInNonce {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "No secure random bytes for the sign-in nonce")
        let raw = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return AppleSignInNonce(raw: raw)
    }

    /// What goes in `ASAuthorizationAppleIDRequest.nonce`: the lowercase hex SHA-256 of `raw`.
    public var hashed: String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
