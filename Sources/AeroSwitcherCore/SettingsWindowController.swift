import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let model: SwitcherSettingsModel
    private var window: NSWindow?
    private var activationObserver: (any NSObjectProtocol)?

    init(model: SwitcherSettingsModel) {
        self.model = model
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak model] _ in
            Task { @MainActor in
                model?.refreshStatus()
            }
        }
    }

    func show() {
        model.refreshStatus()

        if window == nil {
            let view = SwitcherSettingsView(model: model)
            let hostingView = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "AeroSwitcher Settings"
            window.contentView = hostingView
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
