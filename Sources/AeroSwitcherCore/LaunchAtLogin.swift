import AppKit
import Foundation

/// Manages the LaunchAgent that `scripts/install-app.sh` also writes, so the
/// settings toggle and the installer stay in agreement about the same plist.
enum LaunchAtLogin {
    private static let label = "com.nasubikun.aeroswitcher"

    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// Only meaningful when running from an installed .app bundle.
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: agentURL.path)
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            enable()
        } else {
            disable()
        }
    }

    private static func enable() {
        let appPath = Bundle.main.bundleURL.path
        let logDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AeroSwitcher")
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: agentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-gj", appPath],
            "RunAtLoad": true,
            "StandardOutPath": logDirectory.appendingPathComponent("stdout.log").path,
            "StandardErrorPath": logDirectory.appendingPathComponent("stderr.log").path
        ]

        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        ) else {
            return
        }

        try? data.write(to: agentURL)
        runLaunchctl(["bootstrap", "gui/\(getuid())", agentURL.path])
    }

    private static func disable() {
        runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: agentURL)
    }

    private static func runLaunchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            fputs("launchctl \(arguments.joined(separator: " ")) failed to start: \(error)\n", stderr)
            return
        }
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            fputs("launchctl \(arguments.joined(separator: " ")) exited with \(process.terminationStatus)\n", stderr)
        }
    }
}
