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

    public static let `default` = HotKeySpec(
        keyCode: UInt16(kVK_ANSI_Grave),
        modifierRawValue: NSEvent.ModifierFlags.option.rawValue
    )

    public static let defaultRefresh = HotKeySpec(
        keyCode: UInt16(kVK_ANSI_R),
        modifierRawValue: NSEvent.ModifierFlags.command.rawValue
    )

    public static let defaultSettings = HotKeySpec(
        keyCode: UInt16(kVK_ANSI_Comma),
        modifierRawValue: NSEvent.ModifierFlags.command.rawValue
    )

    public init(keyCode: UInt16, modifierRawValue: UInt) {
        self.keyCode = keyCode
        self.modifierRawValue = modifierRawValue
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

    /// Keycap strings, evaluated using the last-used ASCII-capable layout.
    /// Only the code and modifiers persist; legacy JSON's keyLabel is ignored.
    @MainActor public var displayKeys: [String] {
        displayKeys(inputSource: ASCIIKeyboardLayout.currentInputSource)
    }

    @MainActor
    func displayKeys(inputSource: TISInputSource?) -> [String] {
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
        keys.append(keyLabel(inputSource: inputSource))
        return keys
    }

    /// Settings-pane message when RegisterEventHotKey rejects the combination.
    @MainActor public var registrationFailureMessage: LocalizedStringResource {
        """
        Could not register \(displayKeys.joined()) as the global hotkey. \
        Another app may already use it — record a different shortcut above.
        """
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
            modifierRawValue: flags.rawValue
        )
    }

    @MainActor
    private func keyLabel(inputSource: TISInputSource?) -> String {
        let specialLabels: [UInt16: String] = [
            UInt16(kVK_Space): "Space",
            UInt16(kVK_Return): "↩",
            UInt16(kVK_Tab): "⇥",
            UInt16(kVK_Delete): "⌫",
            UInt16(kVK_LeftArrow): "←",
            UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑",
            UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_ANSI_KeypadEnter): "⌤",
            UInt16(kVK_ForwardDelete): "⌦",
            UInt16(kVK_Escape): "⎋",
            UInt16(kVK_Home): "↖",
            UInt16(kVK_End): "↘",
            UInt16(kVK_PageUp): "⇞",
            UInt16(kVK_PageDown): "⇟",
            UInt16(kVK_Help): "?⃝"
        ]
        if let label = specialLabels[keyCode] {
            return label
        }
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
        ]
        if let index = functionKeys.firstIndex(of: Int(keyCode)) {
            return "F\(index + 1)"
        }
        return ASCIIKeyboardLayout.character(for: keyCode, inputSource: inputSource)?.uppercased() ?? "?"
    }
}
