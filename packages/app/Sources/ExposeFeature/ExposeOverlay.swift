import AeroKitCore
import AppKit
import Observation
import SwiftUI

/// Drives the overview's in/out motion from the panel side. The edge ties
/// the motion to the gesture that owns each scope — the workspace overview
/// rises from the bottom like Mission Control after a swipe up, app exposé
/// descends from the top after a swipe down — and dismissal plays the same
/// path backwards, so the overlay always leaves the way it came.
@MainActor
@Observable
final class ExposeOverlayMotion {
    enum Edge {
        case bottom
        case top
    }

    var edge: Edge = .bottom
    /// The backdrop's flag, raised the moment the panel is up so the screen
    /// answers the gesture instantly, while the grid still waits for its
    /// pictures.
    var veiled = false
    var shown = false
}

/// Hosts the SwiftUI overview in a borderless, non-activating panel that
/// covers one screen, and translates panel events into session actions.
@MainActor
final class ExposeOverlay {
    var onActivate: ((Int) -> Void)?
    var onCancel: (() -> Void)?
    var onMove: ((SelectionMove) -> Void)?
    var onHover: ((Int) -> Void)?
    var onToggleGrouping: (() -> Void)?
    /// ⌘W on the selected tile.
    var onCloseSelected: (() -> Void)?
    /// ⇧1–9: send the selected tile's window to the workspace named by the
    /// digit.
    var onMoveSelectedToWorkspace: ((String) -> Void)?
    /// A tile dropped on a workspace chip.
    var onMoveToWorkspace: ((CGWindowID, String) -> Void)?
    /// Key that toggles app grouping; quick select skips it so they can't
    /// collide.
    var groupToggleKey: Character = "0"

    private let panel: OverlayPanel
    private let motion = ExposeOverlayMotion()
    private var session: ExposeSession?
    private var mouseLocationAtShow = NSPoint.zero
    /// Pending order-out at the end of the exit animation; non-nil while
    /// the overlay is on its way off screen.
    private var hideTask: Task<Void, Never>?

    /// False as soon as the exit animation starts — to its callers the
    /// overview is already gone, and a new trigger then re-presents it.
    var isVisible: Bool {
        panel.isVisible && hideTask == nil
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

    func show(
        session: ExposeSession,
        on screen: NSScreen,
        showsGroupingHint: Bool,
        slidesFrom edge: ExposeOverlayMotion.Edge
    ) {
        hideTask?.cancel()
        hideTask = nil
        self.session = session
        motion.edge = edge
        motion.veiled = false
        motion.shown = false
        let view = ExposeOverlayView(
            session: session,
            motion: motion,
            quickSelectExclusion: groupToggleKey,
            showsGroupingHint: showsGroupingHint,
            onActivate: { [weak self] index in self?.onActivate?(index) },
            onHover: { [weak self] index in self?.hover(index) },
            onCancel: { [weak self] in self?.onCancel?() },
            onToggleGrouping: { [weak self] in self?.onToggleGrouping?() },
            onMoveToWorkspace: { [weak self] id, workspace in self?.onMoveToWorkspace?(id, workspace) }
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.setFrame(screen.frame, display: true)
        mouseLocationAtShow = NSEvent.mouseLocation
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        // Next runloop turn, after the hosting view's first frame, so the
        // backdrop fades rather than slamming in.
        Task { @MainActor [motion] in
            motion.veiled = true
        }
    }

    /// Starts the entry cascade. Separate from `show` so the controller can
    /// hold the grid (the backdrop is already dimming) until the preview
    /// captures are in — the cascade then rises with real pictures instead
    /// of icon placeholders that pop into images mid-flight. Idempotent:
    /// the captures-done signal and the safety deadline can both call it.
    func beginEntry() {
        guard panel.isVisible, hideTask == nil else {
            return
        }
        motion.shown = true
    }

    /// Plays the entry backwards — the grid retreats toward the edge it
    /// came from — and only then takes the panel off screen.
    func hide() {
        guard hideTask == nil else {
            return
        }
        // A backdrop-only overlay (cancelled before its pictures arrived)
        // still fades out rather than popping off.
        guard panel.isVisible, motion.shown || motion.veiled else {
            orderOut()
            return
        }
        motion.veiled = false
        motion.shown = false
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(ExposeOverlayView.exitMilliseconds))
            guard let self, !Task.isCancelled else {
                return
            }
            hideTask = nil
            orderOut()
        }
    }

    private func orderOut() {
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

    // A flat key-dispatch switch: each branch is independent, so the
    // complexity count reflects the number of bound keys, not tangled logic.
    // A disable region rather than `:next` keeps the doc comment attached to
    // the declaration.
    // swiftlint:disable cyclomatic_complexity
    /// Swallows every key while the overview is up; unbound keys are
    /// ignored rather than passed to the window behind.
    private func handleKey(_ event: NSEvent) -> Bool {
        // The panel stays up through the exit animation; keys arriving then
        // belong to nothing — swallow them without acting.
        guard hideTask == nil else {
            return true
        }
        // Caps Lock rides along in the flags and must not break matching.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        if flags.contains(.command) {
            if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
                onCloseSelected?()
            }
            // Swallow every ⌘ combo so ⌘+letter never falls into quick
            // select.
            return true
        }
        // ⇧1 types "!", so the digit comes from the key code, not the
        // character. Exact-match on shift keeps ⇧Tab on the tab case below
        // and leaves ⌥digit to the event tap.
        if flags == .shift, let digit = ExposeDigitInterceptor.digit(for: Int64(event.keyCode)) {
            onMoveSelectedToWorkspace?(String(digit))
            return true
        }
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
            handleCharacterKey(event)
        }
        return true
    }

    // swiftlint:enable cyclomatic_complexity

    private func handleCharacterKey(_ event: NSEvent) {
        guard let character = event.charactersIgnoringModifiers?.first else {
            return
        }
        if String(character).uppercased() == String(groupToggleKey).uppercased() {
            onToggleGrouping?()
        } else if let index = quickSelectIndex(for: character) {
            onActivate?(index)
        }
    }

    private func quickSelectIndex(for character: Character) -> Int? {
        guard let index = QuickSelect.index(for: character, excluding: groupToggleKey),
              let session,
              session.tiles.indices.contains(index)
        else {
            return nil
        }
        return index
    }
}
