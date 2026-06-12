import AppKit

public final class AppIconResolver: @unchecked Sendable {
    private let workspace: NSWorkspace
    /// Misses are cached too: unresolvable apps would otherwise rescan
    /// runningApplications and probe the filesystem on every rebuild.
    /// Guarded by `lock` — resolvers are shared with detached tasks.
    private var cache: [String: NSImage?] = [:]
    private let lock = NSLock()

    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    public func icon(forBundleIdentifier bundleIdentifier: String, name: String) -> NSImage? {
        icon(for: WorkspaceApp(name: name, bundleIdentifier: bundleIdentifier))
    }

    public func icon(for app: WorkspaceApp) -> NSImage? {
        let cacheKey = app.bundleIdentifier ?? app.name
        lock.lock()
        if let cached = cache[cacheKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved = iconByBundleIdentifier(app.bundleIdentifier)
            ?? iconByRunningApplicationName(app.name)
            ?? iconByApplicationPath(app.name)

        // NSRunningApplication.icon can hand out a shared instance; resize
        // a copy so other holders keep their size.
        let icon = resolved?.copy() as? NSImage
        icon?.size = NSSize(width: 64, height: 64)
        lock.lock()
        cache[cacheKey] = icon
        lock.unlock()
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
