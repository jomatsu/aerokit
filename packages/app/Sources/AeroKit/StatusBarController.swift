import AeroKitCore
import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    var onShowOverview: (() -> Void)?
    var onShowAppWindows: (() -> Void)?
    var onRefreshSnapshots: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    private var statusItem: NSStatusItem?

    func start() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(
            systemSymbolName: "rectangle.3.group",
            accessibilityDescription: "AeroKit"
        ) {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "AK"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: L10n.tr("Show Window Overview"),
            action: #selector(showOverview),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: L10n.tr("Show App Windows"),
            action: #selector(showAppWindows),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: L10n.tr("Refresh Snapshots"),
            action: #selector(refreshSnapshots),
            keyEquivalent: "r"
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: L10n.tr("Settings..."),
            action: #selector(openSettings),
            keyEquivalent: ","
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: L10n.tr("Quit AeroKit"),
            action: #selector(quit),
            keyEquivalent: "q"
        ))

        for entry in menu.items {
            entry.target = self
        }

        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        let titles = [
            L10n.tr("Show Window Overview"),
            L10n.tr("Show App Windows"),
            L10n.tr("Refresh Snapshots"),
            L10n.tr("Settings..."),
            L10n.tr("Quit AeroKit")
        ]
        for (item, title) in zip(menu.items.filter { !$0.isSeparatorItem }, titles) {
            item.title = title
        }
    }

    @objc
    private func showOverview() {
        onShowOverview?()
    }

    @objc
    private func showAppWindows() {
        onShowAppWindows?()
    }

    @objc
    private func refreshSnapshots() {
        onRefreshSnapshots?()
    }

    @objc
    private func openSettings() {
        onOpenSettings?()
    }

    @objc
    private func quit() {
        onQuit?()
    }
}
