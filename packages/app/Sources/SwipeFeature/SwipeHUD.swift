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
    private static let bottomOffset: CGFloat = 80
    /// Derived from the view's own metrics — panel, shadow room below,
    /// a little headroom above — so window and layout can't drift apart.
    private static let stripHeight: CGFloat =
        SwipeHUDView.panelHeight + SwipeHUDView.bottomPadding + 8

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

    /// Icons arrive from their own load, possibly after the strip is
    /// already up (or even settling) — the cards fill in as they land.
    func updateIcons(_ icons: [String: [NSImage]]) {
        model.icons = icons
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

// MARK: - View

/// The workspace strip on a tight dark glass panel, Raycast-style: every
/// thumbnail is the same size in a fixed row that never reflows, and the
/// selection is a soft highlight pill that glides under the fingers'
/// progress, with a white ring and caption brightness following it. App
/// icons live on a dark gradient scrim along the snapshot's bottom edge —
/// streaming-app card style — so they sit inside the picture without
/// fighting it; the workspace name stays below as the cell's label.
struct SwipeHUDView: View {
    @ObservedObject var model: SwipeHUDModel

    private static let thumbSize = CGSize(width: 140, height: 87.5)
    private static let cellSpacing: CGFloat = 12
    private static let captionSpacing: CGFloat = 6
    private static let captionHeight: CGFloat = 14
    private static let cardCornerRadius: CGFloat = 8
    private static let panelCornerRadius: CGFloat = 18
    /// The scrim band along the thumbnail's bottom edge and the app icons
    /// riding on it.
    private static let scrimHeight: CGFloat = 34
    private static let scrimIconSize: CGFloat = 18
    private static let scrimIconSpacing: CGFloat = 4
    private static let maxScrimIcons = 4
    /// How far the highlight pill extends past the cell on every side.
    private static let highlightInset: CGFloat = 6
    /// How far past the row's ends the pill follows a rubber-banded
    /// overshoot before it stops (the cards' emphasis keeps moving).
    private static let highlightOverhang: CGFloat = 0.2
    private static let panelPadding: CGFloat = 12
    /// Room below the panel for its drop shadow.
    static let bottomPadding: CGFloat = 20
    private static var cellHeight: CGFloat {
        thumbSize.height + captionSpacing + captionHeight
    }
    /// The glass panel's full height; the HUD window derives its frame
    /// from this so the two can't drift apart.
    static var panelHeight: CGFloat {
        cellHeight + panelPadding * 2
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            // A gentle grow-in with a critically damped curve: enough life
            // to feel responsive, but no overshoot — a springing scale
            // makes the whole panel bob vertically on every appearance.
            strip
                .opacity(model.isVisible ? 1 : 0)
                .scaleEffect(model.isVisible ? 1 : 0.98)
                .animation(
                    model.isVisible
                        ? .spring(response: 0.25, dampingFraction: 1)
                        : .easeOut(duration: 0.25),
                    value: model.isVisible
                )
        }
        .padding(.bottom, Self.bottomPadding)
        .frame(maxWidth: .infinity)
    }

    /// The selection's strip position: wrap-aware, rubber-banded at the
    /// ends otherwise (see SwipeHUDModel.position(forOffset:)).
    private var selectionPosition: CGFloat {
        model.selectionPosition
    }

    /// 1 when the selection sits on this card, fading to 0 one card away;
    /// drives the ring, veil, and caption interpolation.
    private func emphasis(at index: Int) -> CGFloat {
        max(0, 1 - abs(selectionPosition - CGFloat(index)))
    }

    private var strip: some View {
        // The pill is a background, not a sibling: it must never take part
        // in layout — taller than the row, it would pad the strip's bottom
        // with dead space.
        HStack(spacing: Self.cellSpacing) {
            ForEach(Array(model.workspaces.enumerated()), id: \.element) { index, name in
                card(for: name, at: index)
            }
        }
        .background(alignment: .topLeading) {
            selectionHighlight
        }
        .padding(.horizontal, 16)
        .padding(.vertical, Self.panelPadding)
        .background {
            RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                .fill(.black.opacity(0.5))
                .background {
                    RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    // Raycast-style edge: bright at the top where the light
                    // hits, falling off toward the bottom.
                    RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.22), .white.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
                // Soft and close — a heavy halo reads as smudges sticking
                // out past the panel's sides.
                .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
        }
    }

    /// The gliding selection: a soft pill that tracks the fingers'
    /// position continuously, clamped near the row so a rubber-banded
    /// overshoot can't drag it out of the panel.
    private var selectionHighlight: some View {
        let upperBound = CGFloat(max(model.workspaces.count - 1, 0))
        let position = min(
            max(selectionPosition, -Self.highlightOverhang),
            upperBound + Self.highlightOverhang
        )
        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(0.12))
            .frame(
                width: Self.thumbSize.width + Self.highlightInset * 2,
                height: Self.cellHeight + Self.highlightInset * 2
            )
            .offset(
                x: (Self.thumbSize.width + Self.cellSpacing) * position - Self.highlightInset,
                y: -Self.highlightInset
            )
    }

    private func card(for name: String, at index: Int) -> some View {
        let emphasis = emphasis(at: index)
        // Constant fonts and frames: only colors animate, so the captions
        // never shift or wobble.
        return VStack(spacing: Self.captionSpacing) {
            thumbnail(for: name, emphasis: emphasis)
            Text(name)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.5 + 0.5 * emphasis))
                .lineLimit(1)
                .frame(width: Self.thumbSize.width, height: Self.captionHeight)
        }
    }

    /// The full snapshot card: picture, icon scrim, dimming veil,
    /// hairline, and selection ring.
    private func thumbnail(for name: String, emphasis: CGFloat) -> some View {
        let icons = model.icons[name] ?? []
        return ZStack {
            if let image = model.previews[name] {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.white.opacity(0.07))
                Image(systemName: "macwindow")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous))
        // Streaming-card scrim: a dark gradient band along the bottom edge
        // that carries the app icons, so they read against any snapshot
        // without floating loose on it. Filled into the card's shape so the
        // rounded corners stay clean.
        .overlay {
            if !icons.isEmpty {
                RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.65), location: 0),
                                .init(color: .clear, location: Self.scrimHeight / Self.thumbSize.height),
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
            }
        }
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: Self.scrimIconSpacing) {
                ForEach(0..<min(icons.count, Self.maxScrimIcons), id: \.self) { index in
                    Image(nsImage: icons[index])
                        .resizable()
                        .frame(width: Self.scrimIconSize, height: Self.scrimIconSize)
                }
            }
            .padding(6)
            .opacity(0.8 + 0.2 * emphasis)
            .saturation(0.8 + 0.2 * emphasis)
        }
        // The dark veil lifts as the selection arrives, so the hierarchy
        // comes from brightness instead of size.
        .overlay {
            RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                .fill(.black.opacity(0.32 * (1 - emphasis)))
        }
        .overlay {
            // Hairline edge every card has, so thumbnails never bleed into
            // the panel…
            RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .overlay {
            // …and the selection ring that fades in over it.
            RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.9 * emphasis), lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(0.35 * emphasis), radius: 10, y: 4)
    }
}
