import Foundation

/// One-time copy of AeroSwitcher-era preferences into the AeroKit domain so
/// the unification doesn't reset anyone's hotkeys or refresh settings.
enum PreferencesMigration {
    private static let markerKey = "migratedFromAeroSwitcher"
    private static let legacyDomain = "com.nasubikun.aeroswitcher"

    /// All keys AeroSwitcher ever persisted; copied verbatim because the
    /// storage formats are unchanged.
    private static let legacyKeys = [
        "snapshot.autoRefresh",
        "snapshot.refreshFrequency",
        "switcher.switchOnRelease",
        "switcher.hideEmptyWorkspaces",
        "switcher.gridColumns",
        "switcher.showOverlayHints",
        "switcher.hotKey",
        "switcher.refreshShortcut",
        "switcher.settingsShortcut"
    ]

    static func migrateIfNeeded(into defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: markerKey) else {
            return
        }
        defaults.set(true, forKey: markerKey)

        guard let legacy = UserDefaults(suiteName: legacyDomain) else {
            return
        }
        for key in legacyKeys where defaults.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }
}
