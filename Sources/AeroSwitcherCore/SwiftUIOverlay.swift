import AppKit
import SwiftUI

@MainActor
public final class SwiftUIOverlay: ObservableObject {
    @Published public private(set) var items: [WorkspacePresentation] = []
    @Published public private(set) var selectedIndex = 0
    @Published public private(set) var isLoading = false
    @Published public private(set) var snapshotFeedback: SnapshotRefreshFeedback = .idle

    public var onAdvance: (() -> Void)?
    public var onMove: ((SelectionMove) -> Void)?
    public var onSelect: (() -> Void)?
    public var onQuickSelect: ((String) -> Void)?
    public var onActivateWorkspace: ((String) -> Void)?
    public var onReloadSnapshots: (() -> Void)?
    public var onCancel: (() -> Void)?

    private let configuration: SwitcherConfiguration
    private let panel: OverlayPanel
    private var hostingView: NSHostingView<SwitcherOverlayView>?
    private var keyMonitor: Any?

    public var isVisible: Bool {
        panel.isVisible
    }

    public init(configuration: SwitcherConfiguration) {
        self.configuration = configuration
        panel = OverlayPanel(contentRect: .zero)
        panel.keyHandler = { [weak self] event in
            self?.handleKey(event) ?? false
        }
    }

    public func show(
        items: [WorkspacePresentation],
        selectedIndex: Int,
        isLoading: Bool,
        snapshotFeedback: SnapshotRefreshFeedback
    ) {
        update(
            items: items,
            selectedIndex: selectedIndex,
            isLoading: isLoading,
            snapshotFeedback: snapshotFeedback
        )
        ensureHostingView()
        positionPanel()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        startDismissMonitors()
    }

    public func update(
        items: [WorkspacePresentation],
        selectedIndex: Int,
        isLoading: Bool,
        snapshotFeedback: SnapshotRefreshFeedback
    ) {
        self.items = items
        self.selectedIndex = selectedIndex
        self.isLoading = isLoading
        self.snapshotFeedback = snapshotFeedback
    }

    public func hide() {
        stopDismissMonitors()
        panel.orderOut(nil)
    }

    public func activateWorkspace(named name: String) {
        onActivateWorkspace?(name)
    }

    public func cancel() {
        onCancel?()
    }

    private func ensureHostingView() {
        guard hostingView == nil else {
            return
        }

        let view = SwitcherOverlayView(model: self, configuration: configuration)
        let hostingView = NSHostingView(rootView: view)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView
        self.hostingView = hostingView
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else {
            return
        }

        panel.setFrame(screen.frame, display: true)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if isSnapshotReloadShortcut(event) {
            onReloadSnapshots?()
            return true
        }

        if handleNavigationKey(event) {
            return true
        }

        if let workspace = quickWorkspace(from: event) {
            onQuickSelect?(workspace)
        } else {
            onCancel?()
        }
        return true
    }

    private func handleNavigationKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case KeyCode.backtick:
            onAdvance?()
        case KeyCode.return, KeyCode.keypadEnter:
            onSelect?()
        case KeyCode.escape:
            onCancel?()
        case KeyCode.leftArrow:
            onMove?(.left)
        case KeyCode.rightArrow:
            onMove?(.right)
        case KeyCode.downArrow:
            onMove?(.down)
        case KeyCode.upArrow:
            onMove?(.up)
        case KeyCode.tab:
            onMove?(.next)
        default:
            return false
        }
        return true
    }

    private func quickWorkspace(from event: NSEvent) -> String? {
        guard let characters = event.charactersIgnoringModifiers?.uppercased() else {
            return nil
        }
        return configuration.workspaceOrder.contains(characters) ? characters : nil
    }

    private func isSnapshotReloadShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.option),
              !flags.contains(.control),
              !flags.contains(.shift)
        else {
            return false
        }

        return event.charactersIgnoringModifiers?.uppercased() == "R"
    }

    private func startDismissMonitors() {
        stopDismissMonitors()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, panel.isVisible else {
                return event
            }
            return handleKey(event) ? nil : event
        }
    }

    private func stopDismissMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

private enum KeyCode {
    static let `return`: UInt16 = 36
    static let tab: UInt16 = 48
    static let backtick: UInt16 = 50
    static let escape: UInt16 = 53
    static let keypadEnter: UInt16 = 76
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}

private final class OverlayPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

public struct SwitcherOverlayView: View {
    @ObservedObject private var model: SwiftUIOverlay
    private let configuration: SwitcherConfiguration

    public init(model: SwiftUIOverlay, configuration: SwitcherConfiguration) {
        self.model = model
        self.configuration = configuration
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    model.cancel()
                }

            VStack(spacing: 8) {
                SnapshotRefreshBadge(feedback: model.snapshotFeedback)
                    .frame(height: 26)

                LazyVGrid(columns: gridColumns, spacing: configuration.padding) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        WorkspaceCard(
                            item: item,
                            isSelected: index == model.selectedIndex,
                            configuration: configuration
                        ) {
                            model.activateWorkspace(named: item.workspace.name)
                        }
                    }
                }
            }
            .padding(configuration.padding)
            .frame(width: contentSize.width, height: contentSize.height)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.73))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentSize: CGSize {
        let columns = max(1, configuration.columns)
        let rows = max(1, Int(ceil(Double(model.items.count) / Double(columns))))
        let rowHeight = configuration.snapshotSize.height + configuration.snapshotAppIconSize + 12 + 24
        let feedbackHeight: CGFloat = 26 + 8
        return CGSize(
            width: CGFloat(columns) * configuration.snapshotSize.width + CGFloat(columns + 1) * configuration.padding,
            height: CGFloat(rows) * rowHeight + CGFloat(rows + 1) * configuration.padding + feedbackHeight
        )
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(configuration.snapshotSize.width), spacing: configuration.padding),
            count: max(1, configuration.columns)
        )
    }
}

private struct SnapshotRefreshBadge: View {
    let feedback: SnapshotRefreshFeedback

    var body: some View {
        HStack(spacing: 8) {
            icon

            Text(feedback.message)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 12)
        .frame(maxWidth: 360)
        .frame(height: 26)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(feedback.isVisible ? 0.12 : 0))
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(feedback.isVisible ? 0.12 : 0), lineWidth: 1)
        }
        .opacity(feedback.isVisible ? 1 : 0)
    }

    @ViewBuilder private var icon: some View {
        switch feedback {
        case .idle:
            EmptyView()
        case .refreshing:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.65)
        case .success:
            Image(systemName: "checkmark.circle.fill")
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
        }
    }

    private var foregroundColor: Color {
        switch feedback {
        case .idle:
            Color.clear
        case .refreshing:
            Color.white.opacity(0.88)
        case .success:
            Color.green.opacity(0.9)
        case .failure:
            Color.red.opacity(0.9)
        }
    }
}

private struct WorkspaceCard: View {
    let item: WorkspacePresentation
    let isSelected: Bool
    let configuration: SwitcherConfiguration
    let onActivate: () -> Void

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
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
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
