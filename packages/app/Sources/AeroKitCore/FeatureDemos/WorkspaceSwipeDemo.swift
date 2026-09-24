import SwiftUI

/// Three-finger swipes: the HUD strip follows the fingers, and lifting
/// lands on the highlighted workspace. Left, then back right.
public struct WorkspaceSwipeDemo: View {
    let naturalDirection: Bool
    var showsCaption = true

    public init(naturalDirection: Bool, showsCaption: Bool = true) {
        self.naturalDirection = naturalDirection
        self.showsCaption = showsCaption
    }

    public var body: some View {
        DemoLoop(duration: 10.5, stillFrame: 0.3) { progress in
            let local = progress.truncatingRemainder(dividingBy: 0.5) / 0.5
            VStack(alignment: .leading, spacing: 14) {
                DemoScreen { size in scene(progress, size: size) }
                if showsCaption {
                    DemoCaption(steps, starts: [0, 0.12, 0.5], end: 0.62, progress: local)
                }
            }
        }
    }

    private var steps: [String] {
        [
            L10n.tr("Rest three fingers on the trackpad"),
            L10n.tr("Swipe left or right"),
            L10n.tr("Lift your fingers to switch")
        ]
    }

    /// Swipe left in the first half, back right in the second; which way
    /// the selection moves depends on the direction setting.
    @ViewBuilder
    private func scene(_ progress: Double, size: CGSize) -> some View {
        let swipeLeft = progress < 0.5
        let local = progress.truncatingRemainder(dividingBy: 0.5) / 0.5
        let step = (swipeLeft == naturalDirection) ? 1 : -1
        let start = swipeLeft ? 1 : 1 + (naturalDirection ? 1 : -1)
        let travel = DemoTiming.ease(local, from: 0.12, to: 0.5)
        let position = Double(start) + Double(step) * travel
        let landed = DemoTiming.ease(local, from: 0.5, to: 0.56)
        let strip = DemoTiming.settle(local, from: 0.08, to: 0.18) * (1 - DemoTiming.ease(local, from: 0.54, to: 0.62))
        let touching = DemoTiming.ease(local, from: 0.04, to: 0.1) * (1 - DemoTiming.ease(local, from: 0.5, to: 0.56))
        let workspaces = DemoWorkspace.all

        WorkspaceLayout(workspaces[start])
        WorkspaceLayout(workspaces[start + step])
            .background(DemoWallpaper())
            .opacity(landed)
        WorkspaceStripHUD(position: position, size: size)
            .opacity(min(1, strip))
            .scaleEffect(0.96 + 0.04 * min(1, strip), anchor: .bottom)
        TrackpadInset(
            offset: CGSize(width: (swipeLeft ? -1 : 1) * DemoTiming.mix(-16, 16, travel), height: 0),
            touching: touching
        )
        .opacity(DemoTiming.ease(local, from: 0, to: 0.05) * (1 - DemoTiming.ease(local, from: 0.58, to: 0.66)))
        .padding(10)
        .frame(width: size.width, height: size.height, alignment: .topTrailing)
    }
}

/// AeroKit's swipe HUD: workspace cards along the bottom with a highlight
/// at a fractional `position`, so it can ride along with the fingers.
struct WorkspaceStripHUD: View {
    let position: Double
    let size: CGSize

    var body: some View {
        let card = CGSize(width: size.width * 0.15, height: size.width * 0.15 * 10 / 16)
        let spacing = size.width * 0.018
        let inset = size.width * 0.02
        let workspaces = DemoWorkspace.all
        ZStack(alignment: .topLeading) {
            HStack(spacing: spacing) {
                ForEach(0 ..< 4) { index in
                    VStack(spacing: 4) {
                        WorkspaceLayout(workspaces[index], gap: 2.5)
                            .background(DemoWallpaper())
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .frame(width: card.width, height: card.height)
                        Text(workspaces[index].name)
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(abs(Double(index) - position) < 0.5 ? 1 : 0.55))
                    }
                }
            }
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2.5)
                .frame(width: card.width + 4, height: card.height + 4)
                .offset(x: CGFloat(position) * (card.width + spacing) - 2, y: -2)
        }
        .padding(inset)
        .background(DemoPanel())
        .fixedSize()
        .padding(.bottom, size.height * 0.06)
        .frame(width: size.width, height: size.height, alignment: .bottom)
    }
}
