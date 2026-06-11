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

    public static let defaultAppHotKey = HotKeySpec(
        keyCode: UInt16(kVK_ANSI_A),
        modifierRawValue: NSEvent.ModifierFlags.option.rawValue,
        keyLabel: "A"
    )

    @Published public var hotKey: HotKeySpec {
        didSet { hotKey.store(in: defaults, key: Keys.hotKey) }
    }

    /// App exposé: the focused app's windows from every workspace.
    @Published public var appHotKey: HotKeySpec {
        didSet { appHotKey.store(in: defaults, key: Keys.appHotKey) }
    }

    /// While the overview is open, claim ⌥1–9 for window selection instead
    /// of letting AeroSpace's workspace bindings fire.
    @Published public var modifierQuickSelect: Bool {
        didSet { defaults.set(modifierQuickSelect, forKey: Keys.modifierQuickSelect) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let hotKey = "expose.hotKey"
        static let appHotKey = "expose.appHotKey"
        static let modifierQuickSelect = "expose.modifierQuickSelect"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotKey = HotKeySpec.load(from: defaults, key: Keys.hotKey) ?? Self.defaultHotKey
        appHotKey = HotKeySpec.load(from: defaults, key: Keys.appHotKey) ?? Self.defaultAppHotKey
        modifierQuickSelect = defaults.object(forKey: Keys.modifierQuickSelect) as? Bool ?? true
    }
}
