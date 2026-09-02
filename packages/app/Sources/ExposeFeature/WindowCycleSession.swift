import AeroKitCore
import AppKit
import Observation

/// One cycling presentation: the focused workspace's windows in recency
/// order, the selection, and preview images as they stream in. ⌘Tab
/// semantics: index 0 is the current window and index 1 arrives
/// preselected, so a plain tap commits the previous window; a lone window
/// stays selected and committing is a no-op.
@MainActor
@Observable
public final class WindowCycleSession {
    public struct Entry: Identifiable {
        public let window: ExposeWindow
        public let icon: NSImage?
        public var image: NSImage?

        public var id: CGWindowID {
            window.id
        }
    }

    public private(set) var entries: [Entry]
    public private(set) var selectedIndex: Int

    public init(windows: [ExposeWindow], icons: [CGWindowID: NSImage]) {
        let built = windows.map { Entry(window: $0, icon: icons[$0.id], image: nil) }
        entries = built
        // Index 0 is the focused window; the controller applies the opening
        // move on top of it, so a forward tap lands on the previous window.
        selectedIndex = 0
    }

    public var selectedEntry: Entry? {
        entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil
    }

    /// Next/previous wrap around; the strip is one row, so up/down are
    /// accepted aliases for the horizontal moves.
    public func move(_ move: SelectionMove) {
        let count = entries.count
        guard count > 1 else {
            return
        }
        switch move {
        case .next, .right, .down:
            selectedIndex = (selectedIndex + 1) % count
        case .previous, .left, .up:
            selectedIndex = (selectedIndex + count - 1) % count
        }
    }

    public func setImage(_ image: NSImage, forWindow id: CGWindowID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }
        entries[index].image = image
    }
}
