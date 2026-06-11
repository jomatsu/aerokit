import AeroKitCore
import AppKit
import CoreGraphics
import Observation

/// One overlay presentation: the windows being shown, their preview images
/// as they stream in, and the keyboard selection.
@MainActor
@Observable
public final class ExposeSession {
    public struct Tile: Identifiable {
        public let window: ExposeWindow
        /// Native size in points; sizes the tile before its capture arrives
        /// and caps the preview so windows are never shown larger than life.
        public let pointSize: CGSize?
        public let icon: NSImage?
        public var image: CGImage?

        public var id: CGWindowID {
            window.id
        }
    }

    public private(set) var tiles: [Tile]
    public private(set) var selectedIndex: Int
    public let grid: GridDimensions

    public init(
        windows: [ExposeWindow],
        containerAspect: CGFloat,
        bounds: [CGWindowID: CGRect] = [:],
        focusedWindowID: CGWindowID? = nil,
        icons: [CGWindowID: NSImage] = [:]
    ) {
        tiles = windows.map { Tile(window: $0, pointSize: bounds[$0.id]?.size, icon: icons[$0.id], image: nil) }
        grid = GridDimensions.bestFit(count: windows.count, containerAspect: containerAspect)
        selectedIndex = windows.firstIndex { $0.id == focusedWindowID } ?? 0
    }

    public func setImage(_ image: CGImage, forWindow id: CGWindowID) {
        guard let index = tiles.firstIndex(where: { $0.window.id == id }) else {
            return
        }
        tiles[index].image = image
    }

    public func select(_ index: Int) {
        guard tiles.indices.contains(index) else {
            return
        }
        selectedIndex = index
    }

    /// Next/previous wrap around in reading order (so left/right arrows flow
    /// across row boundaries); up/down stop at the grid's edge.
    public func move(_ move: SelectionMove) {
        let count = tiles.count
        guard count > 0 else {
            return
        }

        switch move {
        case .next, .right:
            selectedIndex = (selectedIndex + 1) % count
        case .previous, .left:
            selectedIndex = (selectedIndex + count - 1) % count
        case .up:
            let target = selectedIndex - grid.columns
            if target >= 0 {
                selectedIndex = target
            }
        case .down:
            let target = selectedIndex + grid.columns
            if target < count {
                selectedIndex = target
            }
        }
    }
}
