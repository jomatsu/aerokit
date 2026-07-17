import Foundation

private let log = AppLog(category: "core")

/// Reads and writes the macOS "Mission Control" and "App Exposé" trackpad
/// gesture checkboxes (System Settings → Trackpad → More Gestures). Both
/// live in the Dock's preference domain, and the Dock only rereads them on
/// launch, so changing them restarts the Dock.
public enum SystemSwipeGestures {
    private static let domain = "com.apple.dock"
    private static let keys = [
        "showMissionControlGestureEnabled",
        "showAppExposeGestureEnabled"
    ]

    /// True while either system gesture is still on; an absent key means
    /// the gesture was never turned off.
    public static var isEnabled: Bool {
        keys.contains { key in
            CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Bool ?? true
        }
    }

    /// The system's own three-finger horizontal swipe ("Swipe between
    /// full-screen applications", System Settings → Trackpad → More
    /// Gestures). It is recognized from the same raw touches AeroKit
    /// observes and cannot be consumed, so while it is set to three
    /// fingers every workspace swipe also slides the whole screen to a
    /// neighbouring macOS Space — the workspace switch lands correctly
    /// and a different Space then covers it. 2 is the three-finger
    /// setting; off (0) or four fingers leaves three-finger swipes to
    /// AeroKit. An absent key means the macOS default, which is on.
    public static var horizontalThreeFingerSpaceSwipeEnabled: Bool {
        let domains = [
            "com.apple.AppleMultitouchTrackpad",
            "com.apple.driver.AppleBluetoothMultitouch.trackpad"
        ]
        return domains.contains { domain in
            let value = CFPreferencesCopyAppValue(
                "TrackpadThreeFingerHorizSwipeGesture" as CFString,
                domain as CFString
            ) as? Int
            return (value ?? 2) == 2
        }
    }

    /// Flips both checkboxes and restarts the Dock so the change applies
    /// immediately. Blocks on the Dock kill — call off the main thread.
    public static func setEnabled(_ enabled: Bool) throws {
        for key in keys {
            CFPreferencesSetAppValue(key as CFString, enabled ? kCFBooleanTrue : kCFBooleanFalse, domain as CFString)
        }
        guard CFPreferencesAppSynchronize(domain as CFString) else {
            throw SystemSwipeGesturesError.synchronizeFailed
        }
        // killall failing (e.g. the Dock happens to be mid-respawn) does not
        // undo the preference write — launchd brings the Dock back with the
        // new values anyway, so log instead of reporting a failure.
        do {
            _ = try ProcessRunner().run("/usr/bin/killall", arguments: ["Dock"])
        } catch {
            log.error("restarting the Dock failed: \(error)")
        }
    }
}

public enum SystemSwipeGesturesError: Error, CustomStringConvertible {
    case synchronizeFailed

    public var description: String {
        "Writing the Dock gesture preferences failed"
    }
}
