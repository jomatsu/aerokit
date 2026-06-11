import SwiftUI

/// Layout selector in the style of Raycast's window-mode picker: each option
/// is a miniature of the switcher grid so the result is visible at a glance.
struct GridLayoutPicker: View {
    @Binding var selection: Int
    let range: ClosedRange<Int>

    /// Mirrors the typical workspace count so the miniatures match reality.
    private let tileCount = 8

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(range), id: \.self) { columns in
                option(columns: columns)
            }
        }
    }

    private func option(columns: Int) -> some View {
        let isSelected = columns == selection
        return Button {
            selection = columns
        } label: {
            VStack(spacing: 5) {
                GridMiniature(columns: columns, tiles: tileCount, isSelected: isSelected)
                    .frame(width: 60, height: 42)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    }

                Text("\(columns)")
                    .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(columns) columns")
        .animation(.easeOut(duration: 0.12), value: selection)
    }
}

private struct GridMiniature: View {
    let columns: Int
    let tiles: Int
    let isSelected: Bool

    var body: some View {
        let rows = Int(ceil(Double(tiles) / Double(columns)))
        VStack(spacing: 2.5) {
            ForEach(0 ..< rows, id: \.self) { row in
                HStack(spacing: 2.5) {
                    ForEach(0 ..< columns, id: \.self) { column in
                        if row * columns + column < tiles {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(tileColor)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(6)
    }

    private var tileColor: Color {
        isSelected ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.45)
    }
}
