import AppKit
import Foundation

private let log = AppLog(category: "core")

public enum ApplicationRelauncher {
    @MainActor
    public static func relaunch() {
        let appPath = Bundle.main.bundleURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let command = "sleep 0.5; /usr/bin/open -gj '\(appPath)'"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        do {
            try process.run()
        } catch {
            log.error("failed to relaunch application: \(error)")
            return
        }

        NSApp.terminate(nil)
    }
}
