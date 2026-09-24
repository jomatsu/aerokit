/// Keyboard quick-select for overview tiles: digits 1–9 address the first
/// nine, letters A–Z the tiles after that. The grouping-toggle key is carved
/// out of the sequence, so whatever key the user picks can never collide
/// with a tile shortcut.
enum QuickSelect {
    private static let allKeys = Array("123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    /// Number-row positions for ⇧1–9 workspace moves; shifted characters
    /// such as "!" cannot identify the destination workspace.
    static func numberRowDigit(for keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: 1
        case 19: 2
        case 20: 3
        case 21: 4
        case 23: 5
        case 22: 6
        case 26: 7
        case 28: 8
        case 25: 9
        default: nil
        }
    }

    /// Keycap label shown on the tile; nil past the addressable range.
    static func label(forIndex index: Int, excluding excluded: Character? = nil) -> String? {
        var position = index
        if let excludedPosition = excludedPosition(excluded), position >= excludedPosition {
            position += 1
        }
        guard allKeys.indices.contains(position) else {
            return nil
        }
        return String(allKeys[position])
    }

    /// Tile index for a typed character; letters match case-insensitively.
    static func index(for character: Character, excluding excluded: Character? = nil) -> Int? {
        guard let key = normalized(character), let position = allKeys.firstIndex(of: key) else {
            return nil
        }
        guard let excludedPosition = excludedPosition(excluded) else {
            return position
        }
        if position == excludedPosition {
            return nil
        }
        return position > excludedPosition ? position - 1 : position
    }

    private static func excludedPosition(_ excluded: Character?) -> Int? {
        guard let excluded = excluded.flatMap(normalized) else {
            return nil
        }
        return allKeys.firstIndex(of: excluded)
    }

    private static func normalized(_ character: Character) -> Character? {
        String(character).uppercased().first
    }
}
