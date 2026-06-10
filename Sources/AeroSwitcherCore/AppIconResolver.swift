import AppKit

public final class AppIconResolver: @unchecked Sendable {
    private let workspace: NSWorkspace
    private var cache: [String: NSImage] = [:]

    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    public func icon(for app: WorkspaceApp) -> NSImage? {
        let cacheKey = app.bundleIdentifier ?? app.name
        if let cached = cache[cacheKey] {
            return cached
        }

        let icon = iconByBundleIdentifier(app.bundleIdentifier)
            ?? iconByRunningApplicationName(app.name)
            ?? iconByApplicationPath(app.name)

        if let icon {
            icon.size = NSSize(width: 64, height: 64)
            cache[cacheKey] = icon
        }
        return icon
    }

    private func iconByBundleIdentifier(_ bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            return nil
        }
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return workspace.icon(forFile: url.path)
    }

    private func iconByRunningApplicationName(_ appName: String) -> NSImage? {
        workspace.runningApplications
            .first { $0.localizedName == appName || $0.bundleURL?.deletingPathExtension().lastPathComponent == appName
            }?
            .icon
    }

    private func iconByApplicationPath(_ appName: String) -> NSImage? {
        let candidates = [
            "/Applications/\(appName).app",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/\(appName).app",
            "/System/Applications/\(appName).app",
            "/System/Applications/Utilities/\(appName).app"
        ]

        return candidates
            .first { FileManager.default.fileExists(atPath: $0) }
            .map(workspace.icon(forFile:))
    }
}
