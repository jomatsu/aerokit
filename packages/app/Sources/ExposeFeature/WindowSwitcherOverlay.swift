import AeroKitCore
import AppKit
import SwiftUI

/// Hosts the cycling strip in a borderless, non-activating panel centered
/// on the focused screen. Key routing has two paths: when Accessibility is
/// granted, `WindowCycleInterceptor` sees the events globally and this
/// panel is just a picture; without it, the controller routes this panel's
/// `keyHandler` through the same pure rules while `HoldToCommitDismiss`
/// supplies the release-to-commit.
@MainActor
final class WindowSwitcherOverlay {
    var onCancel: (() -> Void)?
    /// Fallback key routing when no event tap runs.
    var keyHandler: ((NSEvent) -> Bool)?

    private let panel: OverlayPanel
    private var hostingView: NSHostingView<WindowSwitcherStripView>?

    var isVisible: Bool {
        panel.isVisible
    }

    /// True while hide() is ordering the panel out; its resign must not
    /// re-enter onCancel/dismiss mid-teardown.
    private var isHiding = false

    init() {
        panel = OverlayPanel(contentRect: .zero)
        panel.keyHandler = { [weak self] event in
            self?.keyHandler?(event) ?? false
        }
        panel.onResignKey = { [weak self] in
            guard let self, isVisible, !isHiding else { return }
            onCancel?()
        }
    }

    func show(session: WindowCycleSession, cardWidth: CGFloat, on screen: NSScreen) {
        let cardHeight = cardWidth * 9 / 16
        let view = WindowSwitcherStripView(session: session, cardSize: CGSize(width: cardWidth, height: cardHeight))
        let hostingView = NSHostingView(rootView: view)
        panel.contentView = hostingView
        self.hostingView = hostingView

        let count = CGFloat(session.entries.count)
        let contentWidth = WorkspaceCardMetrics.panelPadding * 2
            + cardWidth * count
            + WorkspaceCardMetrics.cellSpacing * max(count - 1, 0)
        let contentHeight = cardHeight
            + WorkspaceCardMetrics.captionSpacing
            + WorkspaceCardMetrics.captionHeight
            + WorkspaceCardMetrics.panelPadding * 2
        panel.setContentSize(NSSize(width: contentWidth, height: contentHeight))

        // Centered, sitting a little below the middle — out of the way of a
        // maximized window's title bar, where the eye already is after a
        // ⌘Tab-style switch.
        let frame = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(x: frame.midX - contentWidth / 2, y: frame.midY - contentHeight / 2 - frame.height * 0.1)
        )
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func hide() {
        isHiding = true
        panel.orderOut(nil)
        isHiding = false
        panel.contentView = nil
        hostingView = nil
    }
}
