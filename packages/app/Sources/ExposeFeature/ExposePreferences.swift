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

    public static let defaultWindowSwitchHotKey = HotKeySpec(
        keyCode: UInt16(kVK_Tab),
        modifierRawValue: NSEvent.ModifierFlags.option.rawValue,
        keyLabel: "\u{21e5}"
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

    /// Workspace overview opens grouped by app; the toggle key while open
    /// flips it and the last choice sticks.
    @Published public var groupByApp: Bool {
        didSet { defaults.set(groupByApp, forKey: Keys.groupByApp) }
    }

    /// Key that toggles grouping while the overview is open. Stored as a
    /// single uppercase character; quick select skips it, so any choice —
    /// including a digit or letter — stays collision-free.
    @Published public var groupToggleKey: String {
        didSet { defaults.set(groupToggleKey, forKey: Keys.groupToggleKey) }
    }

    public var groupToggleCharacter: Character {
        groupToggleKey.first ?? "0"
    }

    /// Show the grouping-toggle key as an on-screen hint while the
    /// workspace overview is open.
    @Published public var showGroupToggleHint: Bool {
        didSet { defaults.set(showGroupToggleHint, forKey: Keys.showGroupToggleHint) }
    }

    /// After ⇧1–9 or a drag moves a window to another workspace: follow it
    /// there (switch workspace, dismiss the overview) instead of staying in
    /// the overview.
    @Published public var followMovedWindow: Bool {
        didSet { defaults.set(followMovedWindow, forKey: Keys.followMovedWindow) }
    }

    /// Three-finger trackpad swipes: up opens the workspace overview, down
    /// opens app exposé — standing in for the system Mission Control and
    /// App Exposé gestures.
    @Published public var threeFingerSwipe: Bool {
        didSet { defaults.set(threeFingerSwipe, forKey: Keys.threeFingerSwipe) }
    }

    /// ⌥Tab-style cycling over the focused workspace's windows. Ships off:
    /// AeroSpace's stock config already binds alt-tab, so an on-by-default
    /// ⌥Tab would collide out of the box.
    @Published public var windowSwitchEnabled: Bool {
        didSet { defaults.set(windowSwitchEnabled, forKey: Keys.windowSwitchEnabled) }
    }

    /// Activation hotkey for the window switcher.
    @Published public var windowSwitchHotKey: HotKeySpec {
        didSet { windowSwitchHotKey.store(in: defaults, key: Keys.windowSwitchHotKey) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let hotKey = "expose.hotKey"
        static let appHotKey = "expose.appHotKey"
        static let modifierQuickSelect = "expose.modifierQuickSelect"
        static let groupByApp = "expose.groupByApp"
        static let groupToggleKey = "expose.groupToggleKey"
        static let showGroupToggleHint = "expose.showGroupToggleHint"
        static let followMovedWindow = "expose.followMovedWindow"
        static let threeFingerSwipe = "expose.threeFingerSwipe"
        static let windowSwitchEnabled = "expose.windowSwitchEnabled"
        static let windowSwitchHotKey = "expose.windowSwitchHotKey"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotKey = HotKeySpec.load(from: defaults, key: Keys.hotKey) ?? Self.defaultHotKey
        appHotKey = HotKeySpec.load(from: defaults, key: Keys.appHotKey) ?? Self.defaultAppHotKey
        modifierQuickSelect = defaults.object(forKey: Keys.modifierQuickSelect) as? Bool ?? true
        groupByApp = defaults.bool(forKey: Keys.groupByApp)
        let storedToggleKey = defaults.string(forKey: Keys.groupToggleKey)?.uppercased().first
        groupToggleKey = storedToggleKey.map(String.init) ?? "0"
        showGroupToggleHint = defaults.object(forKey: Keys.showGroupToggleHint) as? Bool ?? true
        followMovedWindow = defaults.bool(forKey: Keys.followMovedWindow)
        threeFingerSwipe = defaults.object(forKey: Keys.threeFingerSwipe) as? Bool ?? true
        windowSwitchEnabled = defaults.object(forKey: Keys.windowSwitchEnabled) as? Bool ?? false
        windowSwitchHotKey = HotKeySpec.load(from: defaults, key: Keys.windowSwitchHotKey)
            ?? Self.defaultWindowSwitchHotKey
    }
}
