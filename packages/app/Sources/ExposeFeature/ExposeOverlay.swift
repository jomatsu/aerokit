import AeroKitCore
import AppKit
import SwiftUI

/// Hosts the SwiftUI overview in a borderless, non-activating panel that
/// covers one screen, and translates panel events into session actions.
@MainActor
final class ExposeOverlay {
    var onActivate: ((Int) -> Void)?
    var onCancel: (() -> Void)?
    var onMove: ((SelectionMove) -> Void)?
    var onHover: ((Int) -> Void)?

    private let panel: OverlayPanel
    private var session: ExposeSession?
    private var mouseLocationAtShow = NSPoint.zero

    var isVisible: Bool {
        panel.isVisible
    }

    init() {
        panel = OverlayPanel(contentRect: .zero)
        panel.keyHandler = { [weak self] event in
            self?.handleKey(event) ?? false
        }
        panel.onResignKey = { [weak self] in
            // orderOut also resigns key; only a still-visible panel losing
            // key (e.g. Cmd-Tab away) should dismiss the overview.
            guard let self, panel.isVisible else {
                return
            }
            onCancel?()
        }
    }

    func show(session: ExposeSession, on screen: NSScreen) {
        self.session = session
        let view = ExposeOverlayView(
            session: session,
            onActivate: { [weak self] index in self?.onActivate?(index) },
            onHover: { [weak self] index in self?.hover(index) },
            onCancel: { [weak self] in self?.onCancel?() }
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.setFrame(screen.frame, display: true)
        mouseLocationAtShow = NSEvent.mouseLocation
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        // Drop the hosting view so the preview images release promptly.
        panel.contentView = nil
        session = nil
    }

    /// The overlay opens under the cursor, so a tile can receive a hover
    /// without any user intent; require actual mouse travel first.
    private func hover(_ index: Int) {
        let location = NSEvent.mouseLocation
        let distance = hypot(location.x - mouseLocationAtShow.x, location.y - mouseLocationAtShow.y)
        guard distance > 4 else {
            return
        }
        onHover?(index)
    }

    /// Swallows every key while the overview is up; unbound keys are
    /// ignored rather than passed to the window behind.
    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case KeyCode.escape:
            onCancel?()
        case KeyCode.return, KeyCode.keypadEnter, KeyCode.space:
            if let session {
                onActivate?(session.selectedIndex)
            }
        case KeyCode.leftArrow:
            onMove?(.left)
        case KeyCode.rightArrow:
            onMove?(.right)
        case KeyCode.upArrow:
            onMove?(.up)
        case KeyCode.downArrow:
            onMove?(.down)
        case KeyCode.tab:
            onMove?(event.modifierFlags.contains(.shift) ? .previous : .next)
        default:
            if let index = quickSelectIndex(from: event) {
                onActivate?(index)
            }
        }
        return true
    }

    private func quickSelectIndex(from event: NSEvent) -> Int? {
        guard let character = event.charactersIgnoringModifiers?.first,
              let index = QuickSelect.index(for: character),
              let session,
              session.tiles.indices.contains(index)
        else {
            return nil
        }
        return index
    }
}
