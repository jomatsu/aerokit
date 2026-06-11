import CoreGraphics
import Foundation

public enum ScreenCapturePermission {
    public static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    public static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
