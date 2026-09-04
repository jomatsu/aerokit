import AppKit
import SwiftUI

/// SwiftUI's verbose disable-animations transaction dance, named.
@MainActor
func withoutAnimation(_ body: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, body)
}

/// Floating workspace strip that tracks the swipe gesture: every workspace
/// shows as a small snapshot card and a single selection block glides under
/// the fingers' progress, springing onto the landing workspace at release.
/// Consecutive swipes reuse the panel so the selection keeps gliding
/// instead of re-appearing.
@MainActor
final class SwipeHUD {
    /// How long the strip stays up after a gesture settles: long enough to
    /// confirm the landing workspace, short enough to feel dismissed by the
    /// hand leaving the trackpad.
    private static let displayDuration: Duration = .milliseconds(450)
    /// Distance from the bottom edge of the screen's visible frame.
    private static let bottomOffset: CGFloat = 80
    /// Derived from the view's own metrics — panel, shadow room below,
    /// a little headroom above — so window and layout can't drift apart.
    private static let stripHeight: CGFloat =
        SwipeHUDView.panelHeight + SwipeHUDView.bottomPadding + 8

    private let model = SwipeHUDModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    /// A gesture is in flight: show the strip and keep it up — no hide
    /// timer runs until the gesture settles.
    func beginInteractive(
        workspaces: [String],
        current: String,
        previews: [String: NSImage],
        wrapsAround: Bool
    ) {
        hideTask?.cancel()
        hideTask = nil
        present(workspaces: workspaces, current: current, previews: previews, wrapsAround: wrapsAround)
    }

    /// Icons arrive from their own load, possibly after the strip is
    /// already up (or even settling) — the cards fill in as they land.
    func updateIcons(_ icons: [String: [NSImage]]) {
        model.icons = icons
    }

    /// Finger-attached selection position, in cards from the current one.
    func setOffset(_ offset: CGFloat) {
        guard panel?.isVisible == true else {
            return
        }
        // A wrap-around pass through the strip's end teleports the selection
        // to the other side; animating that change would fly it across every
        // card in between instead.
        let travel = abs(model.position(forOffset: offset) - model.selectionPosition)
        if travel > CGFloat(max(model.workspaces.count, 1)) / 2 {
            withoutAnimation {
                model.offset = offset
            }
        } else {
            withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.9)) {
                model.offset = offset
            }
        }
    }

    /// The gesture released: spring the selection onto the outcome — the
    /// new workspace, or back where it started on a cancel — then schedule
    /// the fade-out. Also shows the strip when a flick ended before the
    /// workspace ring had arrived to open it.
    func settle(
        workspaces: [String],
        current: String,
        previews: [String: NSImage],
        wrapsAround: Bool
    ) {
        present(workspaces: workspaces, current: current, previews: previews, wrapsAround: wrapsAround)
        scheduleHide()
    }

    /// Immediate dismissal (the feature or the HUD was turned off); also
    /// releases the panel and its hosting view until the next swipe.
    func hide() {
        hideTask?.cancel()
        hideTask = nil
        model.isVisible = false
        panel?.orderOut(nil)
        panel = nil
    }

    private func present(
        workspaces: [String],
        current: String,
        previews: [String: NSImage],
        wrapsAround: Bool
    ) {
        let panel = ensurePanel()
        position(panel)

        // Skip the glide animation when the strip starts hidden — the
        // selection would visibly travel during the fade-in otherwise. The
        // panel's visibility, not the model's, is the cue: mid fade-out the
        // strip is still on screen and the selection should keep gliding.
        model.update(
            workspaces: workspaces,
            current: current,
            previews: previews,
            wrapsAround: wrapsAround,
            animated: panel.isVisible
        )
        panel.orderFrontRegardless()
        model.isVisible = true
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.displayDuration)
            guard let self, !Task.isCancelled else { return }
            model.isVisible = false
            // Let the fade-out finish before the panel leaves the screen.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
        }
    }

    /// The panel is a full-width transparent strip with the cards centered
    /// inside, so changing workspace sets never needs a fitting-size pass.
    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = NSHostingView(rootView: SwipeHUDView(model: model))
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        // NSScreen.main is the screen with keyboard focus, which is where
        // AeroSpace switches workspaces.
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }
        let visible = screen.visibleFrame
        panel.setFrame(
            NSRect(
                x: visible.minX,
                y: visible.minY + Self.bottomOffset,
                width: visible.width,
                height: Self.stripHeight
            ),
            display: false
        )
    }
}
