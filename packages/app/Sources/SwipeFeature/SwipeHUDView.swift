import AeroKitCore
import AppKit
import SwiftUI

/// The workspace strip on a tight dark glass panel, Raycast-style: every
/// thumbnail is the same size in a fixed row that never reflows, and the
/// selection is a soft highlight pill that glides under the fingers'
/// progress, with a white ring and caption brightness following it. App
/// icons live on a dark gradient scrim along the snapshot's bottom edge —
/// streaming-app card style — so they sit inside the picture without
/// fighting it; the workspace name stays below as the cell's label.
struct SwipeHUDView: View {
    @ObservedObject var model: SwipeHUDModel

    // Card and panel chrome shared with the exposé drop bar.
    private static let thumbSize = WorkspaceCardMetrics.thumbSize
    private static let cellSpacing = WorkspaceCardMetrics.cellSpacing
    private static let captionSpacing = WorkspaceCardMetrics.captionSpacing
    private static let captionHeight = WorkspaceCardMetrics.captionHeight
    private static let cardCornerRadius = WorkspaceCardMetrics.cardCornerRadius
    private static let panelPadding = WorkspaceCardMetrics.panelPadding
    private static var cellHeight: CGFloat {
        WorkspaceCardMetrics.cellHeight
    }

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
    /// Room below the panel for its drop shadow.
    static let bottomPadding: CGFloat = 20
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
        .workspaceStripPanel()
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
        return WorkspaceCardThumbnail(image: model.previews[name])
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
                                    .init(color: .clear, location: Self.scrimHeight / Self.thumbSize.height)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                }
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: Self.scrimIconSpacing) {
                    ForEach(0 ..< min(icons.count, Self.maxScrimIcons), id: \.self) { index in
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
