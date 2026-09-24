import SwiftUI

/// The welcome tour's opening scene: a calm tour through four tiled
/// workspaces with the swipe HUD passing between them.
public struct AmbientDesktopDemo: View {
    public init() {}

    public var body: some View {
        DemoLoop(duration: 13, stillFrame: 0.1) { progress in
            DemoScreen { size in scene(progress, size: size) }
        }
    }

    @ViewBuilder
    private func scene(_ progress: Double, size: CGSize) -> some View {
        let segment = min(3, Int(progress * 4))
        let local = progress * 4 - Double(segment)
        let next = (segment + 1) % 4
        let move = DemoTiming.ease(local, from: 0.62, to: 0.84)
        let strip = DemoTiming.settle(local, from: 0.55, to: 0.65) * (1 - DemoTiming.ease(local, from: 0.9, to: 0.98))
        let workspaces = DemoWorkspace.all
        WorkspaceLayout(workspaces[segment])
        WorkspaceLayout(workspaces[next])
            .background(DemoWallpaper())
            .opacity(DemoTiming.ease(local, from: 0.84, to: 0.92))
        WorkspaceStripHUD(position: Double(segment) + Double(next - segment) * move, size: size)
            .opacity(min(1, strip))
    }
}

/// The permission page's scene: grid cards start empty and fill with
/// pictures of each workspace — what Screen Recording makes possible.
public struct PreviewCaptureDemo: View {
    public init() {}

    public var body: some View {
        DemoLoop(duration: 7, stillFrame: 0.8) { progress in
            DemoScreen { size in scene(progress, size: size) }
        }
    }

    @ViewBuilder
    private func scene(_ progress: Double, size: CGSize) -> some View {
        let workspaces = DemoWorkspace.all
        let card = CGSize(width: size.width * 0.17, height: size.width * 0.17 * 10 / 16)
        WorkspaceLayout(workspaces[0])
            .blur(radius: 5)
        Color.black.opacity(0.3)
        HStack(spacing: size.width * 0.025) {
            ForEach(0 ..< 4) { index in
                let filled = DemoTiming.ease(
                    progress,
                    from: 0.15 + 0.13 * Double(index),
                    to: 0.25 + 0.13 * Double(index)
                )
                    * (1 - DemoTiming.ease(progress, from: 0.9, to: 0.98))
                VStack(spacing: 5) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.08))
                        Image(systemName: "photo")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.35))
                        WorkspaceLayout(workspaces[index], gap: 3)
                            .background(DemoWallpaper())
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .opacity(filled)
                    }
                    .frame(width: card.width, height: card.height)
                    Text(workspaces[index].name)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(size.width * 0.035)
        .background(DemoPanel())
        .frame(width: size.width, height: size.height)
    }
}
