import CoreGraphics
import Foundation

enum ScreenCapturePermission {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
