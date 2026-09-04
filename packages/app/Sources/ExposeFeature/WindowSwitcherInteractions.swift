import AeroKitCore
import AppKit

/// Low-level input and hotkey surfaces the window switcher owns. Live
/// construction wraps the existing interceptor, release detector, and
/// Carbon center; tests supply the same types without a separate control
/// flow.
@MainActor
enum WindowSwitcherInteractions {
    static func cycleTap(hotKey: HotKeySpec) -> any WindowCycleTapping {
        WindowCycleInterceptor(hotKey: hotKey)
    }

    static func holdDismiss(
        triggerFlags: NSEvent.ModifierFlags,
        heldAtShow: Bool
    ) -> any HoldToCommitDismissing {
        HoldToCommitDismiss(triggerFlags: triggerFlags, heldAtShow: heldAtShow)
    }
}

@MainActor
protocol WindowCycleTapping: AnyObject {
    var onMove: ((SelectionMove) -> Void)? { get set }
    var onCancel: (() -> Void)? { get set }
    var onCommit: (() -> Void)? { get set }
    func start() -> Bool
    func stop()
}

@MainActor
protocol HoldToCommitDismissing: AnyObject {
    var onModifierRelease: (() -> Void)? { get set }
    func beginSession()
    func endSession()
    func noteKeyEvent(_ event: NSEvent)
}

@MainActor
protocol WindowSwitcherHotKeyRegistering: AnyObject {
    func register(_ role: HotKeyRole, keyCode: UInt32, modifiers: UInt32) throws
    func unregister(_ role: HotKeyRole)
}

extension WindowCycleInterceptor: WindowCycleTapping {}

extension HoldToCommitDismiss: HoldToCommitDismissing {}

extension HotKeyCenter: WindowSwitcherHotKeyRegistering {}
