import os

/// Logging conventions. Use `os.Logger`, never `print` (SwiftLint enforces this).
///
/// ```swift
/// private let logger = Logger(subsystem: Log.subsystem, category: "rooms")
/// logger.info("Joined \(route.name, privacy: .public)")
/// ```
///
/// Interpolated values are private by default in device logs; only mark a value `.public` when it
/// can never be personal data. Coordinates, names, message text, tokens and IDs are never public.
public enum Log {
    public static let subsystem = "com.davidxie.glow"
}
