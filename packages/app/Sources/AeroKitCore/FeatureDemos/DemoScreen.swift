import SwiftUI

/// Apps drawn in the demos, identified by an SF Symbol and a tint.
public enum DemoApp: CaseIterable, Sendable {
    case editor, terminal, browser, chat, mail, notes, music, calendar

    var symbol: String {
        switch self {
        case .editor: "chevron.left.forwardslash.chevron.right"
        case .terminal: "apple.terminal"
        case .browser: "safari"
        case .chat: "bubble.left.and.bubble.right"
        case .mail: "envelope"
        case .notes: "note.text"
        case .music: "music.note"
        case .calendar: "calendar"
        }
    }

    var tint: Color {
        switch self {
        case .editor: .blue
        case .terminal: .gray
        case .browser: .cyan
        case .chat: .purple
        case .mail: .indigo
        case .notes: .orange
        case .music: .pink
        case .calendar: .red
        }
    }
}

/// A workspace as AeroSpace tiles it: apps in unit-square frames.
public struct DemoWorkspace: Sendable {
    public let name: String
    public let tiles: [(app: DemoApp, frame: CGRect)]

    /// Four workspaces with distinct layouts, like a real setup.
    public static let all: [DemoWorkspace] = [
        DemoWorkspace(name: "1", tiles: [
            (.editor, CGRect(x: 0, y: 0, width: 0.58, height: 1)),
            (.terminal, CGRect(x: 0.58, y: 0, width: 0.42, height: 0.5)),
            (.browser, CGRect(x: 0.58, y: 0.5, width: 0.42, height: 0.5))
        ]),
        DemoWorkspace(name: "2", tiles: [
            (.browser, CGRect(x: 0, y: 0, width: 1, height: 1))
        ]),
        DemoWorkspace(name: "3", tiles: [
            (.chat, CGRect(x: 0, y: 0, width: 0.38, height: 1)),
            (.mail, CGRect(x: 0.38, y: 0, width: 0.62, height: 1))
        ]),
        DemoWorkspace(name: "4", tiles: [
            (.notes, CGRect(x: 0, y: 0, width: 0.5, height: 1)),
            (.music, CGRect(x: 0.5, y: 0, width: 0.5, height: 0.45)),
            (.calendar, CGRect(x: 0.5, y: 0.45, width: 0.5, height: 0.55))
        ])
    ]

    /// A tile's frame in points, with AeroSpace-style gaps around it.
    public static func tileFrame(_ unit: CGRect, in size: CGSize, gap: CGFloat) -> CGRect {
        guard size.width > gap * 2, size.height > gap * 2 else {
            return .zero
        }
        let inner = CGRect(origin: .zero, size: size).insetBy(dx: gap / 2, dy: gap / 2)
        return CGRect(
            x: inner.minX + unit.minX * inner.width,
            y: inner.minY + unit.minY * inner.height,
            width: unit.width * inner.width,
            height: unit.height * inner.height
        ).insetBy(dx: gap / 2, dy: gap / 2).standardized
    }
}

/// One window: a plain surface with the app's glyph and a few lines of
/// content. No title-bar chrome — AeroSpace windows read by their content.
public struct DemoTile: View {
    let app: DemoApp
    var focused = false
    var ring = false

    public init(app: DemoApp, focused: Bool = false, ring: Bool = false) {
        self.app = app
        self.focused = focused
        self.ring = ring
    }

    public var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let radius = max(2.5, min(7, side * 0.07))
            let glyph = max(6, min(15, side * 0.16))
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                // A toolbar band in the app's colour: enough to tell windows
                // apart, even when only an edge of one is showing.
                .overlay(alignment: .top) {
                    app.tint.opacity(0.16).frame(height: max(6, geometry.size.height * 0.13))
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: glyph * 0.45) {
                        Image(systemName: app.symbol)
                            .font(.system(size: glyph, weight: .semibold))
                            .foregroundStyle(app.tint)
                        if side > 34 {
                            lines(width: geometry.size.width, height: glyph * 0.32)
                        }
                    }
                    .padding(glyph * 0.6)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            ring || focused ? Color.accentColor : .primary.opacity(0.1),
                            lineWidth: ring ? 2.5 : focused ? 1.5 : 0.5
                        )
                }
                .shadow(color: .black.opacity(0.22), radius: max(2, side * 0.04), y: side * 0.012)
        }
    }

    private func lines(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: height * 0.9) {
            ForEach([0.62, 0.44, 0.54], id: \.self) { fraction in
                Capsule()
                    .fill(app.tint.opacity(0.14))
                    .frame(width: width * fraction * 0.8, height: height)
            }
        }
    }
}

/// A workspace's tiles drawn at any size.
public struct WorkspaceLayout: View {
    let workspace: DemoWorkspace
    var gap: CGFloat = 6
    var focused: DemoApp?

    public init(_ workspace: DemoWorkspace, gap: CGFloat = 6, focused: DemoApp? = nil) {
        self.workspace = workspace
        self.gap = gap
        self.focused = focused
    }

    public var body: some View {
        GeometryReader { geometry in
            ForEach(Array(workspace.tiles.enumerated()), id: \.offset) { _, tile in
                let frame = DemoWorkspace.tileFrame(tile.frame, in: geometry.size, gap: gap)
                DemoTile(app: tile.app, focused: tile.app == focused)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
    }
}

/// The desktop every demo plays on: a 16:10 screen with a soft wallpaper.
public struct DemoScreen<Content: View>: View {
    let content: (CGSize) -> Content

    public init(@ViewBuilder content: @escaping (CGSize) -> Content) {
        self.content = content
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                DemoWallpaper()
                content(geometry.size)
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
        }
    }
}

/// The desktop background, also behind miniature workspaces.
struct DemoWallpaper: View {
    var body: some View {
        LinearGradient(
            colors: [Color.indigo.opacity(0.75), Color.purple.opacity(0.55), Color.teal.opacity(0.6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// The dark translucent panel AeroKit's overlays sit on.
struct DemoPanel: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.black.opacity(0.74))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            }
    }
}

/// Keys being pressed, shown the way screencasts show them.
public struct KeystrokeHUD: View {
    let keys: [(label: String, pressed: Bool)]

    public init(_ keys: [(label: String, pressed: Bool)]) {
        self.keys = keys
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key.label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(key.pressed ? 1 : 0.7))
                    .frame(minWidth: 24, minHeight: 24)
                    .padding(.horizontal, key.label.count > 1 ? 6 : 0)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(key.pressed ? Color.accentColor : .white.opacity(0.13))
                    )
                    .scaleEffect(key.pressed ? 0.92 : 1)
            }
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.6)))
        .fixedSize()
    }
}

/// A small trackpad in the corner of the screen with three contacts.
struct TrackpadInset: View {
    let offset: CGSize
    let touching: Double

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
            .overlay {
                HStack(spacing: 9) {
                    ForEach(0 ..< 3) { _ in
                        Circle()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: 13, height: 13)
                            .overlay { Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5) }
                            .shadow(color: Color.accentColor.opacity(0.5), radius: 4)
                    }
                }
                .offset(offset)
                .opacity(touching)
                .scaleEffect(0.8 + 0.2 * touching)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(
                    .primary.opacity(0.2),
                    lineWidth: 0.75
                )
            }
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .frame(width: 104, height: 68)
    }
}

/// Step caption under a demo: segment bars that fill as the loop plays and
/// the sentence for the step playing now.
public struct DemoCaption: View {
    let steps: [String]
    let starts: [Double]
    let end: Double
    let progress: Double

    public init(_ steps: [String], starts: [Double], end: Double, progress: Double) {
        self.steps = steps
        self.starts = starts
        self.end = end
        self.progress = progress
    }

    private var current: Int {
        starts.lastIndex { progress >= $0 } ?? 0
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(steps.indices, id: \.self) { index in
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.primary.opacity(0.1))
                            Capsule().fill(Color.accentColor).frame(width: geometry.size.width * fill(index))
                        }
                    }
                    .frame(height: 3)
                }
            }
            Text(steps[current])
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(steps.joined(separator: " "))
    }

    private func fill(_ index: Int) -> CGFloat {
        let stop = index + 1 < starts.count ? starts[index + 1] : end
        return CGFloat(DemoTiming.unit(progress, starts[index], stop))
    }
}

/// The (i) popover body: the demo with its title.
public struct FeatureDemoCard<Demo: View>: View {
    let title: String
    let demo: Demo

    public init(_ title: String, @ViewBuilder demo: () -> Demo) {
        self.title = title
        self.demo = demo()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            demo
        }
    }
}

/// The (i) next to a settings section title: plays the section's demo.
public struct FeatureInfoButton<Demo: View>: View {
    let title: String
    let demo: () -> Demo
    @State private var isPresented = false

    public init(_ title: String, @ViewBuilder demo: @escaping () -> Demo) {
        self.title = title
        self.demo = demo
    }

    public var body: some View {
        Button { isPresented.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.tr("See how it works"))
        .accessibilityLabel(L10n.tr("See how \(title) works"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            FeatureDemoCard(title) { demo() }
                .padding(18)
                .frame(width: 420)
        }
    }
}
