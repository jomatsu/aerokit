import AppKit

@MainActor
final class StatusBarController: NSObject {
    var onOpenSettings: (() -> Void)?
    var onRefreshSnapshots: (() -> Void)?
    var onQuit: (() -> Void)?

    private var statusItem: NSStatusItem?

    func start() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "AS"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        ))
        menu.addItem(NSMenuItem(
            title: "Refresh Snapshots",
            action: #selector(refreshSnapshots),
            keyEquivalent: "r"
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit AeroSwitcher",
            action: #selector(quit),
            keyEquivalent: "q"
        ))

        for item in menu.items {
            item.target = self
        }

        item.menu = menu
        statusItem = item
    }

    @objc
    private func openSettings() {
        onOpenSettings?()
    }

    @objc
    private func refreshSnapshots() {
        onRefreshSnapshots?()
    }

    @objc
    private func quit() {
        onQuit?()
    }
}
