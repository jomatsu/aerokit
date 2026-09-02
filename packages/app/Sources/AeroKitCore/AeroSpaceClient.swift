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

/// Identity of the focused window, enough to find its app's other windows.
public struct FocusedWindow: Equatable, Sendable {
    public var id: CGWindowID
    public var bundleIdentifier: String
    public var pid: Int32?
    /// 1-based index into `NSScreen.screens` for the window's monitor.
    public var screenNumber: Int?

    public init(id: CGWindowID, bundleIdentifier: String, pid: Int32? = nil, screenNumber: Int? = nil) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.pid = pid
        self.screenNumber = screenNumber
    }
}

public final class AeroSpaceClient: Sendable {
    private let executablePath: String
    private let runner: any CommandRunning
    private let separator = "\u{1f}"

    /// The default runner talks to the AeroSpace server over its unix
    /// socket and only spawns `executablePath` as a fallback, so the
    /// common path never pays for a process launch.
    public init(executablePath: String, runner: any CommandRunning = AeroSpaceSocketRunner()) {
        self.executablePath = executablePath
        self.runner = runner
    }

    /// Locates the aerospace CLI across common install locations, including
    /// the Homebrew paths GUI apps can't always find via PATH. nil when no
    /// aerospace binary exists at any known location.
    public static func detectInstalledExecutablePath() -> String? {
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
    }

    /// The install path when present, else the Homebrew default so callers
    /// always have a concrete path to spawn.
    public static func detectExecutablePath() -> String {
        detectInstalledExecutablePath() ?? "/opt/homebrew/bin/aerospace"
    }

    // MARK: - Workspaces

    public func listWorkspaces() throws -> [(name: String, isFocused: Bool)] {
        try workspaceList(["list-workspaces", "--all"])
    }

    /// Workspaces of the focused monitor in AeroSpace's order. With
    /// `includeEmpty: false` the focused workspace itself can be missing
    /// from the result when it has no windows.
    public func workspacesOnFocusedMonitor(includeEmpty: Bool) throws -> [(name: String, isFocused: Bool)] {
        var arguments = ["list-workspaces", "--monitor", "focused"]
        if !includeEmpty {
            arguments += ["--empty", "no"]
        }
        return try workspaceList(arguments)
    }

    private func workspaceList(_ arguments: [String]) throws -> [(name: String, isFocused: Bool)] {
        try runFields(arguments, format: ["%{workspace}", "%{workspace-is-focused}"])
            .compactMap { fields in
                guard fields.count >= 2, !fields[0].isEmpty else {
                    return nil
                }
                return (name: fields[0], isFocused: fields[1] == "true")
            }
    }

    public func switchToWorkspace(_ name: String) throws {
        _ = try run(["workspace", name])
    }

    /// Applies an edited config without waiting for an AeroSpace restart.
    public func reloadConfig() throws {
        _ = try run(["reload-config"])
    }

    // MARK: - Key bindings

    /// Workspace name → key combo (e.g. "alt-1") from the config's main-mode
    /// bindings. A binding counts when any of its commands is a `workspace`
    /// or `summon-workspace` switch naming a workspace; several combos for
    /// one workspace keep the one with the fewest modifiers. Unparseable
    /// output degrades to [:].
    public func workspaceKeyBindings() throws -> [String: String] {
        let output = try run(["config", "--get", "mode.main.binding", "--json"])
        guard let data = output.data(using: .utf8),
              let bindings = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }

        var combos: [String: String] = [:]
        for (combo, command) in bindings {
            let commands = command as? [String] ?? (command as? String).map { [$0] } ?? []
            for workspace in commands.compactMap(Self.workspaceSwitchTarget) {
                if let existing = combos[workspace], Self.comboRank(existing) <= Self.comboRank(combo) {
                    continue
                }
                combos[workspace] = combo
            }
        }
        return combos
    }

    /// "workspace --auto-back-and-forth 3" → "3", "summon-workspace web" →
    /// "web"; relative switches ("workspace prev") and other commands
    /// (including `workspace-back-and-forth`) are nil.
    private static func workspaceSwitchTarget(_ command: String) -> String? {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = tokens.first, first == "workspace" || first == "summon-workspace",
              let target = tokens.dropFirst().last(where: { !$0.hasPrefix("--") }),
              !["prev", "next"].contains(target)
        else {
            return nil
        }
        return target
    }

    private static func comboRank(_ combo: String) -> (Int, String) {
        (combo.count { $0 == "-" }, combo)
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
        ]

        return try runFields(["list-windows", "--all"], format: format)
            .compactMap(parseWindowLine)
    }

    // MARK: - Windows (focused workspace)

    public func focusedWorkspaceWindows() throws -> WorkspaceSnapshot {
        try windowSnapshot(listArguments: ["list-windows", "--workspace", "focused"])
    }

    // MARK: - Windows (focused app)

    /// All windows of one app across every workspace; the app exposé's data
    /// source. Filters by bundle id when present (one app can span helper
    /// processes), by pid otherwise (some windows report no bundle id).
    /// `--app-bundle-id`/`--pid` only combine with `--monitor`, so the "all
    /// workspaces" part is spelled `--monitor all`.
    public func appWindows(bundleIdentifier: String, pid: Int32?) throws -> WorkspaceSnapshot {
        var arguments = ["list-windows", "--monitor", "all"]
        if !bundleIdentifier.isEmpty {
            arguments += ["--app-bundle-id", bundleIdentifier]
        } else if let pid {
            arguments += ["--pid", String(pid)]
        } else {
            return WorkspaceSnapshot(windows: [])
        }
        return try windowSnapshot(listArguments: arguments)
    }

    /// nil when no window has focus (AeroSpace exits non-zero) or the output
    /// is unparseable; the caller treats both the same way.
    public func focusedWindow() -> FocusedWindow? {
        let format = [
            "%{window-id}",
            "%{app-bundle-id}",
            "%{app-pid}",
            "%{monitor-appkit-nsscreen-screens-id}"
        ]

        guard let fields = (try? runFields(["list-windows", "--focused"], format: format))?.first,
              fields.count >= 4, let id = CGWindowID(fields[0])
        else {
            return nil
        }
        return FocusedWindow(
            id: id,
            bundleIdentifier: fields[1],
            pid: Int32(fields[2]),
            screenNumber: Int(fields[3])
        )
    }

    private func windowSnapshot(listArguments: [String]) throws -> WorkspaceSnapshot {
        let format = [
            "%{window-id}",
            "%{app-bundle-id}",
            "%{app-name}",
            "%{window-title}",
            "%{monitor-appkit-nsscreen-screens-id}",
            "%{workspace}"
        ]

        var snapshot = WorkspaceSnapshot(windows: [])
        for fields in try runFields(listArguments, format: format) {
            guard fields.count >= 5, let id = CGWindowID(fields[0]) else {
                continue
            }
            snapshot.windows.append(ExposeWindow(
                id: id,
                bundleIdentifier: fields[1],
                appName: fields[2],
                title: fields[3],
                workspace: fields.count > 5 ? fields[5] : ""
            ))
            snapshot.screenNumber = snapshot.screenNumber ?? Int(fields[4])
        }
        return snapshot
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

    /// Moves a window to a workspace without following it — unlike
    /// `summonWindow`, deliberately no `--focus-follows-window`: the exposé
    /// overlay stays up after the move and focus must not leave it.
    public func moveWindow(id: CGWindowID, toWorkspace workspace: String) throws {
        _ = try run(["move-node-to-workspace", "--window-id", String(id), workspace])
    }

    public func closeWindow(id: CGWindowID) throws {
        _ = try run(["close", "--window-id", String(id)])
    }

    // MARK: - Parsing

    private func run(_ arguments: [String]) throws -> String {
        try runner.run(executablePath, arguments: arguments).standardOutput
    }

    /// Runs a list command with `--format` built from `fields` and splits the
    /// output back into one column array per line. Empty columns are kept so
    /// positions stay stable; lines can still come back short (older
    /// aerospace builds emit fewer columns), so callers guard their minimums.
    private func runFields(_ arguments: [String], format: [String]) throws -> [[String]] {
        try run(arguments + ["--format", format.joined(separator: separator)])
            .split(whereSeparator: \.isNewline)
            .map { line in
                line.split(separator: Character(separator), omittingEmptySubsequences: false).map(String.init)
            }
    }

    private func parseWindowLine(_ fields: [String]) -> WorkspaceWindow? {
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

/// Settings-pane diagnosis of the AeroSpace side of the world.
public enum AeroSpaceHealth: Equatable, Sendable {
    /// The server answered a command.
    case running
    /// The CLI binary exists but no command succeeded — the server is
    /// most likely not running.
    case installedNotRunning
    case notInstalled
}

public extension AeroSpaceClient {
    /// Blocking round trip (fast socket path, CLI fallback); call off
    /// the main actor.
    func checkHealth() -> AeroSpaceHealth {
        if (try? listWorkspaces()) != nil {
            return .running
        }
        return Self.detectInstalledExecutablePath() == nil ? .notInstalled : .installedNotRunning
    }
}
