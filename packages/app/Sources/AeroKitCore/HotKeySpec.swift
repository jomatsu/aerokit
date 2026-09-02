import AppKit
import Carbon
import Foundation

/// A user-configurable global hotkey: a key plus modifier flags.
///
/// Shift is intentionally excluded from stored modifiers — Shift+hotkey is
/// reserved for cycling backwards while the switcher is open.
public struct HotKeySpec: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifierRawValue: UInt
    public var keyLabel: String

    public static let `default` = HotKeySpec(
        keyCode: UInt16(kVK_ANSI_Grave),
        modifierRawValue: NSEvent.ModifierFlags.option.rawValue,
        keyLabel: "`"
    )

    public static let defaultRefresh = HotKeySpec(
        keyCode: UInt16(kVK_ANSI_R),
        modifierRawValue: NSEvent.ModifierFlags.command.rawValue,
        keyLabel: "R"
    )

    public static let defaultSettings = HotKeySpec(
        keyCode: UInt16(kVK_ANSI_Comma),
        modifierRawValue: NSEvent.ModifierFlags.command.rawValue,
        keyLabel: ","
    )

    public init(keyCode: UInt16, modifierRawValue: UInt, keyLabel: String) {
        self.keyCode = keyCode
        self.modifierRawValue = modifierRawValue
        self.keyLabel = keyLabel
    }

    public var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
            .intersection([.command, .option, .control])
    }

    public var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        let flags = modifierFlags
        if flags.contains(.control) {
            result |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            result |= UInt32(optionKey)
        }
        if flags.contains(.command) {
            result |= UInt32(cmdKey)
        }
        return result
    }

    /// The modifiers as CGEventFlags, for event-tap flag matching.
    public var cgEventFlags: CGEventFlags {
        var result: CGEventFlags = []
        let flags = modifierFlags
        if flags.contains(.control) {
            result.insert(.maskControl)
        }
        if flags.contains(.option) {
            result.insert(.maskAlternate)
        }
        if flags.contains(.command) {
            result.insert(.maskCommand)
        }
        return result
    }

    /// Keycap strings for display, e.g. ["⌥", "`"].
    public var displayKeys: [String] {
        var keys: [String] = []
        let flags = modifierFlags
        if flags.contains(.control) {
            keys.append("⌃")
        }
        if flags.contains(.option) {
            keys.append("⌥")
        }
        if flags.contains(.command) {
            keys.append("⌘")
        }
        keys.append(keyLabel)
        return keys
    }

    /// Settings-pane message when RegisterEventHotKey rejects the combination.
    public var registrationFailureMessage: String {
        "Could not register \(displayKeys.joined()) as the global hotkey. "
            + "Another app may already use it — record a different shortcut above."
    }

    /// JSON round-trip in UserDefaults; every feature persists its hotkeys
    /// this way.
    public static func load(from defaults: UserDefaults, key: String) -> HotKeySpec? {
        defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(HotKeySpec.self, from: $0) }
    }

    public func store(in defaults: UserDefaults, key: String) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: key)
        }
    }

    /// Whether a key event activates this shortcut. Extra held modifiers are
    /// tolerated so overlay shortcuts still fire while the trigger modifier
    /// keeps the switcher open.
    public func matches(_ event: NSEvent) -> Bool {
        guard event.keyCode == keyCode else {
            return false
        }
        return event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .isSuperset(of: modifierFlags)
    }

    /// Builds a spec from a recorded key event. Returns nil when the
    /// combination is unusable as a global trigger (no ⌃⌥⌘ modifier).
    public static func from(event: NSEvent) -> HotKeySpec? {
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control])
        guard !flags.isEmpty else {
            return nil
        }
        return HotKeySpec(
            keyCode: event.keyCode,
            modifierRawValue: flags.rawValue,
            keyLabel: keyLabel(for: event)
        )
    }

    private static func keyLabel(for event: NSEvent) -> String {
        let specialLabels: [UInt16: String] = [
            UInt16(kVK_Space): "Space",
            UInt16(kVK_Return): "↩",
            UInt16(kVK_Tab): "⇥",
            UInt16(kVK_Delete): "⌫",
            UInt16(kVK_LeftArrow): "←",
            UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑",
            UInt16(kVK_DownArrow): "↓"
        ]
        if let label = specialLabels[event.keyCode] {
            return label
        }

        let characters = event.charactersIgnoringModifiers ?? ""
        guard let character = characters.first, !character.isWhitespace else {
            return "?"
        }
        return String(character).uppercased()
    }
}
