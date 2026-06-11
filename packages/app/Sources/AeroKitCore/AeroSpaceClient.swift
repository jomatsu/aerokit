import CoreGraphics
import Foundation

/// The focused workspace's windows plus the AppKit screen hosting them.
public struct WorkspaceSnapshot: Equatable, Sendable {
    public var windows: [ExposeWindow]
    /// 1-based index into `NSScreen.screens`, straight from
    /// `%{monitor-appkit-nsscreen-screens-id}`; nil when AeroSpace returned
    /// nothing parseable.
    public var screenNumber: Int?

    public init(windows: [ExposeWindow], screenNumber: Int? = nil) {
        self.windows = windows
        self.screenNumber = screenNumber
    }
}

public final class AeroSpaceClient: Sendable {
    private let executablePath: String
    private let runner: any CommandRunning
    private let separator = "\u{1f}"

    public init(executablePath: String, runner: any CommandRunning = ProcessRunner()) {
        self.executablePath = executablePath
        self.runner = runner
    }

    /// Locates the aerospace CLI across common install locations, falling
    /// back to the Homebrew path GUI apps can't always find via PATH.
    public static func detectExecutablePath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = [
            "/opt/homebrew/bin/aerospace",
            "/usr/local/bin/aerospace",
            "\(home)/.local/bin/aerospace"
        ]

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path
                .split(separator: ":")
                .map { "\($0)/aerospace" }
        }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "/opt/homebrew/bin/aerospace"
    }

    // MARK: - Workspaces

    public func listWorkspaces() throws -> [(name: String, isFocused: Bool)] {
        let format = ["%{workspace}", "%{workspace-is-focused}"].joined(separator: separator)

        return try run(["list-workspaces", "--all", "--format", format])
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let fields = line.split(separator: Character(separator), omittingEmptySubsequences: false)
                guard fields.count >= 2, !fields[0].isEmpty else {
                    return nil
                }
                return (name: String(fields[0]), isFocused: fields[1] == "true")
            }
    }

    public func switchToWorkspace(_ name: String) throws {
        _ = try run(["workspace", name])
    }

    // MARK: - Windows (all workspaces)

    public func listWindows() throws -> [WorkspaceWindow] {
        let format = [
            "%{window-id}",
            "%{app-bundle-id}",
            "%{app-name}",
            "%{workspace}",
            "%{window-title}",
            "%{window-layout}",
            "%{window-parent-container-layout}",
            "%{workspace-root-container-layout}"
        ].joined(separator: separator)

        return try run(["list-windows", "--all", "--format", format])
            .split(whereSeparator: \.isNewline)
            .compactMap(parseWindowLine)
    }

    // MARK: - Windows (focused workspace)

    public func focusedWorkspaceWindows() throws -> WorkspaceSnapshot {
        let format = [
            "%{window-id}",
            "%{app-bundle-id}",
            "%{app-name}",
            "%{window-title}",
            "%{monitor-appkit-nsscreen-screens-id}"
        ].joined(separator: separator)

        var snapshot = WorkspaceSnapshot(windows: [])
        let output = try run(["list-windows", "--workspace", "focused", "--format", format])
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: Character(separator), omittingEmptySubsequences: false)
            guard fields.count >= 5, let id = CGWindowID(fields[0]) else {
                continue
            }
            snapshot.windows.append(ExposeWindow(
                id: id,
                bundleIdentifier: String(fields[1]),
                appName: String(fields[2]),
                title: String(fields[3])
            ))
            snapshot.screenNumber = snapshot.screenNumber ?? Int(fields[4])
        }
        return snapshot
    }

    /// nil when no window has focus (AeroSpace exits non-zero) or the output
    /// is unparseable; the caller treats both the same way.
    public func focusedWindowID() -> CGWindowID? {
        guard let output = try? run(["list-windows", "--focused", "--format", "%{window-id}"]) else {
            return nil
        }
        return CGWindowID(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func focusWindow(id: CGWindowID) throws {
        _ = try run(["focus", "--window-id", String(id)])
    }

    public func focusedWorkspaceName() throws -> String? {
        let name = try run(["list-workspaces", "--focused", "--format", "%{workspace}"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Moves a window to a workspace and focuses it. AeroSpace parks other
    /// workspaces' windows off-screen, so re-showing one of our own windows
    /// (e.g. settings) needs an explicit summon or it stays invisible on the
    /// workspace it was created on. The caller supplies the target because
    /// the act of showing the window already flips AeroSpace's focused
    /// workspace to wherever the window currently lives.
    public func summonWindow(id: CGWindowID, toWorkspace workspace: String) throws {
        _ = try run([
            "move-node-to-workspace", "--focus-follows-window", "--window-id", String(id), workspace
        ])
    }

    // MARK: - Parsing

    private func run(_ arguments: [String]) throws -> String {
        try runner.run(executablePath, arguments: arguments).standardOutput
    }

    private func parseWindowLine(_ line: Substring) -> WorkspaceWindow? {
        let fields = line.split(separator: Character(separator), omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 5 else {
            return nil
        }
        return WorkspaceWindow(
            id: fields[0],
            bundleIdentifier: fields[1],
            appName: fields[2],
            workspace: fields[3],
            title: fields[4],
            layout: fields.count > 5 ? fields[5] : "",
            parentContainerLayout: fields.count > 6 ? fields[6] : "",
            workspaceRootContainerLayout: fields.count > 7 ? fields[7] : ""
        )
    }
}
