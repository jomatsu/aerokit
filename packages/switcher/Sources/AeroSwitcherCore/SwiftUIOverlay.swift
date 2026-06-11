import AppKit
import SwiftUI

@MainActor
public final class SwiftUIOverlay: ObservableObject {
    @Published public private(set) var items: [WorkspacePresentation] = []
    @Published public private(set) var selectedIndex = 0
    @Published public private(set) var snapshotFeedback: SnapshotRefreshFeedback = .idle
    @Published public private(set) var isShown = false

    public var onAdvance: (() -> Void)?
    public var onMove: ((SelectionMove) -> Void)?
    public var onSelect: (() -> Void)?
    public var onQuickSelect: ((String) -> Void)?
    public var onActivateWorkspace: ((String) -> Void)?
    public var onHoverSelect: ((Int) -> Void)?
    public var onReloadSnapshots: (() -> Void)?
    public var onOpenSettings: (() -> Void)?
    public var onCancel: (() -> Void)?
    public var onModifierRelease: (() -> Void)?

    private let configuration: SwitcherConfiguration
    private let preferences: AppPreferences
    private let panel: OverlayPanel
    private var hostingView: NSHostingView<SwitcherOverlayView>?
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var triggerModifiersHeldSinceShow = false
    private var mouseLocationAtShow = NSPoint.zero

    public var isVisible: Bool {
        panel.isVisible
    }

    public init(configuration: SwitcherConfiguration, preferences: AppPreferences) {
        self.configuration = configuration
        self.preferences = preferences
        panel = OverlayPanel(contentRect: .zero)
        panel.keyHandler = { [weak self] event in
            self?.handleKey(event) ?? false
        }
    }

    public func show(
        items: [WorkspacePresentation],
        selectedIndex: Int,
        snapshotFeedback: SnapshotRefreshFeedback
    ) {
        update(
            items: items,
            selectedIndex: selectedIndex,
            snapshotFeedback: snapshotFeedback
        )
        ensureHostingView()
        positionPanel()
        // NSEvent.modifierFlags can report empty before this process has
        // received its first NSEvent (e.g. the very first show after launch,
        // triggered via a Carbon hotkey), so read the session state directly.
        triggerModifiersHeldSinceShow = Self.modifiersPhysicallyHeld(preferences.hotKey.modifierFlags)
        mouseLocationAtShow = NSEvent.mouseLocation

        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        startDismissMonitors()

        // Flip the flag on the next runloop tick so the entrance transition
        // animates instead of landing in the already-shown state.
        isShown = false
        DispatchQueue.main.async { [weak self] in
            guard let self, panel.isVisible else { return }
            isShown = true
        }
    }

    public func update(
        items: [WorkspacePresentation],
        selectedIndex: Int,
        snapshotFeedback: SnapshotRefreshFeedback
    ) {
        self.items = items
        self.selectedIndex = selectedIndex
        self.snapshotFeedback = snapshotFeedback
    }

    public func hide() {
        stopDismissMonitors()
        isShown = false
        panel.orderOut(nil)
    }

    public func activateWorkspace(named name: String) {
        onActivateWorkspace?(name)
    }

    public func hoverSelect(index: Int) {
        // The overlay opens under the cursor, so a card can receive a hover
        // without any user intent; require actual mouse travel first.
        let location = NSEvent.mouseLocation
        let distance = hypot(location.x - mouseLocationAtShow.x, location.y - mouseLocationAtShow.y)
        guard distance > 4 else {
            return
        }
        onHoverSelect?(index)
    }

    public func cancel() {
        onCancel?()
    }

    private func ensureHostingView() {
        guard hostingView == nil else {
            return
        }

        let view = SwitcherOverlayView(model: self, configuration: configuration, preferences: preferences)
        let hostingView = NSHostingView(rootView: view)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView
        self.hostingView = hostingView
    }

    private func positionPanel() {
        guard let screen = activeScreen() else {
            return
        }

        panel.setFrame(screen.frame, display: true)
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
    }

    private static func modifiersPhysicallyHeld(_ flags: NSEvent.ModifierFlags) -> Bool {
        guard !flags.isEmpty else {
            return false
        }
        let state = CGEventSource.flagsState(.combinedSessionState)
        if flags.contains(.option), !state.contains(.maskAlternate) {
            return false
        }
        if flags.contains(.command), !state.contains(.maskCommand) {
            return false
        }
        if flags.contains(.control), !state.contains(.maskControl) {
            return false
        }
        return true
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        // A keyDown carrying the trigger modifiers proves they are held right
        // now — re-arm release-to-commit even if the initial check missed it.
        let triggerFlags = preferences.hotKey.modifierFlags
        if !triggerFlags.isEmpty, event.modifierFlags.isSuperset(of: triggerFlags) {
            triggerModifiersHeldSinceShow = true
        }

        // Extra modifiers are tolerated by matches(_:) because the trigger
        // modifier is typically still held while the switcher is open.
        if preferences.refreshShortcut.matches(event) {
            onReloadSnapshots?()
            return true
        }

        if preferences.settingsShortcut.matches(event) {
            onOpenSettings?()
            return true
        }

        if handleNavigationKey(event) {
            return true
        }

        if let workspace = quickWorkspace(from: event) {
            onQuickSelect?(workspace)
        } else {
            onCancel?()
        }
        return true
    }

    private func handleNavigationKey(_ event: NSEvent) -> Bool {
        let isShifted = event.modifierFlags.contains(.shift)

        switch event.keyCode {
        case preferences.hotKey.keyCode:
            if isShifted {
                onMove?(.previous)
            } else {
                onAdvance?()
            }
        case KeyCode.return, KeyCode.keypadEnter:
            onSelect?()
        case KeyCode.escape:
            onCancel?()
        case KeyCode.leftArrow:
            onMove?(.left)
        case KeyCode.rightArrow:
            onMove?(.right)
        case KeyCode.downArrow:
            onMove?(.down)
        case KeyCode.upArrow:
            onMove?(.up)
        case KeyCode.tab:
            onMove?(isShifted ? .previous : .next)
        default:
            return false
        }
        return true
    }

    private func quickWorkspace(from event: NSEvent) -> String? {
        guard !event.modifierFlags.contains(.command),
              let characters = event.charactersIgnoringModifiers?.uppercased()
        else {
            return nil
        }
        return items
            .map(\.workspace.name)
            .first { $0.uppercased() == characters }
    }

    private func startDismissMonitors() {
        stopDismissMonitors()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, panel.isVisible else {
                return event
            }
            return handleKey(event) ? nil : event
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, panel.isVisible else {
                return event
            }
            let triggerFlags = preferences.hotKey.modifierFlags
            let held = !triggerFlags.isEmpty && event.modifierFlags.isSuperset(of: triggerFlags)
            // Re-arm whenever the trigger modifier is pressed again, so a
            // quick tap-to-open followed by hold-and-cycle still commits on
            // release instead of silently disarming after the first release.
            if held {
                triggerModifiersHeldSinceShow = true
            } else if triggerModifiersHeldSinceShow {
                triggerModifiersHeldSinceShow = false
                onModifierRelease?()
            }
            return event
        }
    }

    private func stopDismissMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
    }
}

private enum KeyCode {
    static let `return`: UInt16 = 36
    static let tab: UInt16 = 48
    static let escape: UInt16 = 53
    static let keypadEnter: UInt16 = 76
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}

private final class OverlayPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}
