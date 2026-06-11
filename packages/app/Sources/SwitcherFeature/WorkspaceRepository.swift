import AeroKitCore
import Foundation

public final class WorkspaceRepository: @unchecked Sendable {
    private let client: AeroSpaceClient
    private let orderIndex: [String: Int]

    public init(client: AeroSpaceClient, order: [String]) {
        self.client = client
        orderIndex = Dictionary(order.enumerated().map { ($1, $0) }) { first, _ in first }
    }

    public func load() throws -> [Workspace] {
        let listings = try client.listWorkspaces()
        let windows = try client.listWindows()
        let windowsByWorkspace = Dictionary(grouping: windows, by: \.workspace)

        return listings
            .map { listing in
                let workspaceWindows = windowsByWorkspace[listing.name] ?? []
                return Workspace(
                    name: listing.name,
                    apps: uniqueApps(from: workspaceWindows),
                    isFocused: listing.isFocused,
                    isEmpty: workspaceWindows.isEmpty
                )
            }
            .sorted { lhs, rhs in
                compareWorkspaceNames(lhs.name, rhs.name)
            }
    }

    public func switchToWorkspace(_ name: String) throws {
        try client.switchToWorkspace(name)
    }

    private func uniqueApps(from windows: [WorkspaceWindow]) -> [WorkspaceApp] {
        var seen = Set<String>()
        var apps: [WorkspaceApp] = []

        for window in windows {
            let key = window.bundleIdentifier.isEmpty ? window.appName : window.bundleIdentifier
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            apps.append(WorkspaceApp(name: window.appName, bundleIdentifier: window.bundleIdentifier))
        }

        return apps
    }

    private func compareWorkspaceNames(_ lhs: String, _ rhs: String) -> Bool {
        switch (orderIndex[lhs], orderIndex[rhs]) {
        case let (.some(left), .some(right)):
            left < right
        case (.some, .none):
            true
        case (.none, .some):
            false
        case (.none, .none):
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }
}
