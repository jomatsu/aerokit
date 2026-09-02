import AeroKitCore
import AppKit
import SwiftUI

/// The ⌥Tab strip: one card per window — snapshot, icon, title — with a
/// selection ring on the cycling position, on the shared workspace-strip
/// panel chrome.
struct WindowSwitcherStripView: View {
    let session: WindowCycleSession
    let cardSize: CGSize

    var body: some View {
        HStack(spacing: WorkspaceCardMetrics.cellSpacing) {
            ForEach(session.entries) { entry in
                card(for: entry)
            }
        }
        .padding(WorkspaceCardMetrics.panelPadding)
        .workspaceStripPanel()
    }

    private func card(for entry: WindowCycleSession.Entry) -> some View {
        let selected = entry.id == session.selectedEntry?.id
        return VStack(spacing: WorkspaceCardMetrics.captionSpacing) {
            thumbnail(for: entry, selected: selected)
            Text(entry.window.displayTitle)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(.white.opacity(selected ? 1 : 0.55))
                .frame(width: cardSize.width, height: WorkspaceCardMetrics.captionHeight)
        }
        .background {
            if selected {
                RoundedRectangle(cornerRadius: WorkspaceCardMetrics.cardCornerRadius + 5, style: .continuous)
                    .fill(.white.opacity(0.14))
                    .frame(width: cardSize.width + 10, height: cardSize.height + 10)
            }
        }
    }

    private func thumbnail(for entry: WindowCycleSession.Entry, selected: Bool) -> some View {
        ZStack {
            if let image = entry.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.white.opacity(0.07))
                Image(systemName: "macwindow")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: WorkspaceCardMetrics.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WorkspaceCardMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(selected ? 0.9 : 0.12), lineWidth: selected ? 1.5 : 1)
        }
        .overlay(alignment: .bottomLeading) {
            if let icon = entry.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .padding(6)
            }
        }
        .shadow(color: .black.opacity(selected ? 0.35 : 0.1), radius: 10, y: 4)
    }
}
