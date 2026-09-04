import AeroKitCore
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
            "AeroSpace reported no workspaces to snapshot"
        case .nothingCaptured:
            "No windows captured"
        case let .outputDirectoryUnavailable(path):
            "Could not prepare snapshot directory: \(path)"
        }
    }
}

/// Captures every window of the configured workspaces, composes one
/// overview image per workspace, writes the manifest, and atomically
/// promotes the run to `<root>/current`.
public final class SnapshotEngine: Sendable {
    private struct WindowResult: @unchecked Sendable {
        var window: WorkspaceWindow
        var status: SnapshotStatus
        var composeImage: CGImage?
        var relativePath: String
    }

    /// SCWindow is not Sendable, but these are immutable snapshots that the
    /// capture tasks only read.
    private struct ShareableWindows: @unchecked Sendable {
        let byID: [CGWindowID: SCWindow]
    }

    /// The SCShareableContent query (~70ms wall + replayd CPU) is only
    /// needed by the ScreenCaptureKit fallback, so it starts on first use;
    /// runs where every fast-path capture succeeds never pay for it.
    private actor LazyShareableWindows {
        private let capturer: WindowImageCapturer
        private var task: Task<ShareableWindows, Never>?

        init(capturer: WindowImageCapturer) {
            self.capturer = capturer
        }

        func all() async -> ShareableWindows {
            let resolved = task ?? Task { [capturer] in
                await ShareableWindows(byID: (try? capturer.shareableWindows()) ?? [:])
            }
            task = resolved
            return await resolved.value
        }
    }

    /// Per-batch capture inputs, resolved once before the task group starts.
    private struct CaptureContext {
        let shareable: LazyShareableWindows
        let boundsByID: [CGWindowID: CGSize]
        let displayScale: CGFloat
    }

    private let configuration: SwitcherConfiguration
    private let client: AeroSpaceClient
    private let capturer: WindowImageCapturer
    private let storage: SnapshotRunStorage
    /// Test-only image source, called concurrently from the capture task group.
    private let captureImage: (@Sendable (CGWindowID) async -> CGImage?)?
    private var fileManager: FileManager {
        .default
    }

    /// Compose cells are at most ~800pt wide, so captures are requested at
    /// this size and full-resolution pixels never enter the pipeline.
    private static let composeImageMaxDimension: CGFloat = 800

    private let composeImageCache = ComposeImageCache(maxDimension: SnapshotEngine.composeImageMaxDimension)

    public convenience init(configuration: SwitcherConfiguration, client: AeroSpaceClient) {
        self.init(configuration: configuration, client: client, storage: SnapshotRunStorage())
    }

    init(
        configuration: SwitcherConfiguration,
        client: AeroSpaceClient,
        storage: SnapshotRunStorage,
        captureImage: (@Sendable (CGWindowID) async -> CGImage?)? = nil
    ) {
        self.configuration = configuration
        self.client = client
        capturer = WindowImageCapturer()
        self.storage = storage
        self.captureImage = captureImage
    }

    /// Runs a full snapshot refresh and returns the promoted `current` directory.
    /// `onProgress` reports (completedWindows, totalWindows) as captures finish.
    public func refresh(
        excluding excludedApps: Set<String> = [],
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> URL {
        // Snapshot whatever workspaces AeroSpace actually reports — names
        // are user configuration, so a hardcoded list would silently skip
        // everything a differently-configured user has. Empty workspaces
        // stay in the list so they get a placeholder overview.
        let listing = try await listWorkspacesAndWindows()
        let workspaces = listing.workspaces
        guard !workspaces.isEmpty else {
            throw SnapshotEngineError.noWorkspaces
        }

        // A window can still report a workspace missing from the listing
        // (moved mid-refresh); drop it rather than write into a directory
        // that was never created.
        let selectedWorkspaces = Set(workspaces)
        let windows = listing.windows
            .filter { selectedWorkspaces.contains($0.workspace) }
            // Sensitive apps opted out of snapshots must be dropped before
            // capture — they are never captured, written, listed in the
            // manifest, or composed into an overview.
            .filter { window in
                !excludedApps.contains(window.appName.lowercased())
                    && !excludedApps.contains(window.bundleIdentifier.lowercased())
            }

        let rootURL = URL(fileURLWithPath: configuration.snapshotRootPath, isDirectory: true)
        let previousRun = PreviousSnapshotRun.load(
            fromManifestIn: storage.resolveCurrentDirectory(in: rootURL)
        )
        composeImageCache.prune(keeping: Set(windows.map(\.id)))

        let run = try storage.prepareRun(in: rootURL, workspaces: workspaces)
        var promoted = false
        defer {
            if !promoted {
                try? fileManager.removeItem(at: run.temporaryDirectory)
            }
        }

        let results = await captureWindows(
            windows,
            into: run.temporaryDirectory,
            previousRun: previousRun,
            onProgress: onProgress
        )

        let usableCount = results.filter(\.status.isUsable).count
        if !windows.isEmpty, usableCount == 0 {
            throw SnapshotEngineError.nothingCaptured
        }

        composeOverviews(
            workspaces: workspaces,
            results: results,
            outputDirectory: run.temporaryDirectory,
            previousRun: previousRun
        )

        try storage.writeManifest(
            rows: results.map { result in
                SnapshotManifestRow(
                    window: result.window,
                    relativePath: result.relativePath,
                    status: result.status
                )
            },
            in: run.temporaryDirectory,
            finalDirectory: run.finalDirectory
        )
        try storage.promote(
            temporaryDirectory: run.temporaryDirectory,
            to: run.finalDirectory,
            in: rootURL
        )
        promoted = true

        return rootURL.appendingPathComponent("current", isDirectory: true)
    }

    // MARK: - Capture

    private func captureWindows(
        _ windows: [WorkspaceWindow],
        into outputDirectory: URL,
        previousRun: PreviousSnapshotRun,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) async -> [WindowResult] {
        let context: CaptureContext? = if captureImage == nil {
            await CaptureContext(
                shareable: LazyShareableWindows(capturer: capturer),
                boundsByID: capturer.windowBoundsByID().mapValues(\.size),
                displayScale: capturer.maximumDisplayScale()
            )
        } else {
            nil
        }

        onProgress?(0, windows.count)
        var completed = 0
        var results = [WindowResult?](repeating: nil, count: windows.count)
        await withTaskGroup(of: (Int, WindowResult).self) { group in
            for (index, window) in windows.enumerated() {
                group.addTask {
                    let result = await CaptureLimiter.shared.withSlot {
                        await self.captureWindow(
                            window,
                            context: context,
                            outputDirectory: outputDirectory,
                            previousEntry: previousRun.entriesByWindowID[window.id]
                        )
                    }
                    return (index, result)
                }
            }
            while let (index, result) = await group.next() {
                results[index] = result
                completed += 1
                onProgress?(completed, windows.count)
            }
        }

        return results.compactMap(\.self)
    }

    private func captureWindow(
        _ window: WorkspaceWindow,
        context: CaptureContext?,
        outputDirectory: URL,
        previousEntry: PreviousSnapshotRun.Entry?
    ) async -> WindowResult {
        let relativePath = relativeCapturePath(for: window)
        let fileURL = outputDirectory.appendingPathComponent(relativePath)

        func reuseOrFail(_ status: SnapshotStatus) -> WindowResult {
            reusePrevious(window: window, previousEntry: previousEntry, outputDirectory: outputDirectory)
                ?? WindowResult(window: window, status: status, composeImage: nil, relativePath: relativePath)
        }

        guard let windowID = CGWindowID(window.id) else {
            return reuseOrFail(.failed)
        }

        var captured: CGImage?
        if let captureImage {
            captured = await captureImage(windowID)
        } else if let context {
            // CGWindowListCreateImage first (~9ms/window); ScreenCaptureKit only
            // when it yields nothing, since SCScreenshotManager costs ~105ms per
            // window and serializes in replayd.
            captured = capturer.captureImageFast(
                windowID: windowID,
                maxDimension: Self.composeImageMaxDimension,
                pointSize: context.boundsByID[windowID]
            )
            if captured == nil, let scWindow = await context.shareable.all().byID[windowID] {
                captured = try? await capturer.captureImage(
                    of: scWindow,
                    displayScale: context.displayScale,
                    maxDimension: Self.composeImageMaxDimension
                )
            }
        }
        guard let image = captured else {
            return reuseOrFail(.failed)
        }

        if WorkspaceComposer.isBlackish(image) {
            return reuseOrFail(.failedBlack)
        }

        guard WorkspaceComposer.writeJPEG(image, to: fileURL) else {
            return WindowResult(window: window, status: .failed, composeImage: nil, relativePath: relativePath)
        }

        composeImageCache.store(image, forWindowID: window.id, sourceURL: fileURL)
        return WindowResult(window: window, status: .captured, composeImage: image, relativePath: relativePath)
    }

    /// The previous manifest already vouches for the file (only non-black,
    /// successful captures are ever written), so reuse trusts its status and
    /// skips re-decoding for validation.
    private func reusePrevious(
        window: WorkspaceWindow,
        previousEntry: PreviousSnapshotRun.Entry?,
        outputDirectory: URL
    ) -> WindowResult? {
        guard let previousEntry,
              previousEntry.status.isUsable,
              fileManager.fileExists(atPath: previousEntry.fileURL.path),
              let image = composeImageCache.image(forWindowID: window.id, at: previousEntry.fileURL)
        else {
            return nil
        }

        // Keep the source extension: runs that predate the JPEG switch
        // carry PNG captures forward.
        let fileExtension = previousEntry.fileURL.pathExtension.isEmpty ? "png" : previousEntry.fileURL.pathExtension
        let relativePath = relativeCapturePath(for: window, fileExtension: fileExtension)
        do {
            try fileManager.copyItem(
                at: previousEntry.fileURL,
                to: outputDirectory.appendingPathComponent(relativePath)
            )
        } catch {
            // A reuse entry whose file is missing must not reach the
            // manifest; let the caller record the window as failed instead.
            return nil
        }
        return WindowResult(window: window, status: .cached, composeImage: image, relativePath: relativePath)
    }

    private func relativeCapturePath(for window: WorkspaceWindow, fileExtension: String = "jpg") -> String {
        let directory = WorkspaceName.captureDirectoryName(window.workspace)
        let app = WorkspaceName.sanitizedFileStem(window.appName.isEmpty ? "window" : window.appName)
        return "\(directory)/window-\(window.id)-\(app).\(fileExtension)"
    }

    // MARK: - Compose

    private func composeOverviews(
        workspaces: [String],
        results: [WindowResult],
        outputDirectory: URL,
        previousRun: PreviousSnapshotRun
    ) {
        let resultsByWorkspace = Dictionary(grouping: results, by: \.window.workspace)

        // Each overview draws and encodes independently (~20ms each), so the
        // canvases render in parallel instead of serially.
        DispatchQueue.concurrentPerform(iterations: workspaces.count) { index in
            let workspace = workspaces[index]
            let fileName = WorkspaceName.overviewFileName(workspace)
            let outputURL = outputDirectory.appendingPathComponent(fileName)
            let workspaceResults = resultsByWorkspace[workspace] ?? []
            let images = workspaceResults.compactMap { $0.status.isUsable ? $0.composeImage : nil }

            if images.isEmpty {
                let previousOverview = previousRun.directory?.appendingPathComponent(fileName)
                let hadNoWindowsBefore = !previousRun.workspaces.contains(workspace)
                if hadNoWindowsBefore, let previousOverview, fileManager.fileExists(atPath: previousOverview.path) {
                    try? fileManager.copyItem(at: previousOverview, to: outputURL)
                    return
                }
                if let empty = WorkspaceComposer.emptyOverview(canvasSize: configuration.snapshotComposeSize) {
                    _ = WorkspaceComposer.writePNG(empty, to: outputURL)
                }
                return
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

    // MARK: - Helpers

    /// One background hop for both blocking CLI round trips.
    private func listWorkspacesAndWindows() async throws -> (workspaces: [String], windows: [WorkspaceWindow]) {
        try await BlockingWork.run { [client] in
            try (client.listWorkspaces().map(\.name), client.listWindows())
        }
    }
}
