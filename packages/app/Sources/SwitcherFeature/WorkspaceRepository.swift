import AeroKitCore
import Foundation

public final class WorkspaceRepository: Sendable {
    private let client: AeroSpaceClient

    public init(client: AeroSpaceClient) {
        self.client = client
    }

    /// `order` is the user's priority list, captured at call time because
    /// the settings window can change it while loads run in the background.
    public func load(order: [String]) throws -> [Workspace] {
        let listings = try client.listWorkspaces()
        let windows = try client.listWindows()
        let windowsByWorkspace = Dictionary(grouping: windows, by: \.workspace)
        let comparator = WorkspaceOrdering.comparator(priority: order)

        return listings
            .map { listing in
                let workspaceWindows = windowsByWorkspace[listing.name] ?? []
                return Workspace(
                    name: listing.name,
                    apps: WorkspaceApp.uniqueApps(from: workspaceWindows),
                    isFocused: listing.isFocused,
                    isEmpty: workspaceWindows.isEmpty
                )
            }
            .sorted { lhs, rhs in
                comparator(lhs.name, rhs.name)
            }
    }

    public func switchToWorkspace(_ name: String) throws {
        try client.switchToWorkspace(name)
    }
}
