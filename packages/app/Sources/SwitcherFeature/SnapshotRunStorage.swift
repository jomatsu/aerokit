import AeroKitCore
import Darwin
import Foundation

/// Filesystem boundary for one snapshot refresh: the temporary run directory,
/// manifest.tsv, the `current` pointer, and leftover-run cleanup.
struct SnapshotRunStorage: Sendable {
    var now: @Sendable () -> Date
    var uniqueSuffix: @Sendable () -> String
    var writeText: @Sendable (String, URL) throws -> Void
    var renamePath: @Sendable (String, String) -> Int32

    init(
        now: @escaping @Sendable () -> Date = { Date() },
        uniqueSuffix: @escaping @Sendable () -> String = { String(UUID().uuidString.prefix(6)) },
        writeText: @escaping @Sendable (String, URL) throws -> Void = { content, url in
            try content.write(to: url, atomically: true, encoding: .utf8)
        },
        renamePath: @escaping @Sendable (String, String) -> Int32 = { Darwin.rename($0, $1) }
    ) {
        self.now = now
        self.uniqueSuffix = uniqueSuffix
        self.writeText = writeText
        self.renamePath = renamePath
    }

    private var fileManager: FileManager {
        .default
    }

    private static let runIDFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let manifestDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    func resolveCurrentDirectory(in rootURL: URL) -> URL? {
        let current = rootURL.appendingPathComponent("current", isDirectory: true)
        let resolved = current.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return resolved
    }

    func prepareRun(in rootURL: URL, workspaces: [String]) throws -> SnapshotRunDirectories {
        let runID = Self.runIDFormatter.string(from: now())
        let temporaryDirectory = rootURL.appendingPathComponent(
            ".next-\(runID)-\(uniqueSuffix())",
            isDirectory: true
        )
        let finalDirectory = rootURL.appendingPathComponent(".current-\(runID)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        } catch {
            throw SnapshotEngineError.outputDirectoryUnavailable(temporaryDirectory.path)
        }

        for workspace in workspaces {
            let directory = temporaryDirectory.appendingPathComponent(
                WorkspaceName.captureDirectoryName(workspace),
                isDirectory: true
            )
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return SnapshotRunDirectories(temporaryDirectory: temporaryDirectory, finalDirectory: finalDirectory)
    }

    func writeManifest(
        rows: [SnapshotManifestRow],
        in directory: URL,
        finalDirectory: URL
    ) throws {
        let header = [
            "timestamp", "workspace", "window_id", "app_id", "app_name", "window_title",
            "window_layout", "window_parent_container_layout", "workspace_root_container_layout",
            "file", "status"
        ].joined(separator: "\t")

        let timestamp = Self.manifestDateFormatter.string(from: now())
        let body = rows.map { row in
            [
                timestamp,
                sanitizeField(row.window.workspace),
                row.window.id,
                sanitizeField(row.window.bundleIdentifier),
                sanitizeField(row.window.appName),
                sanitizeField(row.window.title),
                row.window.layout,
                row.window.parentContainerLayout,
                row.window.workspaceRootContainerLayout,
                finalDirectory.appendingPathComponent(row.relativePath).path,
                row.status.rawValue
            ].joined(separator: "\t")
        }

        let manifest = ([header] + body).joined(separator: "\n") + "\n"
        try writeText(manifest, directory.appendingPathComponent("manifest.tsv"))
    }

    func promote(temporaryDirectory: URL, to finalDirectory: URL, in rootURL: URL) throws {
        if fileManager.fileExists(atPath: finalDirectory.path) {
            try? fileManager.removeItem(at: finalDirectory)
        }
        try fileManager.moveItem(at: temporaryDirectory, to: finalDirectory)

        let currentLink = rootURL.appendingPathComponent("current")
        let currentType = (try? fileManager.attributesOfItem(atPath: currentLink.path))?[.type] as? FileAttributeType
        if let currentType, currentType != .typeSymbolicLink {
            // A real directory from an older layout: move it aside so the
            // symlink can take its place, then delete it.
            let retired = rootURL.appendingPathComponent(".previous-current-\(uniqueSuffix())")
            try? fileManager.moveItem(at: currentLink, to: retired)
            try? fileManager.removeItem(at: retired)
        }

        // rename(2) replaces the existing symlink atomically, so `current`
        // never dangles even if the app dies mid-promotion.
        let temporaryLink = rootURL.appendingPathComponent(".current-link-\(uniqueSuffix())")
        try fileManager.createSymbolicLink(
            atPath: temporaryLink.path,
            withDestinationPath: finalDirectory.lastPathComponent
        )
        guard renamePath(temporaryLink.path, currentLink.path) == 0 else {
            try? fileManager.removeItem(at: temporaryLink)
            throw SnapshotEngineError.outputDirectoryUnavailable(currentLink.path)
        }

        cleanupOldRuns(in: rootURL, keeping: finalDirectory.lastPathComponent)
    }

    func cleanupOldRuns(in rootURL: URL, keeping keptName: String) {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: rootURL.path) else {
            return
        }

        for entry in entries where entry != keptName {
            let isEngineRun = entry.hasPrefix(".current-")
                || entry.hasPrefix(".next-")
                || entry.hasPrefix(".previous-current-")
            // Timestamped directories come from the legacy script's --history
            // mode; require its manifest so user-created folders that happen
            // to match the pattern survive.
            let isLegacyRun = entry.range(of: #"^20\d{6}-\d{6}$"#, options: .regularExpression) != nil
                && fileManager.fileExists(
                    atPath: rootURL.appendingPathComponent("\(entry)/manifest.tsv").path
                )
            if isEngineRun || isLegacyRun {
                try? fileManager.removeItem(at: rootURL.appendingPathComponent(entry))
            }
        }
    }

    private func sanitizeField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

struct SnapshotRunDirectories: Sendable {
    var temporaryDirectory: URL
    var finalDirectory: URL
}

struct SnapshotManifestRow: Sendable {
    var window: WorkspaceWindow
    var relativePath: String
    var status: SnapshotStatus
}
