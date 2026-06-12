import AppKit
import SwiftUI
import XCTest

/// Not an assertion suite: renders candidate swipe-HUD designs with mock
/// data to /tmp/aerokit-variant-*.png so they can be compared side by
/// side. Skipped unless RENDER_HUD_VARIANTS=1. Self-contained on purpose —
/// these views are throwaway sketches, not production code.
@MainActor
final class SwipeHUDVariantRenderTests: XCTestCase {
    struct Workspace {
        var name: String
        var preview: NSImage?
        var apps: [(name: String, icon: NSImage)]
    }

    static let workspaces: [Workspace] = [
        Workspace(name: "1", preview: HUDRenderMocks.fakeScreenshot(hue: 0.58), apps: [
            ("Safari", HUDRenderMocks.fakeIcon(hue: 0.6)), ("Mail", HUDRenderMocks.fakeIcon(hue: 0.95)),
        ]),
        Workspace(name: "2", preview: HUDRenderMocks.fakeScreenshot(hue: 0.08), apps: [
            ("Code", HUDRenderMocks.fakeIcon(hue: 0.1)), ("Terminal", HUDRenderMocks.fakeIcon(hue: 0.5)), ("Slack", HUDRenderMocks.fakeIcon(hue: 0.8)),
        ]),
        Workspace(name: "3", preview: HUDRenderMocks.fakeScreenshot(hue: 0.33), apps: [
            ("Figma", HUDRenderMocks.fakeIcon(hue: 0.3)),
        ]),
        Workspace(name: "browser", preview: HUDRenderMocks.fakeScreenshot(hue: 0.75), apps: []),
        Workspace(name: "code", preview: nil, apps: [
            ("Xcode", HUDRenderMocks.fakeIcon(hue: 0.55)), ("Music", HUDRenderMocks.fakeIcon(hue: 0.0)),
        ]),
    ]
    static let selectedIndex = 1

    func testRenderVariants() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RENDER_HUD_VARIANTS"] == "1")
        render(AnyView(HeaderVariant()), name: "a-header")
        render(AnyView(CmdTabVariant()), name: "b-cmdtab")
        render(AnyView(AltTabVariant()), name: "c-alttab")
        render(AnyView(ScrimVariant()), name: "d-scrim")
    }

    private func render(_ view: AnyView, name: String) {
        let content = view
            .frame(width: 900, height: 230)
            .background(Color(white: 0.35))
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              HUDRenderMocks.writePNG(image, to: "/tmp/aerokit-variant-\(name).png")
        else {
            XCTFail("render failed: \(name)")
            return
        }
    }

    // MARK: - Shared chrome

    /// The panel glass every variant sits on.
    struct Panel<Content: View>: View {
        @ViewBuilder var content: Content

        var body: some View {
            VStack {
                Spacer(minLength: 0)
                content
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.black.opacity(0.5))
                            .background {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [.white.opacity(0.22), .white.opacity(0.05)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 1
                                    )
                            }
                            .shadow(color: .black.opacity(0.45), radius: 30, y: 14)
                    }
            }
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
        }
    }

    static func thumb(_ workspace: Workspace, selected: Bool, size: CGSize = CGSize(width: 100, height: 62.5)) -> some View {
        ZStack {
            if let preview = workspace.preview {
                Image(nsImage: preview).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.white.opacity(0.07))
                Image(systemName: "macwindow")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.black.opacity(selected ? 0 : 0.32))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(selected ? 0.9 : 0), lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(selected ? 0.35 : 0), radius: 10, y: 4)
    }

    static func nameLabel(_ name: String, selected: Bool) -> some View {
        Text(name)
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(selected ? 1 : 0.5))
            .lineLimit(1)
    }

    // MARK: - A: detail header

    /// Minimal cells (thumbnail + name); the selected workspace's apps show
    /// in one roomy header line above the grid, icon + app name pairs.
    struct HeaderVariant: View {
        var body: some View {
            Panel {
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        ForEach(Array(workspaces[selectedIndex].apps.enumerated()), id: \.offset) { _, app in
                            HStack(spacing: 5) {
                                Image(nsImage: app.icon).resizable().frame(width: 18, height: 18)
                                Text(app.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }
                    .frame(height: 20)
                    HStack(spacing: 14) {
                        ForEach(Array(workspaces.enumerated()), id: \.offset) { index, workspace in
                            let selected = index == selectedIndex
                            VStack(spacing: 7) {
                                thumb(workspace, selected: selected)
                                nameLabel(workspace.name, selected: selected)
                            }
                            .padding(6)
                            .background {
                                if selected {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.white.opacity(0.12))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: - B: cmd-tab, icons as the hero

    /// No screenshots: each workspace is its app icons at switcher size,
    /// name below, soft square highlight behind the selection.
    struct CmdTabVariant: View {
        var body: some View {
            Panel {
                HStack(spacing: 10) {
                    ForEach(Array(workspaces.enumerated()), id: \.offset) { index, workspace in
                        let selected = index == selectedIndex
                        VStack(spacing: 8) {
                            HStack(spacing: -10) {
                                if workspace.apps.isEmpty {
                                    Image(systemName: "macwindow")
                                        .font(.system(size: 26, weight: .light))
                                        .foregroundStyle(.white.opacity(0.3))
                                        .frame(width: 44, height: 44)
                                } else {
                                    ForEach(Array(workspace.apps.prefix(3).enumerated()), id: \.offset) { offset, app in
                                        Image(nsImage: app.icon)
                                            .resizable()
                                            .frame(
                                                width: offset == 0 ? 44 : 32,
                                                height: offset == 0 ? 44 : 32
                                            )
                                            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                                            .zIndex(Double(-offset))
                                    }
                                }
                            }
                            .frame(height: 48)
                            .opacity(selected ? 1 : 0.65)
                            .saturation(selected ? 1 : 0.7)
                            nameLabel(workspace.name, selected: selected)
                        }
                        .frame(width: 96)
                        .padding(.vertical, 10)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.white.opacity(0.12))
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - C: alt-tab, one badge on the corner

    /// Thumbnail untouched except a single leading-app icon riding the
    /// bottom-right corner, half outside the frame.
    struct AltTabVariant: View {
        var body: some View {
            Panel {
                HStack(spacing: 16) {
                    ForEach(Array(workspaces.enumerated()), id: \.offset) { index, workspace in
                        let selected = index == selectedIndex
                        VStack(spacing: 8) {
                            thumb(workspace, selected: selected)
                                .overlay(alignment: .bottomTrailing) {
                                    if let icon = workspace.apps.first?.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 24, height: 24)
                                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                                            .offset(x: 6, y: 6)
                                            .opacity(selected ? 1 : 0.75)
                                            .saturation(selected ? 1 : 0.75)
                                    }
                                }
                            nameLabel(workspace.name, selected: selected)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.white.opacity(0.12))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - D: scrim, icons inside the picture

    /// Apple-TV-style: a dark gradient scrim across the thumbnail's bottom
    /// edge carries the app icons, so they live inside the picture without
    /// fighting it; the name stays below.
    struct ScrimVariant: View {
        var body: some View {
            Panel {
                HStack(spacing: 14) {
                    ForEach(Array(workspaces.enumerated()), id: \.offset) { index, workspace in
                        let selected = index == selectedIndex
                        VStack(spacing: 7) {
                            ZStack(alignment: .bottomLeading) {
                                thumb(workspace, selected: selected, size: CGSize(width: 110, height: 68.75))
                                LinearGradient(
                                    colors: [.black.opacity(0.65), .black.opacity(0)],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                                .frame(height: 30)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                HStack(spacing: 4) {
                                    ForEach(Array(workspace.apps.prefix(4).enumerated()), id: \.offset) { _, app in
                                        Image(nsImage: app.icon)
                                            .resizable()
                                            .frame(width: 15, height: 15)
                                    }
                                }
                                .padding(6)
                                .opacity(selected ? 1 : 0.8)
                            }
                            .frame(width: 110, height: 68.75)
                            nameLabel(workspace.name, selected: selected)
                        }
                        .padding(6)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.white.opacity(0.12))
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

}
