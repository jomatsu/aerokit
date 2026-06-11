import AeroKitCore
import AppKit
import Carbon
import Combine
import Foundation

@MainActor
public final class ExposePreferences: ObservableObject {
    public static let defaultHotKey = HotKeySpec(
        keyCode: UInt16(kVK_ANSI_M),
        modifierRawValue: NSEvent.ModifierFlags.option.rawValue,
        keyLabel: "M"
    )

    @Published public var hotKey: HotKeySpec {
        didSet { hotKey.store(in: defaults, key: Keys.hotKey) }
    }

    /// While the overview is open, claim ⌥1–9 for window selection instead
    /// of letting AeroSpace's workspace bindings fire.
    @Published public var modifierQuickSelect: Bool {
        didSet { defaults.set(modifierQuickSelect, forKey: Keys.modifierQuickSelect) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let hotKey = "expose.hotKey"
        static let modifierQuickSelect = "expose.modifierQuickSelect"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotKey = HotKeySpec.load(from: defaults, key: Keys.hotKey) ?? Self.defaultHotKey
        modifierQuickSelect = defaults.object(forKey: Keys.modifierQuickSelect) as? Bool ?? true
    }
}
