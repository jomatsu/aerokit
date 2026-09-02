import AeroKitCore
import AppKit
import Foundation

/// `deliverImmediately` is required: the running instance is a background
/// (accessory) app, and suspended apps only receive coalesced distributed
/// notifications once they become active — which a menu-bar app never does.
private func postAndExit(_ name: Notification.Name, userInfo: [String: String]? = nil) -> Never {
    DistributedNotificationCenter.default().postNotificationName(
        name,
        object: nil,
        userInfo: userInfo,
        deliverImmediately: true
    )
    exit(0)
}

/// AeroSpace hands the exec-on-workspace-change hook the changed
/// workspaces in the environment; the running instance re-reads focus
/// itself, so the payload is informational.
private func workspaceChangeUserInfo() -> [String: String] {
    let environment = ProcessInfo.processInfo.environment
    var userInfo: [String: String] = [:]
    // Both names appear across AeroSpace builds/versions; the running app
    // re-reads focus itself, so this payload is informational.
    let workspace = environment["AEROSPACE_WORKSPACE"]
        ?? environment["AEROSPACE_FOCUSED_WORKSPACE"]
    if let workspace, !workspace.isEmpty {
        userInfo["workspace"] = workspace
    }
    if let previous = environment["AEROSPACE_PREV_WORKSPACE"], !previous.isEmpty {
        userInfo["previous"] = previous
    }
    return userInfo
}

if CommandLine.arguments.contains("--version") {
    print("AeroKit \(AppVersion.current)")
    exit(0)
}

if CommandLine.arguments.contains("--open-settings") {
    postAndExit(AeroKitNotification.openSettings)
}

if CommandLine.arguments.contains("--toggle-expose") {
    postAndExit(AeroKitNotification.toggleExpose)
}

if CommandLine.arguments.contains("--toggle-app-expose") {
    postAndExit(AeroKitNotification.toggleAppExpose)
}

if CommandLine.arguments.contains("--workspace-changed") {
    postAndExit(AeroKitNotification.workspaceChanged, userInfo: workspaceChangeUserInfo())
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var observers: [any NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two instances would register duplicate Carbon hotkeys and event
        // taps. LaunchServices dedups `open` launches of the same bundle;
        // this catches raw-binary or second-copy launches it doesn't see.
        let current = NSRunningApplication.current
        let executableName = current.executableURL?.lastPathComponent
        let duplicate = NSWorkspace.shared.runningApplications.contains { app in
            guard app.processIdentifier != current.processIdentifier else { return false }
            if app.bundleIdentifier == current.bundleIdentifier {
                return true
            }
            // Dev ("AeroKit Dev") and release ("AeroKit") installs use
            // different bundle identifiers on purpose, but they fight over
            // the same hotkeys and event taps — the shared name family
            // means the other install is running.
            if let executableName, executableName.hasPrefix("AeroKit"),
               app.executableURL?.lastPathComponent.hasPrefix("AeroKit") == true
            {
                return true
            }
            return false
        }
        if duplicate {
            fputs("AeroKit: another instance is already running; exiting\n", stderr)
            exit(0)
        }

        NSApp.setActivationPolicy(.accessory)
        // A launcher may have started us hidden (`open -j`); a hidden app
        // shows no windows at all, so the exposé overlay and the swipe HUD
        // would silently never appear. Accessory apps own no key focus, so
        // unhiding steals nothing.
        NSApp.unhide(nil)

        let coordinator = AppCoordinator()
        coordinator.start()
        self.coordinator = coordinator

        observers.append(observe(AeroKitNotification.openSettings) { [weak self] _ in
            self?.coordinator?.showSettings()
        })
        observers.append(observe(AeroKitNotification.toggleExpose) { [weak self] _ in
            self?.coordinator?.toggleExpose()
        })
        observers.append(observe(AeroKitNotification.toggleAppExpose) { [weak self] _ in
            self?.coordinator?.toggleAppExpose()
        })
        observers.append(observe(AeroKitNotification.workspaceChanged) { [weak self] userInfo in
            self?.coordinator?.showWorkspaceChangeHUD(
                workspace: userInfo["workspace"],
                previous: userInfo["previous"]
            )
        })
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Distributed payloads are plain strings here, so the observer hands
    /// the handler a Sendable dictionary instead of the non-Sendable
    /// Notification — the values are extracted on the posting hop's queue
    /// before the main-actor task captures them.
    private func observe(
        _ name: Notification.Name,
        _ handler: @escaping @MainActor ([String: String]) -> Void
    ) -> any NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { notification in
            let userInfo = notification.userInfo as? [String: String]
            Task { @MainActor in
                handler(userInfo ?? [:])
            }
        }
    }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
