import Foundation

public final class AeroSpaceClient: @unchecked Sendable {
    private let executablePath: String
    private let runner: any CommandRunning
    private let separator = "\u{1f}"

    public init(executablePath: String, runner: any CommandRunning = ProcessRunner()) {
        self.executablePath = executablePath
        self.runner = runner
    }

    public func listWorkspaceNames() throws -> [String] {
        try run(["list-workspaces", "--all"])
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    public func focusedWorkspaceName() throws -> String {
        try run(["list-workspaces", "--focused"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func listWindows() throws -> [WorkspaceWindow] {
        let format = [
            "%{window-id}",
            "%{app-bundle-id}",
            "%{app-name}",
            "%{workspace}",
            "%{window-title}"
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
            title: fields[4]
        )
    }
}
