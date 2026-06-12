import AppKit
import Combine
import SwiftUI

/// Floating capsule shown after every swipe: the monitor's workspaces as a
/// pill strip with the focused one highlighted. Consecutive swipes reuse the
/// panel so the highlight glides between pills instead of re-appearing.
@MainActor
final class SwipeHUD {
    /// How long the strip stays up after the last swipe.
    private static let displayDuration: Duration = .milliseconds(1000)
    /// Distance from the bottom edge of the screen's visible frame.
    private static let bottomOffset: CGFloat = 96
    private static let stripHeight: CGFloat = 80

    private let model = SwipeHUDModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(workspaces: [String], current: String) {
        let panel = ensurePanel()
        position(panel)

        // Skip the slide animation when the strip starts hidden — the
        // highlight would visibly travel during the fade-in otherwise. The
        // panel's visibility, not the model's, is the cue: mid fade-out the
        // strip is still on screen and the highlight should keep gliding.
        model.update(workspaces: workspaces, current: current, animated: panel.isVisible)
        panel.orderFrontRegardless()
        model.isVisible = true

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

    /// Immediate dismissal (the feature or the HUD was turned off); also
    /// releases the panel and its hosting view until the next swipe.
    func hide() {
        hideTask?.cancel()
        hideTask = nil
        model.isVisible = false
        panel?.orderOut(nil)
        panel = nil
    }

    /// The panel is a full-width transparent strip with the capsule centered
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
        // AeroSpace just switched workspaces.
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
    @Published var isVisible = false

    func update(workspaces: [String], current: String, animated: Bool) {
        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                self.workspaces = workspaces
                self.current = current
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.workspaces = workspaces
                self.current = current
            }
        }
    }
}

// MARK: - View

struct SwipeHUDView: View {
    @ObservedObject var model: SwipeHUDModel
    @Namespace private var highlight

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            strip
                .opacity(model.isVisible ? 1 : 0)
                .scaleEffect(model.isVisible ? 1 : 0.96)
                .animation(
                    model.isVisible
                        ? .spring(response: 0.28, dampingFraction: 0.85)
                        : .easeOut(duration: 0.25),
                    value: model.isVisible
                )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var strip: some View {
        HStack(spacing: 4) {
            ForEach(model.workspaces, id: \.self) { name in
                pill(for: name)
            }
        }
        .padding(5)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        }
    }

    private func pill(for name: String) -> some View {
        let isCurrent = name == model.current
        return Text(name)
            .font(.system(size: 13, weight: isCurrent ? .semibold : .medium, design: .rounded))
            .foregroundStyle(isCurrent ? AnyShapeStyle(.black.opacity(0.85)) : AnyShapeStyle(.white.opacity(0.55)))
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(minWidth: 30, minHeight: 26)
            .background {
                if isCurrent {
                    Capsule(style: .continuous)
                        .fill(.white)
                        .matchedGeometryEffect(id: "selection", in: highlight)
                }
            }
    }
}
