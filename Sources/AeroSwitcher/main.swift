import AeroSwitcherCore
import AppKit
import Darwin
import Foundation

if CommandLine.arguments.contains("--open-settings") {
    DistributedNotificationCenter.default().postNotificationName(
        AeroSwitcherNotification.openSettings,
        object: nil
    )
    exit(0)
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: SwitcherController?
    private var openSettingsObserver: (any NSObjectProtocol)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = SwitcherController()
        controller.start()
        self.controller = controller

        openSettingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: AeroSwitcherNotification.openSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.controller?.showSettings()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
