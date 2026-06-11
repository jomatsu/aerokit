import ApplicationServices
import Foundation

/// Accessibility trust, needed for the event tap that claims ⌥1–9 while the
/// exposé overview is open (Screen Recording does not cover event taps).
public enum AccessibilityPermission {
    public static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that links to Privacy & Security settings.
    /// The key is `kAXTrustedCheckOptionPrompt` spelled out: the constant is
    /// a global `var` the Swift 6 compiler rejects as non-Sendable.
    @discardableResult
    public static func request() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}
