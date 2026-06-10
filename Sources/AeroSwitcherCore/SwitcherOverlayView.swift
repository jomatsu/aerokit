import AppKit
import SwiftUI

public struct SwitcherOverlayView: View {
    @ObservedObject private var model: SwiftUIOverlay
    @ObservedObject private var preferences: AppPreferences
    private let configuration: SwitcherConfiguration

    public init(model: SwiftUIOverlay, configuration: SwitcherConfiguration, preferences: AppPreferences) {
        self.model = model
        self.configuration = configuration
        self.preferences = preferences
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    model.cancel()
                }

            panel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                SnapshotRefreshBadge(feedback: model.snapshotFeedback)
                    .frame(height: 26)

                grid
            }
            .padding(configuration.padding)

            if preferences.showOverlayHints {
                OverlayHintFooter(preferences: preferences)
            }
        }
        .frame(width: contentSize.width, height: contentSize.height)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.73))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(model.isShown ? 1 : 0.97)
        .opacity(model.isShown ? 1 : 0)
        .animation(.easeOut(duration: 0.13), value: model.isShown)
    }

    @ViewBuilder private var grid: some View {
        if model.items.isEmpty {
            Text("No workspaces found. Is AeroSpace running?")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LazyVGrid(columns: gridColumns, spacing: configuration.padding) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    WorkspaceCard(
                        item: item,
                        isSelected: index == model.selectedIndex,
                        configuration: configuration,
                        onActivate: {
                            model.activateWorkspace(named: item.workspace.name)
                        },
                        onHover: {
                            model.hoverSelect(index: index)
                        }
                    )
                }
            }
        }
    }

    private var columnCount: Int {
        max(1, min(preferences.gridColumns, max(1, model.items.count)))
    }

    private var contentSize: CGSize {
        let columns = columnCount
        let rows = max(1, Int(ceil(Double(model.items.count) / Double(columns))))
        let rowHeight = configuration.snapshotSize.height + configuration.snapshotAppIconSize + 12 + 24
        var chromeHeight: CGFloat = 26 + 8
        if preferences.showOverlayHints {
            chromeHeight += OverlayHintFooter.height
        }
        return CGSize(
            width: CGFloat(columns) * configuration.snapshotSize.width + CGFloat(columns + 1) * configuration.padding,
            height: CGFloat(rows) * rowHeight + CGFloat(rows + 1) * configuration.padding + chromeHeight
        )
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(configuration.snapshotSize.width), spacing: configuration.padding),
            count: columnCount
        )
    }
}

// MARK: - Hint footer

private struct OverlayHintFooter: View {
    static let height: CGFloat = 38

    @ObservedObject var preferences: AppPreferences

    var body: some View {
        HStack(spacing: 16) {
            Text(releaseHint)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.45))
            HintItem(label: "Cycle", keys: preferences.hotKey.displayKeys)

            Spacer()

            HintItem(label: "Refresh", keys: preferences.refreshShortcut.displayKeys)
            separator
            HintItem(label: "Settings", keys: preferences.settingsShortcut.displayKeys)
            separator
            HintItem(label: "Close", keys: ["esc"])
        }
        .padding(.horizontal, 16)
        .frame(height: Self.height)
        .background(Color.white.opacity(0.03))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var releaseHint: String {
        let modifiers = preferences.hotKey.displayKeys.dropLast().joined()
        return "Release \(modifiers) to switch"
    }

    private var separator: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: 12)
    }
}

private struct HintItem: View {
    let label: String
    let keys: [String]

    var body: some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.45))

            KeyCapGroup(
                keys: keys,
                foreground: AnyShapeStyle(Color.white.opacity(0.75)),
                background: AnyShapeStyle(Color.white.opacity(0.08))
            )
        }
    }
}

// MARK: - Refresh badge

private struct SnapshotRefreshBadge: View {
    let feedback: SnapshotRefreshFeedback

    private static let accent = Color(red: 0.4, green: 0.6, blue: 1)

    var body: some View {
        HStack(spacing: 8) {
            icon

            Text(feedback.message)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.white.opacity(0.92))
        .padding(.horizontal, 14)
        .frame(height: 26)
        .frame(minWidth: 230)
        .background {
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.45))

                GeometryReader { proxy in
                    Rectangle()
                        .fill(fillGradient)
                        .frame(width: proxy.size.width * fillFraction)
                }
            }
            .clipShape(Capsule(style: .continuous))
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .opacity(feedback.isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: feedback)
    }

    @ViewBuilder private var icon: some View {
        switch feedback {
        case .idle:
            EmptyView()
        case .refreshing:
            // The filling background is the indicator once progress is known;
            // the spinner only covers the brief indeterminate start.
            if feedback.progress == nil {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            }
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green.opacity(0.95))
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.red.opacity(0.95))
        }
    }

    private var fillFraction: CGFloat {
        switch feedback {
        case .idle:
            0
        case .refreshing:
            CGFloat(feedback.progress ?? 0)
        case .success, .failure:
            1
        }
    }

    private var fillGradient: LinearGradient {
        let colors: [Color] = switch feedback {
        case .success:
            [Color.green.opacity(0.40), Color.green.opacity(0.18)]
        case .failure:
            [Color.red.opacity(0.45), Color.red.opacity(0.20)]
        default:
            [Self.accent.opacity(0.60), Self.accent.opacity(0.28)]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Workspace card

private struct WorkspaceCard: View {
    let item: WorkspacePresentation
    let isSelected: Bool
    let configuration: SwitcherConfiguration
    let onActivate: () -> Void
    let onHover: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            preview
            appIconRow
                .frame(height: configuration.snapshotAppIconSize + 12)
            Text(item.workspace.name)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isSelected || item.workspace.isFocused ? selectedColor : Color.white)
                .frame(width: configuration.snapshotSize.width, height: 24)
        }
        .frame(width: configuration.snapshotSize.width)
        .opacity(item.workspace.isEmpty && !isSelected ? 0.45 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .onHover { hovering in
            if hovering {
                onHover()
            }
        }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.72))

            if let snapshot = item.snapshot {
                Image(nsImage: snapshot)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Text(item.workspace.name)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.4))
            }

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.10) : Color.clear)
                .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? selectedColor : Color.clear, lineWidth: 3)
                .allowsHitTesting(false)
        }
        .frame(width: configuration.snapshotSize.width, height: configuration.snapshotSize.height)
    }

    private var appIconRow: some View {
        HStack(spacing: 7) {
            ForEach(Array(item.appIcons.prefix(configuration.maxAppIcons).enumerated()), id: \.offset) { _, icon in
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: configuration.snapshotAppIconSize, height: configuration.snapshotAppIconSize)
            }
        }
        .frame(width: configuration.snapshotSize.width)
    }

    private var selectedColor: Color {
        Color(red: 0.4, green: 0.6, blue: 1)
    }
}
