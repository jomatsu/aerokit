import AppKit
import Foundation

private let log = AppLog(category: "core")

public enum ApplicationRelauncher {
    @MainActor
    public static func relaunch() {
        let appPath = Bundle.main.bundleURL.path.replacingOccurrences(of: "'", with: "'\\''")

        // The new instance's duplicate-instance guard (AeroKit/main.swift) exits
        // immediately if it sees any other process with our bundle ID still
        // running. A fixed `sleep` before `open` raced that guard: if the old
        // process outlived the sleep, the fresh copy spotted it and killed
        // itself, so the app silently vanished — the exact moment this matters,
        // right after granting Screen Recording and hitting "Relaunch to Apply".
        // Instead, wait for THIS process to actually exit (kill -0 fails once the
        // pid is gone) before launching. The shell is orphaned when we terminate
        // but keeps running, so the loop reliably observes our exit. Cap the wait
        // at ~10s so a hung-but-alive old process still eventually relaunches
        // rather than blocking forever.
        let pid = ProcessInfo.processInfo.processIdentifier
        let command =
            "for _ in $(seq 1 100); do /bin/kill -0 \(pid) 2>/dev/null || break; sleep 0.1; done; "
                + "/usr/bin/open -gj '\(appPath)'"

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
