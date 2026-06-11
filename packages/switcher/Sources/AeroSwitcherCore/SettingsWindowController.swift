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
                contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "AeroSwitcher"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.contentView = hostingView
            window.isReleasedWhenClosed = false
            window.setContentSize(hostingView.fittingSize)
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
