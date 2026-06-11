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

    /// One app's contiguous run of tiles while the overview is grouped.
    public struct Section: Identifiable {
        public let appName: String
        public let icon: NSImage?
        public let tileRange: Range<Int>

        public var id: Int {
            tileRange.lowerBound
        }
    }

    public private(set) var tiles: [Tile]
    public private(set) var selectedIndex: Int
    public private(set) var grid: GridDimensions
    /// Non-nil while the tiles are grouped by app; sections cover `tiles`
    /// in order.
    public private(set) var sections: [Section]?
    /// Section indexes per shelf row while grouped; small apps share a row.
    public private(set) var sectionRows: [[Int]]?

    private let containerAspect: CGFloat
    /// Window order as first presented (spatial); grouping is undone by
    /// restoring this order.
    private let defaultOrder: [CGWindowID]

    public init(
        windows: [ExposeWindow],
        containerAspect: CGFloat,
        bounds: [CGWindowID: CGRect] = [:],
        focusedWindowID: CGWindowID? = nil,
        icons: [CGWindowID: NSImage] = [:],
        groupByApp: Bool = false
    ) {
        tiles = windows.map { Tile(window: $0, pointSize: bounds[$0.id]?.size, icon: icons[$0.id], image: nil) }
        self.containerAspect = containerAspect
        defaultOrder = windows.map(\.id)
        grid = GridDimensions.bestFit(count: windows.count, containerAspect: containerAspect)
        selectedIndex = windows.firstIndex { $0.id == focusedWindowID } ?? 0
        if groupByApp {
            setGroupedByApp(true)
        }
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
            moveVertically(by: -1)
        case .down:
            moveVertically(by: 1)
        }
    }

    /// Rows are ragged (a short last row, and every section break while
    /// grouped), so vertical moves keep the column but clamp to the target
    /// row's width.
    private func moveVertically(by delta: Int) {
        let rows = visualRows
        guard let rowIndex = rows.firstIndex(where: { $0.contains(selectedIndex) }) else {
            return
        }
        let targetRow = rowIndex + delta
        guard rows.indices.contains(targetRow), let first = rows[rowIndex].first else {
            return
        }
        let column = selectedIndex - first
        selectedIndex = rows[targetRow][min(column, rows[targetRow].count - 1)]
    }

    /// Row chunks of `range` at the grid's column count; the overlay view
    /// lays tiles out with the same chunks the keyboard moves over.
    func rowRanges(in range: Range<Int>) -> [Range<Int>] {
        stride(from: range.lowerBound, to: range.upperBound, by: grid.columns).map {
            $0 ..< min($0 + grid.columns, range.upperBound)
        }
    }

    /// Tile indices per visual row. While grouped, a shelf row's groups form
    /// one row; a group wider than the grid wraps into several.
    private var visualRows: [[Int]] {
        let blocks: [Range<Int>] = if let sections, let sectionRows {
            // A shelf row's sections are adjacent, so it spans one range.
            sectionRows.compactMap { row in
                guard let first = row.first, let last = row.last else {
                    return nil
                }
                return sections[first].tileRange.lowerBound ..< sections[last].tileRange.upperBound
            }
        } else {
            [0 ..< tiles.count]
        }
        return blocks.flatMap { block in
            rowRanges(in: block).map(Array.init)
        }
    }

    // MARK: - Grouping

    public var isGroupedByApp: Bool {
        sections != nil
    }

    public func toggleGrouping() {
        setGroupedByApp(!isGroupedByApp)
    }

    /// Reorders the tiles in place — previews already captured move with
    /// their tile — and keeps the same window selected across the switch.
    public func setGroupedByApp(_ grouped: Bool) {
        guard grouped != isGroupedByApp else {
            return
        }
        let selectedID = tiles.indices.contains(selectedIndex) ? tiles[selectedIndex].id : nil

        if grouped {
            let groups = groupedTiles()
            tiles = groups.flatMap(\.tiles)
            sections = Self.sections(for: groups)
            let layout = GridDimensions.bestGroupedFit(
                groupCounts: groups.map(\.tiles.count),
                containerAspect: containerAspect
            )
            grid = layout.grid
            sectionRows = layout.rows
        } else {
            let position = Dictionary(
                uniqueKeysWithValues: defaultOrder.enumerated().map { ($0.element, $0.offset) }
            )
            tiles.sort { position[$0.id, default: .max] < position[$1.id, default: .max] }
            sections = nil
            sectionRows = nil
            grid = GridDimensions.bestFit(count: tiles.count, containerAspect: containerAspect)
        }

        if let selectedID, let index = tiles.firstIndex(where: { $0.id == selectedID }) {
            selectedIndex = index
        }
    }

    /// Apps in order of first appearance; each app's windows keep their
    /// current (spatial) order.
    private func groupedTiles() -> [(key: String, tiles: [Tile])] {
        var order: [String] = []
        var byKey: [String: [Tile]] = [:]
        for tile in tiles {
            let key = tile.window.bundleIdentifier.isEmpty
                ? tile.window.appName
                : tile.window.bundleIdentifier
            if byKey[key] == nil {
                order.append(key)
            }
            byKey[key, default: []].append(tile)
        }
        return order.map { (key: $0, tiles: byKey[$0] ?? []) }
    }

    private static func sections(for groups: [(key: String, tiles: [Tile])]) -> [Section] {
        var sections: [Section] = []
        var start = 0
        for group in groups {
            let range = start ..< start + group.tiles.count
            sections.append(Section(
                appName: group.tiles.first?.window.appName ?? group.key,
                icon: group.tiles.first?.icon,
                tileRange: range
            ))
            start = range.upperBound
        }
        return sections
    }
}
