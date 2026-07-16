import Foundation
import ServiceManagement

private let log = AppLog(category: "core")

/// Launch-at-login backed by `SMAppService`, so the app registers as a real
/// Login Item. Unlike the old hand-written LaunchAgent, the state can't drift
/// when the user toggles the item from System Settings › Login Items.
public enum LaunchAtLogin {
    /// Set once we've registered/unregistered on the user's behalf. Lets a
    /// fresh install opt into launch-at-login exactly once (matching the old
    /// installer) while leaving the user's later choice untouched.
    private static let configuredKey = "launchAtLogin.configured"

    /// The label/plist the previous installer and app version managed.
    private static let legacyLabel = "com.nasubikun.aerokit"

    private static var legacyAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(legacyLabel).plist")
    }

    /// `SMAppService` needs a real bundle; a bare binary can't register.
    public static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(true, forKey: configuredKey)
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("SMAppService \(enabled ? "register" : "unregister") failed: \(error)")
        }
    }

    /// One-time reconciliation on launch. Retires the old installer's
    /// LaunchAgent and, for fresh installs, opts into launch-at-login once.
    /// Idempotent and cheap on later launches — the marker is checked first.
    public static func migrateIfNeeded() {
        guard isAvailable else { return }

        let defaults = UserDefaults.standard

        if FileManager.default.fileExists(atPath: legacyAgentURL.path) {
            // Boot the old job out (a non-zero exit just means it already
            // stopped) and drop its plist, then hand its enabled state to
            // SMAppService so the user keeps launch-at-login across the upgrade.
            runLaunchctl(["bootout", "gui/\(getuid())/\(legacyLabel)"])
            try? FileManager.default.removeItem(at: legacyAgentURL)
            register()
            defaults.set(true, forKey: configuredKey)
            return
        }

        // First run with no legacy agent: the old installer enabled
        // launch-at-login unconditionally, so match that for fresh installs.
        // The user can flip it off in Settings or System Settings › Login Items
        // (macOS shows a notification when a login item is added).
        guard !defaults.bool(forKey: configuredKey) else { return }
        register()
        defaults.set(true, forKey: configuredKey)
    }

    private static func register() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            log.error("SMAppService register failed: \(error)")
        }
    }

    private static func runLaunchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            log.error("launchctl \(arguments.joined(separator: " ")) failed to start: \(error)")
            return
        }
        process.waitUntilExit()
    }
}
