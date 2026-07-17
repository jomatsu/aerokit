import AppKit
import SwiftUI

/// Drag-to-reorder editor for the shared workspace order: the workspaces
/// AeroSpace actually reports appear as chips — name plus the key combo
/// bound to them — in their effective order. Reordering uses a plain drag
/// gesture, not system drag-and-drop: a drop released outside a target
/// would cancel silently and leave the visual order uncommitted.
public struct WorkspaceOrderEditor: View {
    @ObservedObject private var store: WorkspaceOrderStore
    private let loadWorkspaces: @Sendable () throws -> [WorkspaceOrderEntry]

    @State private var entries: [WorkspaceOrderEntry] = []
    @State private var dragged: String?
    @State private var chipFrames: [String: CGRect] = [:]
    @State private var didLoad = false
    @State private var loadFailed = false

    private static let chipSpace = "workspaceOrderChips"

    public init(
        store: WorkspaceOrderStore,
        loadWorkspaces: @escaping @Sendable () throws -> [WorkspaceOrderEntry]
    ) {
        _store = ObservedObject(wrappedValue: store)
        self.loadWorkspaces = loadWorkspaces
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            footer
        }
        .onAppear { reload() }
        .onChange(of: store.order) { resortFromStore() }
    }

    @ViewBuilder private var content: some View {
        if loadFailed {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Could not load workspaces from AeroSpace")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Retry") { reload() }
                    .controlSize(.small)
            }
        } else if entries.isEmpty {
            Text(didLoad ? "No workspaces found" : "Loading workspaces…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            chips
        }
    }

    private var chips: some View {
        ChipFlowLayout(spacing: 6) {
            ForEach(entries, id: \.name) { entry in
                WorkspaceOrderChip(entry: entry, isDragged: dragged == entry.name)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ChipFrameKey.self,
                                value: [entry.name: proxy.frame(in: .named(Self.chipSpace))]
                            )
                        }
                    }
                    .zIndex(dragged == entry.name ? 1 : 0)
                    .gesture(dragGesture(for: entry.name))
            }
        }
        .coordinateSpace(name: Self.chipSpace)
        .onPreferenceChange(ChipFrameKey.self) { chipFrames = $0 }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The settings window is movable by background; without this the
        // mouse-down on a chip drags the whole window instead of the chip.
        .background(WindowDragBlocker())
    }

    /// Reordering runs on the hover position and the gesture end always
    /// commits — unlike a system drop, releasing anywhere keeps the change.
    private func dragGesture(for name: String) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.chipSpace))
            .onChanged { value in
                dragged = name
                // The inset shrinks the trigger region so chips of unequal
                // width cannot flip back and forth under a resting pointer.
                guard let target = chipFrames.first(where: { key, frame in
                    key != name && frame.insetBy(dx: frame.width * 0.2, dy: 0).contains(value.location)
                })?.key,
                    let from = entries.firstIndex(where: { $0.name == name }),
                    let to = entries.firstIndex(where: { $0.name == target })
                else {
                    return
                }
                withAnimation(.spring(duration: 0.25)) {
                    entries.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                }
            }
            .onEnded { _ in
                dragged = nil
                commitOrder()
            }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .help("Reload workspaces")

            if store.order != WorkspaceOrderStore.defaultOrder {
                Button("Reset to Default") {
                    store.order = WorkspaceOrderStore.defaultOrder
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }

            Spacer()
        }
    }

    private func reload() {
        let load = loadWorkspaces
        let priority = store.order
        Task {
            let loaded = await BlockingWork.run { () -> [WorkspaceOrderEntry]? in
                try? load()
            }
            didLoad = true
            if let loaded {
                loadFailed = false
                let comparator = WorkspaceOrdering.comparator(priority: priority)
                entries = loaded.sorted { comparator($0.name, $1.name) }
            } else if entries.isEmpty {
                loadFailed = true
            }
        }
    }

    /// A reset — or a reorder committed in the other settings pane — must
    /// rearrange the chips shown here too.
    private func resortFromStore() {
        guard dragged == nil else {
            return
        }
        let comparator = WorkspaceOrdering.comparator(priority: store.order)
        entries = entries.sorted { comparator($0.name, $1.name) }
    }

    /// The full arrangement is stored, not a diff: the chips are the
    /// workspaces that exist right now, and unlisted future ones follow in
    /// natural order.
    private func commitOrder() {
        store.order = entries.map(\.name)
    }
}

// MARK: - Chip

private struct WorkspaceOrderChip: View {
    let entry: WorkspaceOrderEntry
    let isDragged: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(entry.name)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.85))
            if let combo = entry.keyBinding {
                Text(KeyComboDisplay.symbols(combo))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background {
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(.quaternary)
                    }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary.opacity(0.7))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
        }
        .scaleEffect(isDragged ? 1.06 : 1)
        .shadow(color: .black.opacity(isDragged ? 0.25 : 0), radius: 4, y: 2)
        .animation(.spring(duration: 0.2), value: isDragged)
    }
}

private struct ChipFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Opts the chip strip out of `isMovableByWindowBackground`: AppKit asks
/// the deepest hit-tested view whether a mouse-down may move the window,
/// and the hosting view's default yes would swallow chip drags.
private struct WindowDragBlocker: NSViewRepresentable {
    final class BlockerView: NSView {
        override var mouseDownCanMoveWindow: Bool {
            false
        }
    }

    func makeNSView(context: Context) -> BlockerView {
        BlockerView()
    }

    func updateNSView(_ nsView: BlockerView, context: Context) {}
}

// MARK: - Flow layout

/// Left-aligned wrapping row layout for the chips.
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        frames(for: subviews, maxWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placement = frames(for: subviews, maxWidth: bounds.width)
        for (subview, frame) in zip(subviews, placement.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func frames(for subviews: Subviews, maxWidth: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX > 0, cursorX + size.width > maxWidth {
                cursorX = 0
                cursorY += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: cursorX, y: cursorY), size: size))
            rowHeight = max(rowHeight, size.height)
            cursorX += size.width + spacing
            width = max(width, cursorX - spacing)
        }
        return (frames, CGSize(width: width, height: cursorY + rowHeight))
    }
}
