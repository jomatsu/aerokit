import AeroKitCore
import AppKit
import CoreGraphics

/// Claims Option+1–9 while the overview is open so the digits select
/// overview windows instead of triggering AeroSpace's own workspace
/// bindings. Built on the shared `ScopedEventTap`: a consuming session tap
/// at the head of the chain, so the events never reach AeroSpace. Requires
/// Accessibility trust; `start()` fails (returns false) without it.
@MainActor
final class ExposeDigitInterceptor {
    var onDigit: ((Int) -> Void)?

    /// Lazy so the closure can weakly reference self — a stored property
    /// cannot be captured before two-phase initialization completes.
    private lazy var tap = ScopedEventTap(
        eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue)
    ) { [weak self] type, event in
        self?.handle(type: type, event: event) ?? false
    }

    @discardableResult
    func start() -> Bool {
        tap.start()
    }

    func stop() {
        tap.stop()
    }

    /// Returns true when the event was consumed.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        let flags = event.flags
        guard type == .keyDown,
              flags.contains(.maskAlternate),
              !flags.contains(.maskCommand),
              !flags.contains(.maskControl),
              let digit = Self.digit(for: event.getIntegerValueField(.keyboardEventKeycode))
        else {
            return false
        }

        onDigit?(digit)
        return true
    }

    /// ANSI keyboard layout: number-row key codes are not contiguous.
    static func digit(for keyCode: Int64) -> Int? {
        switch keyCode {
        case 18: 1
        case 19: 2
        case 20: 3
        case 21: 4
        case 23: 5
        case 22: 6
        case 26: 7
        case 28: 8
        case 25: 9
        default: nil
        }
    }
}
