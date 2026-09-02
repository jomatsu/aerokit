import CoreGraphics
import Foundation

/// `@unchecked` carrier that ferries the non-Sendable CGEvent into
/// `MainActor.assumeIsolated` inside the tap callback.
private struct EventBox: @unchecked Sendable {
    let event: CGEvent
}

/// A consuming session event tap scoped to one feature session: inserted at
/// the head of the chain so matched events never reach other apps (AeroSpace
/// included), and re-enabled automatically when the system disables it after
/// a stalled callback. Requires Accessibility trust; `start()` fails
/// (returns false) without it. The handler runs on the main actor — the run
/// loop source lives on the main run loop.
@MainActor
public final class ScopedEventTap {
    private let eventsOfInterest: CGEventMask
    private let consume: @MainActor (CGEventType, CGEvent) -> Bool

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// - Parameter consume: returns true when the event was swallowed.
    public init(eventsOfInterest: CGEventMask, consume: @escaping @MainActor (CGEventType, CGEvent) -> Bool) {
        self.eventsOfInterest = eventsOfInterest
        self.consume = consume
    }

    @discardableResult
    public func start() -> Bool {
        guard tap == nil else {
            return true
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: { _, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let tap = Unmanaged<ScopedEventTap>.fromOpaque(refcon).takeUnretainedValue()
                // The box ferries the non-Sendable CGEvent across
                // assumeIsolated.
                let box = EventBox(event: event)
                let consumed = MainActor.assumeIsolated {
                    tap.handle(type: type, event: box.event)
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

    public func stop() {
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

    /// Keyboard taps get disabled by the system if a callback stalls;
    /// re-enable so a hiccup doesn't kill the feature for the session.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        }
        return consume(type, event)
    }
}
