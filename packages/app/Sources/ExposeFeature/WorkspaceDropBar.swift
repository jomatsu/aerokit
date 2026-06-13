import AeroKitCore
import AppKit
import SwiftUI

/// A workspace a dragged window can be dropped on, in AeroSpace's order.
public struct WorkspaceTarget: Equatable, Identifiable, Sendable {
    public var name: String
    public var isFocused: Bool

    public var id: String {
        name
    }

    public init(name: String, isFocused: Bool) {
        self.name = name
        self.isFocused = isFocused
    }
}

/// Card frames in the overlay's coordinate space, keyed by workspace name;
/// the drag's hover highlight and drop test scan this dictionary.
struct ChipFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Mission-Control-style spaces strip shown while a tile drag is in
/// flight: one snapshot card per workspace, and dropping the window on a
/// card moves it there. Visual language follows the swipe HUD — same card
/// metrics, same glass panel — so the two workspace strips read as one
/// family.
struct WorkspaceDropBar: View {
    /// Card metrics the ghost also fits itself to, so the dragged window
    /// visibly becomes "one of these cards" while it travels.
    static let thumbSize = WorkspaceCardMetrics.thumbSize
    private static let cardCornerRadius = WorkspaceCardMetrics.cardCornerRadius

    let targets: [WorkspaceTarget]
    /// Snapshot previews keyed by workspace name; missing ones render as
    /// placeholders.
    let previews: [String: NSImage]
    /// The dragged window's own workspace — present but inert.
    let disabledName: String?
    /// The card under the dragged tile right now.
    let highlightedName: String?
    /// Name of the overlay's coordinate space the cards report frames in.
    let coordinateSpace: String

    var body: some View {
        HStack(spacing: WorkspaceCardMetrics.cellSpacing) {
            ForEach(targets) { target in
                card(target)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, WorkspaceCardMetrics.panelPadding)
        .workspaceStripPanel()
    }

    private func card(_ target: WorkspaceTarget) -> some View {
        let disabled = target.name == disabledName
        let highlighted = target.name == highlightedName
        return VStack(spacing: WorkspaceCardMetrics.captionSpacing) {
            thumbnail(for: target.name, disabled: disabled, highlighted: highlighted)
            Text(target.name)
                // The focused workspace's caption sits a touch heavier,
                // matching the swipe HUD's emphasis language.
                .font(.system(size: 11.5, weight: target.isFocused ? .semibold : .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(disabled ? 0.35 : highlighted ? 1 : 0.6))
                .lineLimit(1)
                .frame(width: Self.thumbSize.width, height: WorkspaceCardMetrics.captionHeight)
        }
        // The whole card — caption included — is the drop target.
        .background(GeometryReader { proxy in
            Color.clear.preference(
                key: ChipFramesKey.self,
                value: disabled ? [:] : [target.name: proxy.frame(in: .named(coordinateSpace))]
            )
        })
        .scaleEffect(highlighted ? 1.06 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 1), value: highlighted)
    }

    private func thumbnail(for name: String, disabled: Bool, highlighted: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
        return WorkspaceCardThumbnail(image: previews[name])
            // Brightness carries the hierarchy: the hovered card lights up,
            // the source workspace stays veiled.
            .overlay {
                shape.fill(.black.opacity(disabled ? 0.55 : highlighted ? 0 : 0.32))
            }
            .overlay {
                shape.strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .overlay {
                shape.strokeBorder(
                    Color(nsColor: .controlAccentColor).opacity(highlighted ? 1 : 0),
                    lineWidth: 2
                )
            }
            .shadow(color: .black.opacity(highlighted ? 0.35 : 0), radius: 10, y: 4)
    }
}
