import Foundation
import os

/// Diagnostics logger every module shares: one subsystem, one category per
/// feature, so `log show --predicate 'subsystem == "com.nasubikun.aerokit"'`
/// (or Console.app) recovers everything after the fact.
///
/// Messages are mirrored to stderr for terminal runs. The installed app is
/// launched through LaunchServices, where stderr goes nowhere — the unified
/// log is the only trace that survives in production.
public struct AppLog: Sendable {
    public static let subsystem = "com.nasubikun.aerokit"

    private let logger: Logger
    private let category: String

    public init(category: String) {
        self.category = category
        logger = Logger(subsystem: Self.subsystem, category: category)
    }

    /// `.public`: these are diagnostic failure messages, and a redacted
    /// `<private>` log defeats their purpose.
    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        fputs("AeroKit[\(category)]: \(message)\n", stderr)
    }

    public func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        fputs("AeroKit[\(category)]: \(message)\n", stderr)
    }
}
