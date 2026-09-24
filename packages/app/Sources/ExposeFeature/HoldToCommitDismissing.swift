import AeroKitCore
import AppKit

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

extension HoldToCommitDismiss: HoldToCommitDismissing {}

extension HotKeyCenter: WindowSwitcherHotKeyRegistering {}
