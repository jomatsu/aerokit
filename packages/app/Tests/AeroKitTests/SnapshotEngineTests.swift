import CoreGraphics
import XCTest
@testable import AeroKitCore
@testable import SwitcherFeature

private let engineFixedNow = Date(timeIntervalSince1970: 1_704_067_200)

final class SnapshotEngineTests: XCTestCase {
    private let us = "\u{1f}"

    func testPublicRefreshThrowsWhenAeroSpaceReportsNoWorkspaces() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        var configuration = SwitcherConfiguration()
        configuration.snapshotRootPath = root.path
        let engine = SnapshotEngine(
            configuration: configuration,
            client: AeroSpaceClient(
                executablePath: "/usr/bin/true",
                runner: ListingRunner(workspacesOutput: "", windowsOutput: "")
            )
        )

        do {
            _ = try await engine.refresh()
            XCTFail("Expected noWorkspaces")
        } catch SnapshotEngineError.noWorkspaces {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("current").path))
        }
    }

    func testRefreshWritesManifestAndPromotesCurrentUsingNormalizedRoot() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let image = try XCTUnwrap(solidImage())
        let engine = makeEngine(
            rootPath: root.path + "/",
            workspaces: workspaceLine("1"),
            windows: windowLine(id: "42", bundle: "com.apple.Safari", app: "Safari", workspace: "1")
        ) { _ in image }

        let current = try await engine.refresh()

        let expectedCurrent = URL(fileURLWithPath: root.path, isDirectory: true)
            .appendingPathComponent("current", isDirectory: true)
        XCTAssertEqual(current.path, expectedCurrent.path)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: current.path),
            ".current-\(fixtureRunID(engineFixedNow))"
        )
        let type = try FileManager.default.attributesOfItem(atPath: current.path)[.type] as? FileAttributeType
        XCTAssertEqual(type, .typeSymbolicLink)
        let body = try manifestFields(in: current)
        XCTAssertEqual(body.count, 11)
        XCTAssertEqual(body[0], fixtureManifestTimestamp(engineFixedNow))
        XCTAssertEqual(body[2], "42")
        XCTAssertEqual(body[10], "captured")
        XCTAssertFalse(body[9].contains("//"))
        XCTAssertTrue(body[9].hasSuffix("/workspace-1/window-42-Safari.jpg"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: body[9]).path))
    }

    func testExcludedAppsAreNeverCapturedOrListed() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let capturedIDs = LockedValue<[CGWindowID]>([])
        let image = try XCTUnwrap(solidImage())
        let windows = [
            windowLine(id: "11", bundle: "com.apple.Safari", app: "Safari", workspace: "1"),
            windowLine(id: "22", bundle: "com.1password.1password", app: "1Password", workspace: "1"),
            windowLine(id: "33", bundle: "com.apple.Passwords", app: "Passwords", workspace: "2")
        ].joined(separator: "\n")
        let engine = makeEngine(
            rootPath: root.path,
            workspaces: [workspaceLine("1"), workspaceLine("2")].joined(separator: "\n"),
            windows: windows
        ) { id in
            capturedIDs.withLock { $0.append(id) }
            return image
        }

        let current = try await engine.refresh(excluding: ["1password", "com.apple.passwords"])

        XCTAssertEqual(capturedIDs.withLock { $0 }, [11])
        let manifest = try String(
            contentsOf: current.appendingPathComponent("manifest.tsv"),
            encoding: .utf8
        )
        XCTAssertTrue(manifest.contains("\t11\t"))
        XCTAssertFalse(manifest.contains("1Password"))
        XCTAssertFalse(manifest.contains("com.1password.1password"))
        XCTAssertFalse(manifest.contains("Passwords"))
        XCTAssertFalse(manifest.contains("com.apple.Passwords"))
        XCTAssertFalse(manifest.contains("\t22\t"))
        XCTAssertFalse(manifest.contains("\t33\t"))
    }

    func testAllCapturesFailedPreservesExistingCurrent() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let planted = try plantCurrentRun(in: root, windowID: "99", fileExtension: "jpg")
        let engine = makeEngine(
            rootPath: root.path,
            workspaces: workspaceLine("1"),
            windows: windowLine(id: "42", bundle: "com.apple.Safari", app: "Safari", workspace: "1")
        ) { _ in nil }

        do {
            _ = try await engine.refresh()
            XCTFail("Expected nothingCaptured")
        } catch SnapshotEngineError.nothingCaptured {
            let current = try FileManager.default.destinationOfSymbolicLink(
                atPath: root.appendingPathComponent("current").path
            )
            XCTAssertEqual(current, planted.lastPathComponent)
            XCTAssertEqual(
                try String(contentsOf: planted.appendingPathComponent("manifest.tsv"), encoding: .utf8),
                try String(
                    contentsOf: root.appendingPathComponent("current/manifest.tsv"),
                    encoding: .utf8
                )
            )
            XCTAssertFalse(try directoryNames(in: root).contains { $0.hasPrefix(".next-") })
        }
    }

    func testCachedReuseCopiesPreviousCaptureAndMarksCached() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        _ = try plantCurrentRun(in: root, windowID: "42", fileExtension: "jpg")
        let engine = makeEngine(
            rootPath: root.path,
            workspaces: workspaceLine("1"),
            windows: windowLine(id: "42", bundle: "com.apple.Safari", app: "Safari", workspace: "1")
        ) { _ in nil }

        let current = try await engine.refresh()
        let body = try manifestFields(in: current)
        XCTAssertEqual(body[10], "cached")
        XCTAssertTrue(body[9].hasSuffix("/workspace-1/window-42-Safari.jpg"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: body[9]).path))
        XCTAssertTrue(body[9].contains("/.current-\(fixtureRunID(engineFixedNow))/"))
        XCTAssertFalse(body[9].contains(".current-planted"))
    }

    func testCachedReusePreservesLegacyPNGPath() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        _ = try plantCurrentRun(in: root, windowID: "42", fileExtension: "png")
        let engine = makeEngine(
            rootPath: root.path,
            workspaces: workspaceLine("1"),
            windows: windowLine(id: "42", bundle: "com.apple.Safari", app: "Safari", workspace: "1")
        ) { _ in nil }

        let body = try await manifestFields(in: engine.refresh())
        XCTAssertEqual(body[10], "cached")
        XCTAssertTrue(body[9].hasSuffix("/workspace-1/window-42-Safari.png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: body[9]).path))
    }

    func testProgressAndResultsPreserveInputOrder() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let gate = ArrivalGate()
        let completionOrder = LockedValue<[CGWindowID]>([])
        let progress = LockedValue<[(Int, Int)]>([])
        let image = try XCTUnwrap(solidImage())
        let windows = [
            windowLine(id: "1", bundle: "com.apple.Safari", app: "Safari", workspace: "1"),
            windowLine(id: "2", bundle: "com.apple.TextEdit", app: "TextEdit", workspace: "1")
        ].joined(separator: "\n")
        let engine = makeEngine(
            rootPath: root.path,
            workspaces: workspaceLine("1"),
            windows: windows
        ) { id in
            if id == 1 {
                await gate.waitForSecond()
                completionOrder.withLock { $0.append(id) }
            } else {
                completionOrder.withLock { $0.append(id) }
                gate.markSecondStarted()
            }
            return image
        }

        let current = try await engine.refresh { completed, total in
            progress.withLock { $0.append((completed, total)) }
        }

        XCTAssertEqual(completionOrder.withLock { $0 }, [2, 1])
        XCTAssertEqual(progress.withLock { $0.map(\.0) }, [0, 1, 2])
        XCTAssertEqual(progress.withLock { $0.map(\.1) }, [2, 2, 2])
        let lines = try String(contentsOf: current.appendingPathComponent("manifest.tsv"), encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false)[2] }
        XCTAssertEqual(lines.map(String.init), ["1", "2"])
    }

    func testWriteFailureCleansTemporaryDirectoryAndPreservesCurrent() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let planted = try plantCurrentRun(in: root, windowID: "99", fileExtension: "jpg")
        let image = try XCTUnwrap(solidImage())
        let storage = SnapshotRunStorage(
            now: { engineFixedNow },
            uniqueSuffix: { "test01" },
            writeText: { _, _ in throw StubWriteError() }
        )
        let engine = makeEngine(
            rootPath: root.path,
            workspaces: workspaceLine("1"),
            windows: windowLine(id: "42", bundle: "com.apple.Safari", app: "Safari", workspace: "1"),
            storage: storage
        ) { _ in image }

        do {
            _ = try await engine.refresh()
            XCTFail("Expected write failure")
        } catch is StubWriteError {
            XCTAssertEqual(
                try FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent("current").path),
                planted.lastPathComponent
            )
            XCTAssertFalse(try directoryNames(in: root).contains { $0.hasPrefix(".next-") })
            XCTAssertFalse(try directoryNames(in: root).contains { $0.hasPrefix(".current-20") })
        }
    }

    func testRenameFailureLeavesFinalDirectoryAndPreservesCurrent() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let planted = try plantCurrentRun(in: root, windowID: "99", fileExtension: "jpg")
        let image = try XCTUnwrap(solidImage())
        let storage = SnapshotRunStorage(
            now: { engineFixedNow },
            uniqueSuffix: { "test01" },
            renamePath: { _, _ in -1 }
        )
        let engine = makeEngine(
            rootPath: root.path,
            workspaces: workspaceLine("1"),
            windows: windowLine(id: "42", bundle: "com.apple.Safari", app: "Safari", workspace: "1"),
            storage: storage
        ) { _ in image }

        do {
            _ = try await engine.refresh()
            XCTFail("Expected rename failure")
        } catch let SnapshotEngineError.outputDirectoryUnavailable(path) {
            XCTAssertEqual(path, root.appendingPathComponent("current").path)
            XCTAssertEqual(
                try FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent("current").path),
                planted.lastPathComponent
            )
            let names = try directoryNames(in: root)
            XCTAssertFalse(names.contains { $0.hasPrefix(".current-link-") })
            XCTAssertFalse(names.contains { $0.hasPrefix(".next-") })
            XCTAssertTrue(names.contains { $0.hasPrefix(".current-") && $0 != ".current-planted" })
        }
    }

    private func makeEngine(
        rootPath: String,
        workspaces: String,
        windows: String,
        storage: SnapshotRunStorage? = nil,
        capture: @escaping @Sendable (CGWindowID) async -> CGImage?
    ) -> SnapshotEngine {
        var configuration = SwitcherConfiguration()
        configuration.snapshotRootPath = rootPath
        configuration.snapshotComposeSize = CGSize(width: 160, height: 90)
        return SnapshotEngine(
            configuration: configuration,
            client: AeroSpaceClient(
                executablePath: "/usr/bin/true",
                runner: ListingRunner(workspacesOutput: workspaces, windowsOutput: windows)
            ),
            storage: storage ?? SnapshotRunStorage(now: { engineFixedNow }, uniqueSuffix: { "test01" }),
            captureImage: capture
        )
    }

    private func workspaceLine(_ name: String) -> String {
        "\(name)\(us)false"
    }

    private func windowLine(id: String, bundle: String, app: String, workspace: String) -> String {
        [id, bundle, app, workspace, "Apple", "tiling", "h_tiles", "v_tiles"].joined(separator: us)
    }
}

private struct StubWriteError: Error {}

private enum FixtureError: Error {
    case missingImage
    case writeFailed
}

private final class ListingRunner: CommandRunning, @unchecked Sendable {
    let workspacesOutput: String
    let windowsOutput: String

    init(workspacesOutput: String, windowsOutput: String) {
        self.workspacesOutput = workspacesOutput
        self.windowsOutput = windowsOutput
    }

    func run(_ executable: String, arguments: [String]) throws -> ProcessResult {
        let output: String = if arguments.first == "list-workspaces" {
            workspacesOutput
        } else if arguments.first == "list-windows" {
            windowsOutput
        } else {
            ""
        }
        return ProcessResult(standardOutput: output, standardError: "", terminationStatus: 0)
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    @discardableResult
    func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

private final class ArrivalGate: @unchecked Sendable {
    private let lock = NSLock()
    private var secondStarted = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func waitForSecond() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if secondStarted {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func markSecondStarted() {
        lock.lock()
        secondStarted = true
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        for continuation in pending {
            continuation.resume()
        }
    }
}

private func solidImage(white: CGFloat = 0.5, size: Int = 32) -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    context.setFillColor(CGColor(red: white, green: white, blue: white, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    return context.makeImage()
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aerokit-snapshot-engine-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func removeTemporaryDirectory(_ directory: URL) {
    try? FileManager.default.removeItem(at: directory)
}

private func directoryNames(in root: URL) throws -> Set<String> {
    try Set(FileManager.default.contentsOfDirectory(atPath: root.path))
}

private func manifestFields(in current: URL) throws -> [String] {
    let lines = try String(contentsOf: current.appendingPathComponent("manifest.tsv"), encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: false)
    return lines[1].split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
}

/// Test-owned copy of the production timestamp layout. Time zone is the
/// process default so a formatter change in storage fails this fixture.
private func fixtureManifestTimestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: date)
}

private func fixtureRunID(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: date)
}

private func plantCurrentRun(in root: URL, windowID: String, fileExtension: String) throws -> URL {
    let runDir = root.appendingPathComponent(".current-planted", isDirectory: true)
    let relativePath = "workspace-1/window-\(windowID)-Safari.\(fileExtension)"
    let fileURL = runDir.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let image = solidImage() else {
        throw FixtureError.missingImage
    }
    let wrote: Bool = if fileExtension == "png" {
        WorkspaceComposer.writePNG(image, to: fileURL)
    } else {
        WorkspaceComposer.writeJPEG(image, to: fileURL)
    }
    guard wrote else {
        throw FixtureError.writeFailed
    }
    let header = [
        "timestamp", "workspace", "window_id", "app_id", "app_name", "window_title",
        "window_layout", "window_parent_container_layout", "workspace_root_container_layout",
        "file", "status"
    ].joined(separator: "\t")
    let row = [
        "2020-01-01T00:00:00+0000", "1", windowID, "com.apple.Safari", "Safari", "Apple",
        "tiling", "h_tiles", "v_tiles", fileURL.path, "captured"
    ].joined(separator: "\t")
    try "\(header)\n\(row)\n".write(
        to: runDir.appendingPathComponent("manifest.tsv"),
        atomically: true,
        encoding: .utf8
    )
    try FileManager.default.createSymbolicLink(
        atPath: root.appendingPathComponent("current").path,
        withDestinationPath: runDir.lastPathComponent
    )
    return runDir
}
