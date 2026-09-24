import SwiftUI

/// The workspace grid: open it with the user's shortcut, move along, and
/// the chosen workspace grows out of its card to become the desktop.
public struct WorkspaceSwitcherDemo: View {
    let modifiers: [String]
    let key: String
    let releaseToSwitch: Bool
    let startsOnNext: Bool
    var showsCaption = true

    /// - Parameter shortcut: display keys of the opening shortcut, e.g. ["⌥", "`"].
    public init(shortcut: [String], releaseToSwitch: Bool, startsOnNext: Bool, showsCaption: Bool = true) {
        modifiers = Array(shortcut.dropLast())
        key = shortcut.last ?? ""
        self.releaseToSwitch = releaseToSwitch
        self.startsOnNext = startsOnNext
        self.showsCaption = showsCaption
    }

    private static let open = 0.12
    private static let moves = [0.34, 0.48]
    private static let commit = 0.64
    private static let landed = 0.78
    private static let reset = 0.94

    public var body: some View {
        DemoLoop(duration: 9.5, stillFrame: 0.5) { progress in
            VStack(alignment: .leading, spacing: 14) {
                DemoScreen { size in scene(progress, size: size) }
                if showsCaption {
                    DemoCaption(steps, starts: [0, 0.28, Self.commit - 0.04], end: Self.landed, progress: progress)
                }
            }
        }
    }

    private var heldKeys: String {
        modifiers.joined()
    }

    private var steps: [String] {
        releaseToSwitch
            ? [
                L10n.tr("Hold \(heldKeys) and press \(key)"),
                L10n.tr("Press \(key) again to move to the next one"),
                L10n.tr("Release \(heldKeys) to switch")
            ]
            : [
                L10n.tr("Press \(heldKeys)\(key) to open the grid"),
                L10n.tr("Choose with the arrow keys"),
                L10n.tr("Press ↵ to switch")
            ]
    }

    private func selection(_ progress: Double) -> Int {
        min(3, (startsOnNext ? 1 : 0) + DemoTiming.count(progress, Self.moves))
    }

    @ViewBuilder
    private func scene(_ progress: Double, size: CGSize) -> some View {
        let selected = selection(progress)
        let shown = DemoTiming.settle(progress, from: Self.open, to: Self.open + 0.08)
        let hidden = DemoTiming.ease(progress, from: Self.commit, to: Self.commit + 0.05)
        let zoom = DemoTiming.ease(progress, from: Self.commit, to: Self.landed)
        let workspaces = DemoWorkspace.all
        let panel = panelFrame(size)

        let backdrop = min(1, shown) * (1 - DemoTiming.ease(progress, from: Self.commit, to: Self.landed))
        WorkspaceLayout(workspaces[progress < Self.landed ? 0 : selected])
            .blur(radius: 5 * backdrop)
        Color.black.opacity(0.3 * backdrop)
        ZStack(alignment: .topLeading) {
            DemoPanel().frame(width: panel.width, height: panel.height).offset(x: panel.minX, y: panel.minY)
            ForEach(0 ..< 4) { index in
                card(workspaces[index], frame: cardFrame(index, in: size), selected: index == selected)
            }
        }
        .scaleEffect(0.94 + 0.06 * shown)
        .opacity(min(shown, 1) * (1 - hidden))
        if progress >= Self.commit, progress < Self.landed {
            let frame = DemoTiming.mix(cardFrame(selected, in: size), CGRect(origin: .zero, size: size), zoom)
            WorkspaceLayout(workspaces[selected], gap: DemoTiming.mix(3, 6, zoom))
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
        }
        if progress >= Self.reset {
            WorkspaceLayout(workspaces[0])
                .background(DemoWallpaper())
                .opacity(DemoTiming.ease(progress, from: Self.reset, to: 1))
        }
        KeystrokeHUD(keys(progress))
            .padding(.bottom, 10)
            .frame(width: size.width, height: size.height, alignment: .bottom)
            .opacity(progress < Self.landed ? 1 : 0)
    }

    private func card(_ workspace: DemoWorkspace, frame: CGRect, selected: Bool) -> some View {
        VStack(spacing: 5) {
            WorkspaceLayout(workspace, gap: 3)
                .background(DemoWallpaper())
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(
                            selected ? Color.accentColor : .white.opacity(0.12),
                            lineWidth: selected ? 2.5 : 0.5
                        )
                }
                .frame(width: frame.width, height: frame.height)
                .scaleEffect(selected ? 1.04 : 1)
            Text(workspace.name)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(selected ? 1 : 0.6))
        }
        .offset(x: frame.minX, y: frame.minY)
        .animation(.spring(duration: 0.25, bounce: 0.3), value: selected)
    }

    private func panelFrame(_ size: CGSize) -> CGRect {
        let width = size.width * 0.8
        let card = cardSize(size)
        let height = card.height + size.width * 0.035 * 2 + 16
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2 - 8, width: width, height: height)
    }

    private func cardSize(_ size: CGSize) -> CGSize {
        let width = (size.width * 0.8 - size.width * 0.035 * 2 - size.width * 0.025 * 3) / 4
        return CGSize(width: width, height: width * 10 / 16)
    }

    private func cardFrame(_ index: Int, in size: CGSize) -> CGRect {
        let panel = panelFrame(size)
        let card = cardSize(size)
        let inset = size.width * 0.035
        return CGRect(
            x: panel.minX + inset + CGFloat(index) * (card.width + size.width * 0.025),
            y: panel.minY + inset,
            width: card.width,
            height: card.height
        )
    }

    private func keys(_ progress: Double) -> [(label: String, pressed: Bool)] {
        if releaseToSwitch {
            let held = DemoTiming.during(progress, Self.open - 0.04, Self.commit)
            let taps = [Self.open] + Self.moves
            return modifiers.map { ($0, held) } + [(key, taps.contains { DemoTiming.tap(progress, at: $0) })]
        }
        let opening = DemoTiming.during(progress, Self.open - 0.03, Self.open + 0.05)
        return modifiers.map { ($0, opening) }
            + [(key, DemoTiming.tap(progress, at: Self.open))]
            + [("→", Self.moves.contains { DemoTiming.tap(progress, at: $0) })]
            + [("↵", DemoTiming.tap(progress, at: Self.commit - 0.02))]
    }
}
