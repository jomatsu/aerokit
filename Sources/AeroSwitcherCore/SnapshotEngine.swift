import CoreGraphics
import Foundation
import ScreenCaptureKit

public enum SnapshotEngineError: Error, CustomStringConvertible {
    case noWorkspaces
    case nothingCaptured
    case outputDirectoryUnavailable(String)

    public var description: String {
        switch self {
        case .noWorkspaces:
            "No workspaces configured for snapshots"
        case .nothingCaptured:
            "No windows captured"
        case let .outputDirectoryUnavailable(path):
            "Could not prepare snapshot directory: \(path)"
        }
    }
}

/// In-app replacement for aerospace-workspace-snapshot.sh
/// (`--configured --current --windows --compose`): captures every window of
/// the configured workspaces through ScreenCaptureKit, composes one overview
/// PNG per workspace, writes the manifest, and atomically promotes the run
/// to `<root>/current`.
public final class SnapshotEngine: Sendable {
    private struct WindowResult: @unchecked Sendable {
        var window: WorkspaceWindow
        var status: SnapshotStatus
        var composeImage: CGImage?
    }

    /// SCWindow is not Sendable, but these are immutable snapshots that the
    /// capture tasks only read.
    private struct ShareableWindows: @unchecked Sendable {
        let byID: [CGWindowID: SCWindow]
    }

    private let configuration: SwitcherConfiguration
    private let client: AeroSpaceClient
    private let capturer: WindowImageCapturer
    private var fileManager: FileManager {
        .default
    }

    private let maxConcurrentCaptures = 4

    public init(configuration: SwitcherConfiguration, client: AeroSpaceClient) {
        self.configuration = configuration
        self.client = client
        capturer = WindowImageCapturer()
    }

    /// Runs a full snapshot refresh and returns the promoted `current` directory.
    /// `onProgress` reports (completedWindows, totalWindows) as captures finish.
    public func refresh(onProgress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> URL {
        let workspaces = configuration.workspaceOrder
        guard !workspaces.isEmpty else {
            throw SnapshotEngineError.noWorkspaces
        }

        let selectedWorkspaces = Set(workspaces)
        let windows = try await listWindows()
            .filter { selectedWorkspaces.contains($0.workspace) }

        let rootURL = URL(fileURLWithPath: configuration.snapshotRootPath, isDirectory: true)
        let runID = Self.runIDFormatter.string(from: Date())
        let previousDirectory = resolveCurrentDirectory(in: rootURL)
        let previousWorkspaces = workspacesInManifest(at: previousDirectory)

        let temporaryDirectory = rootURL.appendingPathComponent(
            ".next-\(runID)-\(UUID().uuidString.prefix(6))",
            isDirectory: true
        )
        let finalDirectory = rootURL.appendingPathComponent(".current-\(runID)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        } catch {
            throw SnapshotEngineError.outputDirectoryUnavailable(temporaryDirectory.path)
        }

        var promoted = false
        defer {
            if !promoted {
                try? fileManager.removeItem(at: temporaryDirectory)
            }
        }

        for workspace in workspaces {
            let directory = temporaryDirectory.appendingPathComponent(
                WorkspaceName.captureDirectoryName(workspace),
                isDirectory: true
            )
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let results = await captureWindows(
            windows,
            into: temporaryDirectory,
            previousDirectory: previousDirectory,
            onProgress: onProgress
        )

        let usableCount = results.filter(\.status.isUsable).count
        if !windows.isEmpty, usableCount == 0 {
            throw SnapshotEngineError.nothingCaptured
        }

        composeOverviews(
            workspaces: workspaces,
            results: results,
            outputDirectory: temporaryDirectory,
            previousDirectory: previousDirectory,
            previousWorkspaces: previousWorkspaces
        )

        try writeManifest(results: results, in: temporaryDirectory, finalDirectory: finalDirectory)
        try promote(temporaryDirectory: temporaryDirectory, to: finalDirectory, in: rootURL)
        promoted = true

        return rootURL.appendingPathComponent("current", isDirectory: true)
    }

    // MARK: - Capture

    private func captureWindows(
        _ windows: [WorkspaceWindow],
        into outputDirectory: URL,
        previousDirectory: URL?,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async -> [WindowResult] {
        let shareable = await ShareableWindows(byID: (try? capturer.shareableWindows()) ?? [:])
        let displayScale = await capturer.maximumDisplayScale()

        onProgress?(0, windows.count)
        var completed = 0
        var results = [WindowResult?](repeating: nil, count: windows.count)
        await withTaskGroup(of: (Int, WindowResult).self) { group in
            var nextIndex = 0

            func addNext() {
                guard nextIndex < windows.count else {
                    return
                }
                let index = nextIndex
                let window = windows[index]
                nextIndex += 1
                group.addTask {
                    let result = await self.captureWindow(
                        window,
                        shareable: shareable,
                        displayScale: displayScale,
                        outputDirectory: outputDirectory,
                        previousDirectory: previousDirectory
                    )
                    return (index, result)
                }
            }

            for _ in 0 ..< maxConcurrentCaptures {
                addNext()
            }
            while let (index, result) = await group.next() {
                results[index] = result
                completed += 1
                onProgress?(completed, windows.count)
                addNext()
            }
        }

        return results.compactMap(\.self)
    }

    private func captureWindow(
        _ window: WorkspaceWindow,
        shareable: ShareableWindows,
        displayScale: CGFloat,
        outputDirectory: URL,
        previousDirectory: URL?
    ) async -> WindowResult {
        let fileURL = outputDirectory.appendingPathComponent(relativeCapturePath(for: window))
        let previousURL = previousDirectory?.appendingPathComponent(relativeCapturePath(for: window))

        func reuseOrFail(_ status: SnapshotStatus) -> WindowResult {
            reusePrevious(window: window, previousURL: previousURL, fileURL: fileURL)
                ?? WindowResult(window: window, status: status, composeImage: nil)
        }

        guard let windowID = CGWindowID(window.id), let scWindow = shareable.byID[windowID] else {
            return reuseOrFail(.failed)
        }

        guard let image = try? await capturer.captureImage(of: scWindow, scale: displayScale) else {
            return reuseOrFail(.failed)
        }

        if WorkspaceComposer.isBlackish(image) {
            return reuseOrFail(.failedBlack)
        }

        guard WorkspaceComposer.writePNG(image, to: fileURL) else {
            return WindowResult(window: window, status: .failed, composeImage: nil)
        }

        return WindowResult(window: window, status: .captured, composeImage: downsampled(image))
    }

    private func reusePrevious(window: WorkspaceWindow, previousURL: URL?, fileURL: URL) -> WindowResult? {
        guard let previousURL,
              fileManager.fileExists(atPath: previousURL.path),
              let image = WorkspaceComposer.loadImage(at: previousURL),
              !WorkspaceComposer.isBlackish(image)
        else {
            return nil
        }

        try? fileManager.copyItem(at: previousURL, to: fileURL)
        return WindowResult(window: window, status: .cached, composeImage: downsampled(image))
    }

    private func relativeCapturePath(for window: WorkspaceWindow) -> String {
        let directory = WorkspaceName.captureDirectoryName(window.workspace)
        let app = WorkspaceName.sanitizedFileStem(window.appName.isEmpty ? "window" : window.appName)
        return "\(directory)/window-\(window.id)-\(app).png"
    }

    /// Compose cells are at most ~800pt wide, so keep a small copy for
    /// composition and let the full-resolution capture live on disk only.
    private func downsampled(_ image: CGImage, maxDimension: CGFloat = 800) -> CGImage {
        let size = CGSize(width: image.width, height: image.height)
        let scale = min(1, maxDimension / max(size.width, size.height))
        guard scale < 1,
              let context = WorkspaceComposer.makeContext(
                  width: Int((size.width * scale).rounded()),
                  height: Int((size.height * scale).rounded())
              )
        else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        return context.makeImage() ?? image
    }

    // MARK: - Compose

    private func composeOverviews(
        workspaces: [String],
        results: [WindowResult],
        outputDirectory: URL,
        previousDirectory: URL?,
        previousWorkspaces: Set<String>
    ) {
        let resultsByWorkspace = Dictionary(grouping: results, by: \.window.workspace)

        for workspace in workspaces {
            let fileName = WorkspaceName.overviewFileName(workspace)
            let outputURL = outputDirectory.appendingPathComponent(fileName)
            let workspaceResults = resultsByWorkspace[workspace] ?? []
            let images = workspaceResults.compactMap { $0.status.isUsable ? $0.composeImage : nil }

            if images.isEmpty {
                let previousOverview = previousDirectory?.appendingPathComponent(fileName)
                let hadNoWindowsBefore = !previousWorkspaces.contains(workspace)
                if hadNoWindowsBefore, let previousOverview, fileManager.fileExists(atPath: previousOverview.path) {
                    try? fileManager.copyItem(at: previousOverview, to: outputURL)
                    continue
                }
                if let empty = WorkspaceComposer.emptyOverview(canvasSize: configuration.snapshotComposeSize) {
                    _ = WorkspaceComposer.writePNG(empty, to: outputURL)
                }
                continue
            }

            let rootLayout = workspaceResults.first?.window.workspaceRootContainerLayout ?? ""
            if let overview = WorkspaceComposer.composeOverview(
                images: images,
                rootLayout: rootLayout,
                canvasSize: configuration.snapshotComposeSize,
                gap: configuration.snapshotComposeGap
            ) {
                _ = WorkspaceComposer.writePNG(overview, to: outputURL)
            }
        }
    }

    // MARK: - Manifest

    private func writeManifest(results: [WindowResult], in directory: URL, finalDirectory: URL) throws {
        let header = [
            "timestamp", "workspace", "window_id", "app_id", "app_name", "window_title",
            "window_layout", "window_parent_container_layout", "workspace_root_container_layout",
            "file", "status"
        ].joined(separator: "\t")

        let timestamp = Self.manifestDateFormatter.string(from: Date())
        let rows = results.map { result in
            [
                timestamp,
                sanitizeField(result.window.workspace),
                result.window.id,
                sanitizeField(result.window.bundleIdentifier),
                sanitizeField(result.window.appName),
                sanitizeField(result.window.title),
                result.window.layout,
                result.window.parentContainerLayout,
                result.window.workspaceRootContainerLayout,
                finalDirectory.appendingPathComponent(relativeCapturePath(for: result.window)).path,
                result.status.rawValue
            ].joined(separator: "\t")
        }

        let manifest = ([header] + rows).joined(separator: "\n") + "\n"
        try manifest.write(to: directory.appendingPathComponent("manifest.tsv"), atomically: true, encoding: .utf8)
    }

    private func sanitizeField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func workspacesInManifest(at directory: URL?) -> Set<String> {
        guard let directory,
              let contents = try? String(
                  contentsOf: directory.appendingPathComponent("manifest.tsv"),
                  encoding: .utf8
              )
        else {
            return []
        }

        let workspaces = contents
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line -> String? in
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                return fields.count > 1 ? String(fields[1]) : nil
            }
        return Set(workspaces)
    }

    // MARK: - Promotion

    private func resolveCurrentDirectory(in rootURL: URL) -> URL? {
        let current = rootURL.appendingPathComponent("current", isDirectory: true)
        let resolved = current.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return resolved
    }

    private func promote(temporaryDirectory: URL, to finalDirectory: URL, in rootURL: URL) throws {
        if fileManager.fileExists(atPath: finalDirectory.path) {
            try? fileManager.removeItem(at: finalDirectory)
        }
        try fileManager.moveItem(at: temporaryDirectory, to: finalDirectory)

        let currentLink = rootURL.appendingPathComponent("current")
        let currentType = (try? fileManager.attributesOfItem(atPath: currentLink.path))?[.type] as? FileAttributeType
        if let currentType, currentType != .typeSymbolicLink {
            // A real directory from an older layout: move it aside so the
            // symlink can take its place, then delete it.
            let retired = rootURL.appendingPathComponent(".previous-current-\(UUID().uuidString.prefix(6))")
            try? fileManager.moveItem(at: currentLink, to: retired)
            try? fileManager.removeItem(at: retired)
        }

        // rename(2) replaces the existing symlink atomically, so `current`
        // never dangles even if the app dies mid-promotion.
        let temporaryLink = rootURL.appendingPathComponent(".current-link-\(UUID().uuidString.prefix(6))")
        try fileManager.createSymbolicLink(
            atPath: temporaryLink.path,
            withDestinationPath: finalDirectory.lastPathComponent
        )
        guard rename(temporaryLink.path, currentLink.path) == 0 else {
            try? fileManager.removeItem(at: temporaryLink)
            throw SnapshotEngineError.outputDirectoryUnavailable(currentLink.path)
        }

        cleanupOldRuns(in: rootURL, keeping: finalDirectory.lastPathComponent)
    }

    private func cleanupOldRuns(in rootURL: URL, keeping keptName: String) {
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

    // MARK: - Helpers

    private func listWindows() async throws -> [WorkspaceWindow] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [client] in
                continuation.resume(with: Result { try client.listWindows() })
            }
        }
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
}
