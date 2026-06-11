import AppKit
import CoreGraphics

/// `@unchecked` carrier that ferries the non-Sendable CGEvent into
/// `MainActor.assumeIsolated` inside the tap callback.
private struct EventBox: @unchecked Sendable {
    let event: CGEvent
}

/// Claims Option+1–9 while the overview is open so the digits select
/// overview windows instead of triggering AeroSpace's own workspace
/// bindings. Implemented as a consuming session event tap inserted at the
/// head of the chain, so the events never reach AeroSpace. Requires
/// Accessibility trust; `start()` fails (returns false) without it.
@MainActor
final class ExposeDigitInterceptor {
    var onDigit: ((Int) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    @discardableResult
    func start() -> Bool {
        guard tap == nil else {
            return true
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let interceptor = Unmanaged<ExposeDigitInterceptor>.fromOpaque(refcon).takeUnretainedValue()
                // The run loop source lives on the main run loop, so the
                // callback always arrives on the MainActor's thread. The box
                // ferries the non-Sendable CGEvent across assumeIsolated.
                let box = EventBox(event: event)
                let consumed = MainActor.assumeIsolated {
                    interceptor.handle(type: type, event: box.event)
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        self.tap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    /// Returns true when the event was consumed. Keyboard taps get disabled
    /// by the system if a callback stalls; re-enable so a hiccup doesn't
    /// kill the feature for the session.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        }

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
