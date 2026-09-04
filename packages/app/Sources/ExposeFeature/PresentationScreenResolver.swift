import AppKit

/// Shared screen pick for exposé and the window switcher: AeroSpace's
/// 1-based `screenNumber` when it names a real screen, then the screen
/// under the cursor, then main, then the first screen.
enum PresentationScreenResolver {
    static func screen(
        for screenNumber: Int?,
        screens: [NSScreen] = NSScreen.screens,
        mouseLocation: NSPoint = NSEvent.mouseLocation,
        main: NSScreen? = NSScreen.main
    ) -> NSScreen? {
        if let screenNumber, screens.indices.contains(screenNumber - 1) {
            return screens[screenNumber - 1]
        }
        return screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? main ?? screens.first
    }
}
