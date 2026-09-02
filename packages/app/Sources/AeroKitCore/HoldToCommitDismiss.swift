import AppKit
import Foundation

/// Release-to-commit detection for hold-to-cycle overlays, shared by the
/// workspace switcher and the window switcher: while the overlay is up,
/// the selection commits when the trigger modifiers are released. A local
/// flagsChanged monitor catches the release while the app owns key focus;
/// a 50 ms physical-state watchdog catches it after focus has moved
/// elsewhere — the local monitor is blind exactly there. The watchdog
/// re-arm logic survives quick tap-to-open followed by hold-and-cycle.
@MainActor
public final class HoldToCommitDismiss {
    /// Fired once when the trigger modifiers were held and then released.
    public var onModifierRelease: (() -> Void)?

    private let triggerFlags: NSEvent.ModifierFlags
    private var flagsMonitor: Any?
    private var watchdog: Timer?
    private var triggerModifiersHeldSinceShow: Bool

    /// - Parameters:
    ///   - triggerFlags: the hotkey's modifier flags (⌘⌥⌃ only, mirroring
    ///     `HotKeySpec.modifierFlags`).
    ///   - heldAtShow: whether the modifiers were held when the overlay
    ///     appeared; a hold-to-cycle overlay opens with them held.
    public init(triggerFlags: NSEvent.ModifierFlags, heldAtShow: Bool) {
        self.triggerFlags = triggerFlags
        triggerModifiersHeldSinceShow = heldAtShow
    }

    /// Whether the trigger modifiers are physically held right now (⌘⌥⌃
    /// via `CGEventSource`, independent of key focus). Only checks
    /// ⌘⌥⌃, mirroring the clamp in `HotKeySpec.modifierFlags`; keep the
    /// two in sync.
    public static func modifiersPhysicallyHeld(_ flags: NSEvent.ModifierFlags) -> Bool {
        guard !flags.isEmpty else {
            return false
        }
        let state = CGEventSource.flagsState(.combinedSessionState)
        if flags.contains(.option), !state.contains(.maskAlternate) {
            return false
        }
        if flags.contains(.command), !state.contains(.maskCommand) {
            return false
        }
        if flags.contains(.control), !state.contains(.maskControl) {
            return false
        }
        return true
    }

    /// A keyDown carrying the trigger modifiers proves they are held right
    /// now — re-arms release-to-commit even if the initial check missed it.
    public func noteKeyEvent(_ event: NSEvent) {
        if !triggerFlags.isEmpty, event.modifierFlags.isSuperset(of: triggerFlags) {
            triggerModifiersHeldSinceShow = true
        }
    }

    /// Installs the local flagsChanged monitor and starts the watchdog.
    public func beginSession() {
        stopMonitors()

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else {
                return event
            }
            _ = noteFlagsChanged(event)
            return event
        }

        // The local monitor only sees events while this app owns the key
        // window; a release that happens after focus moved elsewhere would
        // otherwise never commit. Poll the physical state as a fallback.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkWatchdog()
            }
        }
        // .common so the poll keeps running during event tracking (drags,
        // menus) — exactly the situations where the local monitor is blind.
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    public func endSession() {
        stopMonitors()
        triggerModifiersHeldSinceShow = false
    }

    /// Feed a flagsChanged event manually (e.g. from a global tap);
    /// returns true when the release fired.
    @discardableResult
    public func noteFlagsChanged(_ event: NSEvent) -> Bool {
        let held = !triggerFlags.isEmpty && event.modifierFlags.isSuperset(of: triggerFlags)
        // Re-arm whenever the trigger modifier is pressed again, so a
        // quick tap-to-open followed by hold-and-cycle still commits on
        // release instead of silently disarming after the first release.
        if held {
            triggerModifiersHeldSinceShow = true
            return false
        }
        if triggerModifiersHeldSinceShow {
            triggerModifiersHeldSinceShow = false
            onModifierRelease?()
            return true
        }
        return false
    }

    private func checkWatchdog() {
        guard triggerModifiersHeldSinceShow else {
            return
        }
        if !Self.modifiersPhysicallyHeld(triggerFlags) {
            triggerModifiersHeldSinceShow = false
            onModifierRelease?()
        }
    }

    private func stopMonitors() {
        watchdog?.invalidate()
        watchdog = nil
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
    }
}
