import Foundation

/// Removes personal data from text before it leaves the phone in an error report.
///
/// Defense in depth for Sentry: coordinates (P2), emails, access tokens and link query strings
/// (room tokens, signed image links) are replaced with placeholders.
public enum PrivacyScrubber {
    private static let rules: [(pattern: String, template: String)] = [
        // JWTs (Supabase access tokens, join tickets).
        (#"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#, "[token]"),
        // Bearer tokens in headers.
        (#"(?i)bearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer [token]"),
        // Email addresses.
        (#"(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, "[email]"),
        // Query strings on links (room tokens, signed image links).
        (#"(?i)\b((?:https?|glow)://[^\s?#"']+)\?[^\s#"']*"#, "$1?[query]"),
        // Decimal numbers with 4+ fractional digits: coordinates and accuracies.
        (#"-?\b\d{1,3}\.\d{4,}\b"#, "[number]"),
    ]

    /// Words that make a property or field name sensitive, whatever its value.
    private static let sensitiveKeyWords: Set<String> = [
        "lat", "lng", "lon", "long", "latitude", "longitude", "coord", "coords", "coordinate", "coordinates",
        "accuracy", "location", "geo", "name", "email", "phone", "birthday", "birthdate", "dob", "age",
        "photo", "photos", "image", "images", "body", "message", "messages", "text", "token", "ticket",
        "secret", "password", "user", "userid", "uid", "ip",
    ]

    public static func scrub(_ text: String) -> String {
        var result = text
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: rule.template)
        }
        return result
    }

    /// True for keys like `lat`, `user_id`, `firstName` or `message_text` that must be dropped from
    /// any payload. Keys are split into words on `_`, `-`, `.`, spaces and camelCase humps.
    public static func isSensitiveKey(_ key: String) -> Bool {
        words(in: key).contains { sensitiveKeyWords.contains($0) }
    }

    static func words(in key: String) -> [String] {
        var words: [String] = []
        var current = ""
        for character in key {
            if character == "_" || character == "-" || character == "." || character == " " {
                if !current.isEmpty {
                    words.append(current)
                }
                current = ""
            } else if character.isUppercase, !current.isEmpty, current.last?.isUppercase == false {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words.map { $0.lowercased() }
    }
}
