import AeroKitCore
import AppKit
import CoreGraphics
import SwiftUI

/// Single settings window with one tab per feature plus a General tab for
/// app-level concerns (permission, login item). Styled after Raycast's
/// settings: an icon tab bar merged into the title bar, a hairline divider,
/// and a fixed-size scrolling content area.
@MainActor
final class SettingsWindowController {
    private static let contentSize = NSSize(width: 560, height: 600)

    private let content: AeroKitSettingsView
    private let onWillShow: () -> Void
    private var window: NSWindow?
    /// Never removed: the coordinator keeps this controller for the app's
    /// lifetime, and a nonisolated deinit could not touch it anyway.
    private var activationObserver: (any NSObjectProtocol)?

    init(
        client: AeroSpaceClient,
        switcherPane: some View,
        exposePane: some View,
        swipePane: some View,
        onWillShow: @escaping () -> Void
    ) {
        let general = GeneralSettingsModel(client: client)
        content = AeroKitSettingsView(
            generalModel: general,
            switcherPane: AnyView(switcherPane),
            exposePane: AnyView(exposePane),
            swipePane: AnyView(swipePane)
        )
        self.onWillShow = onWillShow

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak general] _ in
            Task { @MainActor in
                guard self?.window?.isVisible == true else { return }
                general?.refreshStatus()
            }
        }
    }

    /// CGWindowID of the settings window once it has been shown.
    var windowID: CGWindowID? {
        window.map { CGWindowID($0.windowNumber) }
    }

    func show() {
        onWillShow()
        content.generalModel.refreshStatus()

        if window == nil {
            let hostingView = NSHostingView(rootView: content)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: Self.contentSize),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "AeroKit"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.contentView = hostingView
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Root view

struct AeroKitSettingsView: View {
    @ObservedObject var generalModel: GeneralSettingsModel
    let switcherPane: AnyView
    let exposePane: AnyView
    let swipePane: AnyView

    @State private var selectedTab = Tab.general

    enum Tab: String, CaseIterable {
        case general = "General"
        case switcher = "Switcher"
        case expose = "Exposé"
        case swipe = "Swipe"

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .switcher: "rectangle.3.group"
            case .expose: "square.grid.2x2"
            case .swipe: "hand.draw"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            ScrollView {
                pane
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            SettingsBackdrop().ignoresSafeArea()
        }
    }

    @ViewBuilder private var pane: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsView(model: generalModel)
        case .switcher:
            switcherPane
        case .expose:
            exposePane
        case .swipe:
            swipePane
        }
    }

    /// Raycast-style tab strip living in the (transparent) title bar area:
    /// traffic lights sit at the left, the icon tabs are centered.
    private var tabBar: some View {
        HStack(spacing: 10) {
            ForEach(Tab.allCases, id: \.self) { tab in
                TabButton(tab: tab, isSelected: tab == selectedTab) {
                    selectedTab = tab
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }
}

private struct TabButton: View {
    let tab: AeroKitSettingsView.Tab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(height: 18)
                Text(tab.rawValue)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(width: 72, height: 46)
            .background {
                if isSelected || isHovering {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.primary.opacity(isSelected ? 0.08 : 0.04))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
