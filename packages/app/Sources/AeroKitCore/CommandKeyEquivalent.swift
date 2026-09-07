import AppKit
import Carbon

/// Built-in Command shortcuts follow the ASCII layout's Command table, unlike
/// recorded global hotkeys, whose keycodes stay fixed. Resolve on every event.
@MainActor
public enum CommandKeyEquivalent {
    public static func matches(_ event: NSEvent, character: String) -> Bool {
        matches(event, character: character, inputSource: ASCIIKeyboardLayout.currentInputSource)
    }

    /// Explicit source lets tests exercise installed layouts without changing
    /// the user's selected input source or requiring a particular active layout.
    static func matches(_ event: NSEvent, character: String, inputSource: TISInputSource?) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        guard flags == .command else {
            return false
        }
        let translated = ASCIIKeyboardLayout.character(for: event.keyCode, command: true, inputSource: inputSource)
        // Preserve the old behavior only if layout translation is unavailable.
        // Do not OR both interpretations: that can bind two different keys.
        let resolved = translated ?? event.charactersIgnoringModifiers
        return resolved?.lowercased() == character.lowercased()
    }
}
