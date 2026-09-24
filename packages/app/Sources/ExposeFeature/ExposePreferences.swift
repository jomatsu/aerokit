import AeroKitCore
import AppKit
import Carbon
import Combine
import Foundation

@MainActor
public final class ExposePreferences: ObservableObject {
    public static let defaultHotKey = HotKeySpec(
        keyCode: UInt16(kVK_ANSI_M),
        modifierRawValue: NSEvent.ModifierFlags.option.rawValue
    )

    public static let defaultAppHotKey = HotKeySpec(
        keyCode: UInt16(kVK_ANSI_A),
        modifierRawValue: NSEvent.ModifierFlags.option.rawValue
    )

    /// The shortcut releases through v0.2.6 used implicitly (never stored)
    /// when window switching was switched on.
    static let legacyWindowSwitchHotKey = HotKeySpec(
        keyCode: UInt16(kVK_Tab),
        modifierRawValue: NSEvent.ModifierFlags.option.rawValue
    )

    @Published public var hotKey: HotKeySpec {
        didSet { hotKey.store(in: defaults, key: Keys.hotKey) }
    }

    /// App exposé: the focused app's windows from every workspace.
    @Published public var appHotKey: HotKeySpec {
        didSet { appHotKey.store(in: defaults, key: Keys.appHotKey) }
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

    /// Hold-to-cycle through the focused workspace's windows. Experimental,
    /// so it ships without a shortcut: assigning one turns the feature on
    /// and clearing it turns it off — there is no separate switch.
    @Published public var windowSwitchHotKey: HotKeySpec? {
        didSet {
            if let windowSwitchHotKey {
                windowSwitchHotKey.store(in: defaults, key: Keys.windowSwitchHotKey)
            } else {
                defaults.removeObject(forKey: Keys.windowSwitchHotKey)
            }
        }
    }

    public var windowSwitchEnabled: Bool {
        windowSwitchHotKey != nil
    }

    public func resetKeyboardSettings() {
        hotKey = Self.defaultHotKey
        appHotKey = Self.defaultAppHotKey
        groupToggleKey = "0"
        windowSwitchHotKey = nil
    }

    public func resetDisplaySettings() {
        groupByApp = false
        followMovedWindow = false
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let hotKey = "expose.hotKey"
        static let appHotKey = "expose.appHotKey"
        static let groupByApp = "expose.groupByApp"
        static let groupToggleKey = "expose.groupToggleKey"
        static let followMovedWindow = "expose.followMovedWindow"
        static let threeFingerSwipe = "expose.threeFingerSwipe"
        static let windowSwitchHotKey = "expose.windowSwitchHotKey"
        /// Retired: the switch is implied by the shortcut, and the layout
        /// key hint always shows. Read once for migration, then dropped.
        static let windowSwitchEnabled = "expose.windowSwitchEnabled"
        static let showGroupToggleHint = "expose.showGroupToggleHint"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotKey = HotKeySpec.load(from: defaults, key: Keys.hotKey) ?? Self.defaultHotKey
        appHotKey = HotKeySpec.load(from: defaults, key: Keys.appHotKey) ?? Self.defaultAppHotKey
        groupByApp = defaults.bool(forKey: Keys.groupByApp)
        let storedToggleKey = defaults.string(forKey: Keys.groupToggleKey)?.uppercased().first
        groupToggleKey = storedToggleKey.map(String.init) ?? "0"
        followMovedWindow = defaults.bool(forKey: Keys.followMovedWindow)
        threeFingerSwipe = defaults.object(forKey: Keys.threeFingerSwipe) as? Bool ?? true
        windowSwitchHotKey = Self.migratedWindowSwitchHotKey(from: defaults)
        defaults.removeObject(forKey: Keys.windowSwitchEnabled)
        defaults.removeObject(forKey: Keys.showGroupToggleHint)
    }

    /// Folds the retired on/off switch into the shortcut. An enabled switch
    /// without a stored shortcut is a v0.2.x user on the implicit ⌥Tab, who
    /// must keep a working switcher; an explicit off clears the shortcut.
    /// Idempotent: once the switch key is gone the stored shortcut stands.
    private static func migratedWindowSwitchHotKey(from defaults: UserDefaults) -> HotKeySpec? {
        let stored = HotKeySpec.load(from: defaults, key: Keys.windowSwitchHotKey)
        guard let enabled = defaults.object(forKey: Keys.windowSwitchEnabled) as? Bool else {
            return stored
        }
        guard enabled else {
            defaults.removeObject(forKey: Keys.windowSwitchHotKey)
            return nil
        }
        let migrated = stored ?? legacyWindowSwitchHotKey
        migrated.store(in: defaults, key: Keys.windowSwitchHotKey)
        return migrated
    }
}
