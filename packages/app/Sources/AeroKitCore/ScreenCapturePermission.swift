import AppKit
import CoreGraphics
import Foundation

public enum ScreenCapturePermission {
    public static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    public static func request() -> Bool {
        if isGranted {
            return true
        }
        // If the app is already listed in System Settings (e.g. from a
        // previous install), CGRequestScreenCaptureAccess() returns false
        // without showing a dialog. Callers should follow up with
        // openSettings() when this returns false. The settings Grant Access
        // button uses CurrentAppScreenCaptureRegistration so a replaced
        // build can reset this app's ScreenCapture TCC entry first.
        return CGRequestScreenCaptureAccess() || isGranted
    }

    public static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            _ = NSWorkspace.shared.open(url)
        }
    }
}
