import SwiftUI

/// A workspace in AeroSpace's accordion layout: every window takes the
/// same slot, stacked, with only the edges of the others peeking out. The
/// windows are there, but you can't see them — which the overview fixes.
enum AccordionGeometry {
    static let apps: [DemoApp] = [.editor, .browser, .terminal, .chat]

    /// Window `index` in the stack.
    static func stackedFrame(_ index: Int, in size: CGSize) -> CGRect {
        let gap: CGFloat = 6
        // The first layout pass can arrive with an empty size.
        guard size.width > gap * 4, size.height > gap * 4 else {
            return .zero
        }
        let peek = size.width * 0.05
        let slot = CGRect(origin: .zero, size: size).insetBy(dx: gap, dy: gap)
        let width = slot.width - peek * CGFloat(apps.count - 1)
        // Each window sits one step further right; with the front one on
        // top, earlier windows peek out on the left and later ones on the right.
        return CGRect(x: slot.minX + peek * CGFloat(index), y: slot.minY, width: width, height: slot.height)
    }

    /// Back-to-front drawing order: farthest from the front window first.
    static func order(front: Int) -> [Int] {
        apps.indices.sorted { abs($0 - front) > abs($1 - front) }
    }

    static func spreadFrame(_ index: Int, in size: CGSize) -> CGRect {
        let area = CGRect(
            x: size.width * 0.1,
            y: size.height * 0.1,
            width: size.width * 0.8,
            height: size.height * 0.68
        )
        let gap = size.width * 0.04
        let cell = CGSize(width: (area.width - gap) / 2, height: (area.height - gap) / 2)
        guard cell.width > 0, cell.height > 0 else {
            return .zero
        }
        let window = stackedFrame(0, in: size)
        guard window.width > 0, window.height > 0 else {
            return .zero
        }
        let scale = min(cell.width / window.width, cell.height / window.height) * 0.94
        let fitted = CGSize(width: window.width * scale, height: window.height * scale)
        let origin = CGPoint(
            x: area.minX + CGFloat(index % 2) * (cell.width + gap),
            y: area.minY + CGFloat(index / 2) * (cell.height + gap)
        )
        return CGRect(
            x: origin.x + (cell.width - fitted.width) / 2,
            y: origin.y + (cell.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}

/// The accordion workspace; `spread` lifts every window out of the stack
/// into a grid, each with its number.
struct OverviewScene: View {
    let size: CGSize
    let spread: Double
    var front = 0
    var ringed: Int?

    var body: some View {
        Color.black.opacity(0.32 * spread)
        ForEach(AccordionGeometry.order(front: front), id: \.self) { index in
            let frame = DemoTiming.mix(
                AccordionGeometry.stackedFrame(index, in: size),
                AccordionGeometry.spreadFrame(index, in: size),
                spread
            )
            DemoTile(app: AccordionGeometry.apps[index], focused: index == front, ring: ringed == index)
                .frame(width: frame.width, height: frame.height)
                .overlay(alignment: .topLeading) { badge(index + 1).opacity(spread).offset(x: -7, y: -7) }
                .offset(x: frame.minX, y: frame.minY)
        }
    }

    private func badge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(.black.opacity(0.7)))
    }
}

/// The window overview: lay out every window, jump to one by number.
public struct WindowOverviewDemo: View {
    let shortcut: [String]
    var showsCaption = true

    public init(shortcut: [String], showsCaption: Bool = true) {
        self.shortcut = shortcut
        self.showsCaption = showsCaption
    }

    private static let open = 0.1
    private static let pick = 0.44
    private static let closed = 0.68

    public var body: some View {
        DemoLoop(duration: 9.5, stillFrame: 0.4) { progress in
            VStack(alignment: .leading, spacing: 14) {
                DemoScreen { size in scene(progress, size: size) }
                if showsCaption {
                    DemoCaption(steps, starts: [0, Self.pick - 0.08], end: Self.closed, progress: progress)
                }
            }
        }
    }

    private var steps: [String] {
        [
            L10n.tr("Press \(shortcut.joined()) to show all windows"),
            L10n.tr("Press a number to switch to that window")
        ]
    }

    @ViewBuilder
    private func scene(_ progress: Double, size: CGSize) -> some View {
        let spread = DemoTiming.ease(progress, from: Self.open + 0.02, to: Self.open + 0.2)
            * (1 - DemoTiming.ease(progress, from: Self.pick + 0.06, to: Self.closed))
        let picked = progress >= Self.pick && progress < 0.97
        OverviewScene(
            size: size,
            spread: spread,
            front: picked ? 2 : 0,
            ringed: picked && spread > 0.3 ? 2 : nil
        )
        KeystrokeHUD(
            shortcut.dropLast().map { ($0, DemoTiming.during(progress, Self.open - 0.03, Self.open + 0.05)) }
                + [(shortcut.last ?? "", DemoTiming.tap(progress, at: Self.open))]
                + [("3", DemoTiming.tap(progress, at: Self.pick))]
        )
        .padding(.bottom, 10)
        .frame(width: size.width, height: size.height, alignment: .bottom)
        .opacity(progress < Self.closed ? 1 : 0)
    }
}

/// Three-finger swipe up for this workspace's windows, down for the
/// current app's windows from every workspace.
public struct VerticalGestureDemo: View {
    var showsCaption = true

    public init(showsCaption: Bool = true) {
        self.showsCaption = showsCaption
    }

    public var body: some View {
        DemoLoop(duration: 11.5, stillFrame: 0.25) { progress in
            VStack(alignment: .leading, spacing: 14) {
                DemoScreen { size in scene(progress, size: size) }
                if showsCaption {
                    DemoCaption(steps, starts: [0, 0.5], end: 1, progress: progress)
                }
            }
        }
    }

    private var steps: [String] {
        [
            L10n.tr("Swipe up with three fingers to show this workspace’s windows"),
            L10n.tr("Swipe down to show the current app’s windows")
        ]
    }

    @ViewBuilder
    private func scene(_ progress: Double, size: CGSize) -> some View {
        let swipeUp = progress < 0.5
        let local = progress.truncatingRemainder(dividingBy: 0.5) / 0.5
        let travel = DemoTiming.ease(local, from: 0.08, to: 0.34)
        let touching = DemoTiming.ease(local, from: 0.04, to: 0.1) * (1 - DemoTiming.ease(local, from: 0.34, to: 0.42))
        let shown = DemoTiming.ease(local, from: 0.3, to: 0.48) * (1 - DemoTiming.ease(local, from: 0.86, to: 0.98))

        if swipeUp {
            OverviewScene(size: size, spread: shown)
        } else {
            OverviewScene(size: size, spread: 0)
                .blur(radius: 5 * shown)
            appWindows(shown: shown, size: size)
        }
        TrackpadInset(
            offset: CGSize(width: 0, height: (swipeUp ? -1 : 1) * DemoTiming.mix(-12, 12, travel)),
            touching: touching
        )
        .opacity(DemoTiming.ease(local, from: 0, to: 0.05) * (1 - DemoTiming.ease(local, from: 0.44, to: 0.52)))
        .padding(10)
        .frame(width: size.width, height: size.height, alignment: .bottomTrailing)
    }

    private func appWindows(shown: Double, size: CGSize) -> some View {
        ZStack {
            Color.black.opacity(0.45 * shown)
            HStack(spacing: size.width * 0.035) {
                ForEach(["1", "2", "4"], id: \.self) { workspace in
                    DemoTile(app: .browser)
                        .frame(width: size.width * 0.27, height: size.width * 0.27 * 0.72)
                        .overlay(alignment: .bottomTrailing) {
                            Text(workspace)
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor))
                                .padding(5)
                        }
                }
            }
            .scaleEffect(0.9 + 0.1 * shown)
            .opacity(shown)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Hold-to-cycle switching: tap to walk the strip of recent windows,
/// release to focus the highlighted one.
public struct QuickWindowSwitchDemo: View {
    let modifiers: [String]
    let key: String
    var showsCaption = true

    /// - Parameter shortcut: display keys; empty shows ⌥⇥ as an example.
    public init(shortcut: [String], showsCaption: Bool = true) {
        let keys = shortcut.isEmpty ? ["⌥", "⇥"] : shortcut
        modifiers = Array(keys.dropLast())
        key = keys.last ?? ""
        self.showsCaption = showsCaption
    }

    private static let taps = [0.1, 0.32]
    private static let release = 0.6
    /// Most recent first; indices into `AccordionGeometry.apps`.
    private static let recent = [0, 1, 2, 3]

    public var body: some View {
        DemoLoop(duration: 8.5, stillFrame: 0.4) { progress in
            VStack(alignment: .leading, spacing: 14) {
                DemoScreen { size in scene(progress, size: size) }
                if showsCaption {
                    DemoCaption(steps, starts: [0, 0.26, Self.release - 0.04], end: 0.7, progress: progress)
                }
            }
        }
    }

    private var steps: [String] {
        [
            L10n.tr("Hold \(modifiers.joined()) and press \(key)"),
            L10n.tr("Press \(key) again for the next window"),
            L10n.tr("Release the keys to switch")
        ]
    }

    @ViewBuilder
    private func scene(_ progress: Double, size: CGSize) -> some View {
        let selected = DemoTiming.count(progress, Self.taps)
        let shown = DemoTiming.settle(progress, from: 0.11, to: 0.19)
            * (1 - DemoTiming.ease(progress, from: Self.release, to: Self.release + 0.05))
        let switched = progress >= Self.release && progress < 0.97
        OverviewScene(size: size, spread: 0, front: switched ? Self.recent[max(selected, 1)] : 0)
            .blur(radius: 3 * min(1, shown))
        Color.black.opacity(0.25 * min(1, shown))
        HStack(spacing: size.width * 0.02) {
            ForEach(Self.recent.indices, id: \.self) { index in
                DemoTile(app: AccordionGeometry.apps[Self.recent[index]], ring: index == selected)
                    .frame(width: size.width * 0.17, height: size.width * 0.17 * 0.7)
                    .scaleEffect(index == selected ? 1.06 : 1)
            }
        }
        .padding(size.width * 0.022)
        .background(DemoPanel())
        .scaleEffect(0.95 + 0.05 * min(1, shown))
        .opacity(min(1, shown))
        .frame(width: size.width, height: size.height)
        KeystrokeHUD(
            modifiers.map { ($0, DemoTiming.during(progress, 0.06, Self.release)) }
                + [(key, Self.taps.contains { DemoTiming.tap(progress, at: $0) })]
        )
        .padding(.bottom, 10)
        .frame(width: size.width, height: size.height, alignment: .bottom)
        .opacity(progress < Self.release + 0.08 ? 1 : 0)
    }
}
