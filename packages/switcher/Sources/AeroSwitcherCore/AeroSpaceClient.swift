import Foundation

public final class AeroSpaceClient: @unchecked Sendable {
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

    public func switchToWorkspace(_ name: String) throws {
        _ = try runner.run(executablePath, arguments: ["workspace", name])
    }

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
