import AeroKitCore
import AppKit
import CoreGraphics

/// Consuming session tap that drives the window cycle strip: the trigger
/// key cycles (⇧ reverses), arrows move, Esc cancels, every other key is
/// swallowed so nothing types into the frontmost app, and a flagsChanged
/// that drops the trigger modifiers commits — never consumed, so modifier
/// state reaches the system untouched.
@MainActor
final class WindowCycleInterceptor {
    var onMove: ((SelectionMove) -> Void)?
    var onCancel: (() -> Void)?
    var onCommit: (() -> Void)?

    private let hotKey: HotKeySpec

    /// Lazy so the closure can weakly reference self — a stored property
    /// cannot be captured before two-phase initialization completes.
    private lazy var tap = ScopedEventTap(
        eventsOfInterest: (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
    ) { [weak self] type, event in
        self?.handle(type: type, event: event) ?? false
    }

    init(hotKey: HotKeySpec) {
        self.hotKey = hotKey
    }

    @discardableResult
    func start() -> Bool {
        tap.start()
    }

    func stop() {
        tap.stop()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .flagsChanged:
            let held = event.flags.isSuperset(of: hotKey.cgEventFlags)
            if CycleKeyRules.action(for: .modifiersChanged(triggerHeld: held)) == .commit {
                onCommit?()
            }
            return false
        case .keyDown:
            if let action = Self.action(for: event, hotKey: hotKey) {
                switch action {
                case .advance:
                    onMove?(.next)
                case .retreat:
                    onMove?(.previous)
                case .cancel:
                    onCancel?()
                case .commit, .swallow, .pass:
                    break
                }
            }
            return true
        case .keyUp:
            // Swallow the trigger's key-up so it never types anywhere.
            return true
        default:
            return false
        }
    }

    private static func action(for event: CGEvent, hotKey: HotKeySpec) -> CycleAction? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let kind: CycleKeyInput.Kind = if keyCode == hotKey.keyCode {
            .hotKey
        } else if keyCode == KeyCode.leftArrow {
            .leftArrow
        } else if keyCode == KeyCode.rightArrow {
            .rightArrow
        } else if keyCode == KeyCode.escape {
            .escape
        } else {
            .other
        }
        return CycleKeyRules.action(for: .key(kind, shifted: event.flags.contains(.maskShift)))
    }
}
