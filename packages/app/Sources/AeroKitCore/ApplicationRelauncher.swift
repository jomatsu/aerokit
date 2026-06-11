import AppKit
import Foundation

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
            fputs("Failed to relaunch application: \(error)\n", stderr)
            return
        }

        NSApp.terminate(nil)
    }
}
