import AeroKitCore
import AppKit
import Foundation

/// `deliverImmediately` is required: the running instance is a background
/// (accessory) app, and suspended apps only receive coalesced distributed
/// notifications once they become active — which a menu-bar app never does.
private func postAndExit(_ name: Notification.Name) -> Never {
    DistributedNotificationCenter.default().postNotificationName(
        name,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    exit(0)
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

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var observers: [any NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two instances would register duplicate Carbon hotkeys and event
        // taps. LaunchServices dedups `open` launches of the same bundle;
        // this catches raw-binary or second-copy launches it doesn't see.
        let current = NSRunningApplication.current
        let duplicate = NSWorkspace.shared.runningApplications.contains { app in
            guard app.processIdentifier != current.processIdentifier else { return false }
            if let bundleID = Bundle.main.bundleIdentifier {
                return app.bundleIdentifier == bundleID
            }
            // Raw-binary runs (swift run / .build) have no bundle identifier;
            // match by executable name instead.
            return app.executableURL?.lastPathComponent == "AeroKit"
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

        observers.append(observe(AeroKitNotification.openSettings) { [weak self] in
            self?.coordinator?.showSettings()
        })
        observers.append(observe(AeroKitNotification.toggleExpose) { [weak self] in
            self?.coordinator?.toggleExpose()
        })
        observers.append(observe(AeroKitNotification.toggleAppExpose) { [weak self] in
            self?.coordinator?.toggleAppExpose()
        })
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func observe(
        _ name: Notification.Name,
        _ handler: @escaping @MainActor () -> Void
    ) -> any NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                handler()
            }
        }
    }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
