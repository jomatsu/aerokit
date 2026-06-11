/// Keyboard quick-select for overview tiles: digits 1–9 address the first
/// nine, letters A–Z the tiles after that.
enum QuickSelect {
    static let digitCount = 9
    private static let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    /// Keycap label shown on the tile; nil past the addressable range.
    static func label(forIndex index: Int) -> String? {
        guard index >= 0 else {
            return nil
        }
        if index < digitCount {
            return String(index + 1)
        }
        let letterIndex = index - digitCount
        guard letters.indices.contains(letterIndex) else {
            return nil
        }
        return String(letters[letterIndex])
    }

    /// Tile index for a typed character; letters match case-insensitively.
    static func index(for character: Character) -> Int? {
        if let digit = character.wholeNumberValue, (1 ... digitCount).contains(digit) {
            return digit - 1
        }
        let uppercased = String(character).uppercased()
        guard uppercased.count == 1, let letter = uppercased.first,
              let position = letters.firstIndex(of: letter)
        else {
            return nil
        }
        return digitCount + position
    }
}
