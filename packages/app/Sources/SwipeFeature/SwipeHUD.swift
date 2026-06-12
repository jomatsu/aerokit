import AppKit
import Combine
import SwiftUI

/// SwiftUI's verbose disable-animations transaction dance, named.
@MainActor
private func withoutAnimation(_ body: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, body)
}

/// Floating workspace strip that tracks the swipe gesture: every workspace
/// shows as a small snapshot card and a single selection block glides under
/// the fingers' progress, springing onto the landing workspace at release.
/// Consecutive swipes reuse the panel so the selection keeps gliding
/// instead of re-appearing.
@MainActor
final class SwipeHUD {
    /// How long the strip stays up after a gesture settles.
    private static let displayDuration: Duration = .milliseconds(1000)
    /// Distance from the bottom edge of the screen's visible frame.
    private static let bottomOffset: CGFloat = 96
    /// Tall enough for a card grown to full emphasis plus its caption.
    private static let stripHeight: CGFloat = 140

    private let model = SwipeHUDModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    /// A gesture is in flight: show the strip and keep it up — no hide
    /// timer runs until the gesture settles.
    func beginInteractive(
        workspaces: [String],
        current: String,
        previews: [String: NSImage],
        wrapsAround: Bool
    ) {
        hideTask?.cancel()
        hideTask = nil
        present(workspaces: workspaces, current: current, previews: previews, wrapsAround: wrapsAround)
    }

    /// Finger-attached selection position, in cards from the current one.
    func setOffset(_ offset: CGFloat) {
        guard panel?.isVisible == true else {
            return
        }
        // A wrap-around pass through the strip's end teleports the selection
        // to the other side; animating that change would fly it across every
        // card in between instead.
        let travel = abs(model.position(forOffset: offset) - model.selectionPosition)
        if travel > CGFloat(max(model.workspaces.count, 1)) / 2 {
            withoutAnimation {
                model.offset = offset
            }
        } else {
            withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.9)) {
                model.offset = offset
            }
        }
    }

    /// The gesture released: spring the selection onto the outcome — the
    /// new workspace, or back where it started on a cancel — then schedule
    /// the fade-out. Also shows the strip when a flick ended before the
    /// workspace ring had arrived to open it.
    func settle(
        workspaces: [String],
        current: String,
        previews: [String: NSImage],
        wrapsAround: Bool
    ) {
        present(workspaces: workspaces, current: current, previews: previews, wrapsAround: wrapsAround)
        scheduleHide()
    }

    /// Immediate dismissal (the feature or the HUD was turned off); also
    /// releases the panel and its hosting view until the next swipe.
    func hide() {
        hideTask?.cancel()
        hideTask = nil
        model.isVisible = false
        panel?.orderOut(nil)
        panel = nil
    }

    private func present(
        workspaces: [String],
        current: String,
        previews: [String: NSImage],
        wrapsAround: Bool
    ) {
        let panel = ensurePanel()
        position(panel)

        // Skip the glide animation when the strip starts hidden — the
        // selection would visibly travel during the fade-in otherwise. The
        // panel's visibility, not the model's, is the cue: mid fade-out the
        // strip is still on screen and the selection should keep gliding.
        model.update(
            workspaces: workspaces,
            current: current,
            previews: previews,
            wrapsAround: wrapsAround,
            animated: panel.isVisible
        )
        panel.orderFrontRegardless()
        model.isVisible = true
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.displayDuration)
            guard let self, !Task.isCancelled else { return }
            model.isVisible = false
            // Let the fade-out finish before the panel leaves the screen.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self.panel?.orderOut(nil)
        }
    }

    /// The panel is a full-width transparent strip with the cards centered
    /// inside, so changing workspace sets never needs a fitting-size pass.
    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = NSHostingView(rootView: SwipeHUDView(model: model))
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        // NSScreen.main is the screen with keyboard focus, which is where
        // AeroSpace switches workspaces.
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }
        let visible = screen.visibleFrame
        panel.setFrame(
            NSRect(
                x: visible.minX,
                y: visible.minY + Self.bottomOffset,
                width: visible.width,
                height: Self.stripHeight
            ),
            display: false
        )
    }
}

// MARK: - Model

@MainActor
final class SwipeHUDModel: ObservableObject {
    @Published var workspaces: [String] = []
    @Published var current = ""
    @Published var previews: [String: NSImage] = [:]
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

    private func apply(workspaces: [String], current: String, previews: [String: NSImage], wrapsAround: Bool) {
        self.workspaces = workspaces
        self.current = current
        self.previews = previews
        self.wrapsAround = wrapsAround
        currentIndex = workspaces.firstIndex(of: current) ?? 0
        offset = 0
    }
}

// MARK: - View

/// The workspace strip, styled after Mission Control's Spaces bar: a row of
/// snapshot thumbnails on a dark glass panel. The selected thumbnail is
/// larger — the layout itself makes room, nothing overlaps — and carries a
/// white ring and a bright caption. Size, ring, and caption all interpolate
/// continuously with the fingers' progress, so selection both reads at a
/// glance and feels attached to the gesture.
struct SwipeHUDView: View {
    @ObservedObject var model: SwipeHUDModel

    private static let baseThumbSize = CGSize(width: 88, height: 55)
    private static let selectedThumbSize = CGSize(width: 124, height: 77.5)
    private static let cardSpacing: CGFloat = 14
    private static let captionSpacing: CGFloat = 7
    private static let captionHeight: CGFloat = 14

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            strip
                .opacity(model.isVisible ? 1 : 0)
                .scaleEffect(model.isVisible ? 1 : 0.97)
                .animation(
                    model.isVisible
                        ? .spring(response: 0.28, dampingFraction: 0.85)
                        : .easeOut(duration: 0.25),
                    value: model.isVisible
                )
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }

    /// The selection's strip position: wrap-aware, rubber-banded at the
    /// ends otherwise (see SwipeHUDModel.position(forOffset:)).
    private var selectionPosition: CGFloat {
        model.selectionPosition
    }

    /// The one card currently rendered as selected.
    private var selectedIndex: Int {
        let upperBound = max(model.workspaces.count - 1, 0)
        return min(max(Int(selectionPosition.rounded()), 0), upperBound)
    }

    /// 1 when the selection sits on this card, fading to 0 one card away;
    /// drives the size, ring, and caption interpolation.
    private func emphasis(at index: Int) -> CGFloat {
        max(0, 1 - min(1, abs(selectionPosition - CGFloat(index))))
    }

    private var strip: some View {
        HStack(alignment: .bottom, spacing: Self.cardSpacing) {
            ForEach(Array(model.workspaces.enumerated()), id: \.element) { index, name in
                card(for: name, at: index)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.55))
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.09), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.5), radius: 28, y: 12)
        }
    }

    private func card(for name: String, at index: Int) -> some View {
        let emphasis = emphasis(at: index)
        let isSelected = index == selectedIndex
        let size = CGSize(
            width: Self.baseThumbSize.width
                + (Self.selectedThumbSize.width - Self.baseThumbSize.width) * emphasis,
            height: Self.baseThumbSize.height
                + (Self.selectedThumbSize.height - Self.baseThumbSize.height) * emphasis
        )
        return VStack(spacing: Self.captionSpacing) {
            preview(for: name, size: size, emphasis: emphasis)
            Text(name)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(.white.opacity(0.4 + 0.55 * emphasis))
                .lineLimit(1)
                .frame(height: Self.captionHeight)
        }
    }

    private func preview(for name: String, size: CGSize, emphasis: CGFloat) -> some View {
        ZStack {
            if let image = model.previews[name] {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.white.opacity(0.06))
                Image(systemName: "macwindow")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.white.opacity(0.22))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        // The dark veil lifts as the card grows, instead of a flat dimming.
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.black.opacity(0.3 * (1 - emphasis)))
        }
        .overlay {
            // Hairline edge every card has, so thumbnails never bleed into
            // the panel…
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .overlay {
            // …and the selection ring that fades in over it.
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(.white.opacity(0.9 * emphasis), lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.35 * emphasis), radius: 10, y: 4)
    }
}
