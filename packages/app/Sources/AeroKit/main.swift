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

if CommandLine.arguments.contains("--open-settings") {
    postAndExit(AeroKitNotification.openSettings)
}

if CommandLine.arguments.contains("--toggle-expose") {
    postAndExit(AeroKitNotification.toggleExpose)
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var observers: [any NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let coordinator = AppCoordinator()
        coordinator.start()
        self.coordinator = coordinator

        observers.append(observe(AeroKitNotification.openSettings) { [weak self] in
            self?.coordinator?.showSettings()
        })
        observers.append(observe(AeroKitNotification.toggleExpose) { [weak self] in
            self?.coordinator?.toggleExpose()
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
