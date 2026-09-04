import AppKit
import Combine
import SwiftUI

@MainActor
final class SwipeHUDModel: ObservableObject {
    @Published var workspaces: [String] = []
    @Published var current = ""
    @Published var previews: [String: NSImage] = [:]
    /// Icons of the apps with windows on each workspace, in window order.
    /// Updated independently of the rest: they stream in from their own
    /// load (see SwipeHUD.updateIcons) and survive across updates.
    @Published var icons: [String: [NSImage]] = [:]
    /// Selection displacement from `current`, in cards; follows the fingers
    /// during a gesture and springs back to 0 when it settles.
    @Published var offset: CGFloat = 0
    @Published var isVisible = false
    /// Mirrors the wrap-around preference so the selection can pass through
    /// the strip's ends the same way the commit does.
    @Published var wrapsAround = false
    /// Index of `current` in `workspaces`, cached because the position is
    /// recomputed for every card on every gesture frame.
    private var currentIndex = 0

    /// The selection's strip position for a given offset. With wrap-around
    /// the position passes through the ends — half a card past the last
    /// re-enters before the first — matching where a wrapped commit lands.
    /// Without it the ends rubber-band like a native page swipe.
    func position(forOffset offset: CGFloat) -> CGFloat {
        let count = workspaces.count
        guard count > 1 else {
            return 0
        }
        let raw = CGFloat(currentIndex) + offset
        let maxIndex = CGFloat(count - 1)
        if wrapsAround {
            var position = raw.truncatingRemainder(dividingBy: CGFloat(count))
            if position < -0.5 {
                position += CGFloat(count)
            }
            if position >= CGFloat(count) - 0.5 {
                position -= CGFloat(count)
            }
            return position
        }
        if raw < 0 {
            return raw * 0.25
        }
        if raw > maxIndex {
            return maxIndex + (raw - maxIndex) * 0.25
        }
        return raw
    }

    var selectionPosition: CGFloat {
        position(forOffset: offset)
    }

    func update(
        workspaces: [String],
        current: String,
        previews: [String: NSImage],
        wrapsAround: Bool,
        animated: Bool
    ) {
        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                apply(workspaces: workspaces, current: current, previews: previews, wrapsAround: wrapsAround)
            }
        } else {
            withoutAnimation {
                apply(workspaces: workspaces, current: current, previews: previews, wrapsAround: wrapsAround)
            }
        }
    }

    private func apply(
        workspaces: [String],
        current: String,
        previews: [String: NSImage],
        wrapsAround: Bool
    ) {
        self.workspaces = workspaces
        self.current = current
        self.previews = previews
        self.wrapsAround = wrapsAround
        currentIndex = workspaces.firstIndex(of: current) ?? 0
        offset = 0
    }
}
