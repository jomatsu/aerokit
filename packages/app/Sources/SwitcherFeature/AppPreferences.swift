import AeroKitCore
import Combine
import Foundation

public enum SnapshotRefreshFrequency: String, CaseIterable, Identifiable, Sendable {
    case every30Seconds
    case everyMinute
    case every3Minutes
    case every10Minutes

    public var id: String {
        rawValue
    }

    /// Snapshots older than this are refreshed when the switcher opens.
    public var staleInterval: TimeInterval {
        switch self {
        case .every30Seconds: 30
        case .everyMinute: 60
        case .every3Minutes: 180
        case .every10Minutes: 600
        }
    }

    /// Minimum spacing between automatic background refreshes.
    public var minInterval: TimeInterval {
        switch self {
        case .every30Seconds: 15
        case .everyMinute: 30
        case .every3Minutes: 60
        case .every10Minutes: 120
        }
    }

    public var label: String {
        switch self {
        case .every30Seconds: "Every 30 seconds"
        case .everyMinute: "Every minute"
        case .every3Minutes: "Every 3 minutes"
        case .every10Minutes: "Every 10 minutes"
        }
    }

    public var shortLabel: String {
        switch self {
        case .every30Seconds: "30 s"
        case .everyMinute: "1 min"
        case .every3Minutes: "3 min"
        case .every10Minutes: "10 min"
        }
    }
}

@MainActor
public final class AppPreferences: ObservableObject {
    @Published public var autoRefresh: Bool {
        didSet { defaults.set(autoRefresh, forKey: Keys.autoRefresh) }
    }

    @Published public var refreshFrequency: SnapshotRefreshFrequency {
        didSet { defaults.set(refreshFrequency.rawValue, forKey: Keys.refreshFrequency) }
    }

    /// Comma- or newline-separated app names / bundle ids whose windows never
    /// enter saved snapshots (password managers, banking apps, …).
    @Published public var snapshotExcludedApps: String {
        didSet { defaults.set(snapshotExcludedApps, forKey: Keys.excludedApps) }
    }

    /// cmd-tab style: releasing the trigger modifier commits the selection.
    /// Off, the overlay stays open until Return/click/quick-select.
    @Published public var switchOnRelease: Bool {
        didSet { defaults.set(switchOnRelease, forKey: Keys.switchOnRelease) }
    }

    /// Opening the switcher pre-selects the adjacent workspace instead of the
    /// current one, so a quick tap of the hotkey moves one workspace over.
    @Published public var preselectNextOnOpen: Bool {
        didSet { defaults.set(preselectNextOnOpen, forKey: Keys.preselectNextOnOpen) }
    }

    @Published public var hideEmptyWorkspaces: Bool {
        didSet { defaults.set(hideEmptyWorkspaces, forKey: Keys.hideEmptyWorkspaces) }
    }

    @Published public var gridColumns: Int {
        didSet { defaults.set(gridColumns, forKey: Keys.gridColumns) }
    }

    @Published public var showOverlayHints: Bool {
        didSet { defaults.set(showOverlayHints, forKey: Keys.showOverlayHints) }
    }

    @Published public var hotKey: HotKeySpec {
        didSet { hotKey.store(in: defaults, key: Keys.hotKey) }
    }

    @Published public var refreshShortcut: HotKeySpec {
        didSet { refreshShortcut.store(in: defaults, key: Keys.refreshShortcut) }
    }

    @Published public var settingsShortcut: HotKeySpec {
        didSet { settingsShortcut.store(in: defaults, key: Keys.settingsShortcut) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let autoRefresh = "snapshot.autoRefresh"
        static let refreshFrequency = "snapshot.refreshFrequency"
        static let excludedApps = "snapshot.excludedApps"
        static let switchOnRelease = "switcher.switchOnRelease"
        static let preselectNextOnOpen = "switcher.preselectNextOnOpen"
        static let hideEmptyWorkspaces = "switcher.hideEmptyWorkspaces"
        static let gridColumns = "switcher.gridColumns"
        static let showOverlayHints = "switcher.showOverlayHints"
        static let hotKey = "switcher.hotKey"
        static let refreshShortcut = "switcher.refreshShortcut"
        static let settingsShortcut = "switcher.settingsShortcut"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoRefresh = defaults.object(forKey: Keys.autoRefresh) as? Bool ?? true
        refreshFrequency = defaults.string(forKey: Keys.refreshFrequency)
            .flatMap(SnapshotRefreshFrequency.init) ?? .every3Minutes
        snapshotExcludedApps = defaults.string(forKey: Keys.excludedApps) ?? ""
        switchOnRelease = defaults.bool(forKey: Keys.switchOnRelease)
        // Pre-selection used to be implied by switchOnRelease; inherit it for
        // existing cmd-tab-style users and pin it immediately so the two
        // settings stay independent from now on.
        if let stored = defaults.object(forKey: Keys.preselectNextOnOpen) as? Bool {
            preselectNextOnOpen = stored
        } else {
            let inherited = defaults.bool(forKey: Keys.switchOnRelease)
            preselectNextOnOpen = inherited
            defaults.set(inherited, forKey: Keys.preselectNextOnOpen)
        }
        hideEmptyWorkspaces = defaults.bool(forKey: Keys.hideEmptyWorkspaces)
        let storedColumns = defaults.integer(forKey: Keys.gridColumns)
        gridColumns = (2 ... 6).contains(storedColumns) ? storedColumns : 4
        showOverlayHints = defaults.object(forKey: Keys.showOverlayHints) as? Bool ?? true
        hotKey = HotKeySpec.load(from: defaults, key: Keys.hotKey) ?? .default
        refreshShortcut = HotKeySpec.load(from: defaults, key: Keys.refreshShortcut) ?? .defaultRefresh
        settingsShortcut = HotKeySpec.load(from: defaults, key: Keys.settingsShortcut) ?? .defaultSettings
    }

    /// Lowercased match tokens parsed from `snapshotExcludedApps`.
    public var snapshotExclusions: Set<String> {
        Set(
            snapshotExcludedApps
                .split(whereSeparator: { $0 == "," || $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
        )
    }
}
