import XCTest
@testable import AeroKitCore
@testable import SwitcherFeature

private let storageFixedNow = Date(timeIntervalSince1970: 1_704_067_200)

final class SnapshotRunStorageTests: XCTestCase {
    func testWriteManifestHasElevenTabSeparatedColumnsAndTrailingNewline() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let storage = makeStorage()
        let run = try storage.prepareRun(in: root, workspaces: ["1"])
        let row = safariRow(relativePath: "workspace-1/window-42-Safari.jpg", status: .captured)

        try storage.writeManifest(rows: [row], in: run.temporaryDirectory, finalDirectory: run.finalDirectory)

        let manifest = try manifestContents(in: run.temporaryDirectory)
        XCTAssertTrue(manifest.hasSuffix("\n"))
        let lines = manifest.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(lines.last, "")
        let header = fields(in: lines[0])
        let body = fields(in: lines[1])
        XCTAssertEqual(header, manifestHeader)
        XCTAssertEqual(body.count, 11)
        XCTAssertEqual(body[2], "42")
        XCTAssertEqual(body[10], "captured")
        XCTAssertEqual(body[9], run.finalDirectory.appendingPathComponent(row.relativePath).path)
    }

    func testWriteManifestSanitizesTabsAndNewlinesInFields() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let storage = makeStorage()
        let run = try storage.prepareRun(in: root, workspaces: ["1"])
        var row = safariRow(relativePath: "workspace-1/window-42-Safari.jpg")
        row.window.title = "Hello\tWorld\nNext"
        row.window.appName = "Saf\tari"

        try storage.writeManifest(rows: [row], in: run.temporaryDirectory, finalDirectory: run.finalDirectory)

        let body = try fields(in: manifestLines(in: run.temporaryDirectory)[1])
        XCTAssertEqual(body.count, 11)
        XCTAssertEqual(body[4], "Saf ari")
        XCTAssertEqual(body[5], "Hello World Next")
        XCTAssertFalse(body[5].contains("\t"))
        XCTAssertFalse(body[5].contains("\n"))
    }

    func testWriteManifestUsesOneClockReadingForEveryRow() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let clock = SteppingClock(dates: [
            Date(timeIntervalSince1970: 1000),
            Date(timeIntervalSince1970: 2000),
            Date(timeIntervalSince1970: 3000)
        ])
        let storage = SnapshotRunStorage(now: { clock.now() }, uniqueSuffix: { "abc123" })
        let run = try storage.prepareRun(in: root, workspaces: ["1"])
        let rows = [
            safariRow(id: "1", relativePath: "workspace-1/window-1-Safari.jpg"),
            safariRow(id: "2", relativePath: "workspace-1/window-2-Safari.jpg")
        ]

        try storage.writeManifest(rows: rows, in: run.temporaryDirectory, finalDirectory: run.finalDirectory)

        let lines = try manifestLines(in: run.temporaryDirectory)
        let first = fields(in: lines[1])
        let second = fields(in: lines[2])
        let expected = fixtureManifestTimestamp(Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(first[0], expected)
        XCTAssertEqual(second[0], expected)
        XCTAssertEqual(
            run.finalDirectory.lastPathComponent,
            ".current-\(fixtureRunID(Date(timeIntervalSince1970: 1000)))"
        )
    }

    func testWriteManifestFullBytesMatchFixture() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let storage = makeStorage()
        let run = try storage.prepareRun(in: root, workspaces: ["1"])
        var row = safariRow(relativePath: "workspace-1/window-42-Safari.jpg", status: .captured)
        row.window.title = "Hello\tWorld\nNext"
        row.window.appName = "Saf\tari"

        try storage.writeManifest(rows: [row], in: run.temporaryDirectory, finalDirectory: run.finalDirectory)

        let filePath = "\(run.finalDirectory.path)/workspace-1/window-42-Safari.jpg"
        let expected = [
            manifestHeader.joined(separator: "\t"),
            [
                fixtureManifestTimestamp(storageFixedNow),
                "1", "42", "com.apple.Safari", "Saf ari", "Hello World Next",
                "tiling", "h_tiles", "v_tiles", filePath, "captured"
            ].joined(separator: "\t")
        ].joined(separator: "\n") + "\n"
        XCTAssertEqual(try manifestContents(in: run.temporaryDirectory), expected)
    }

    func testWriteManifestNormalizesTrailingSlashInRootFileColumn() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let slashedRoot = URL(fileURLWithPath: root.path + "/", isDirectory: true)
        let storage = makeStorage()
        let run = try storage.prepareRun(in: slashedRoot, workspaces: ["1"])
        let row = safariRow(relativePath: "workspace-1/window-42-Safari.jpg")

        try storage.writeManifest(rows: [row], in: run.temporaryDirectory, finalDirectory: run.finalDirectory)

        let fileColumn = try fields(in: manifestLines(in: run.temporaryDirectory)[1])[9]
        XCTAssertFalse(fileColumn.contains("//"))
        XCTAssertEqual(fileColumn, run.finalDirectory.appendingPathComponent(row.relativePath).path)
        XCTAssertTrue(fileColumn.hasPrefix(slashedRoot.path))
        XCTAssertFalse(slashedRoot.path.hasSuffix("/"))
    }

    func testWriteManifestPreservesLegacyPNGRelativePath() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let storage = makeStorage()
        let run = try storage.prepareRun(in: root, workspaces: ["1"])
        let row = safariRow(relativePath: "workspace-1/window-42-Safari.png", status: .cached)

        try storage.writeManifest(rows: [row], in: run.temporaryDirectory, finalDirectory: run.finalDirectory)

        let body = try fields(in: manifestLines(in: run.temporaryDirectory)[1])
        XCTAssertTrue(body[9].hasSuffix("/workspace-1/window-42-Safari.png"))
        XCTAssertEqual(body[10], "cached")
        XCTAssertEqual(body[9], run.finalDirectory.appendingPathComponent(row.relativePath).path)
    }

    func testPromoteCreatesRelativeCurrentSymlink() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let storage = makeStorage()
        let run = try prepareManifest(storage: storage, root: root)

        try storage.promote(
            temporaryDirectory: run.temporaryDirectory,
            to: run.finalDirectory,
            in: root
        )

        let current = root.appendingPathComponent("current")
        let type = try FileManager.default.attributesOfItem(atPath: current.path)[.type] as? FileAttributeType
        XCTAssertEqual(type, .typeSymbolicLink)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: current.path),
            run.finalDirectory.lastPathComponent
        )
        let manifestURL = run.finalDirectory.appendingPathComponent("manifest.tsv")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: run.temporaryDirectory.path))
    }

    func testPromoteRetiresLegacyRealCurrentDirectory() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let storage = makeStorage()
        let run = try prepareManifest(storage: storage, root: root)
        let current = root.appendingPathComponent("current", isDirectory: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try "legacy".write(to: current.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)

        try storage.promote(
            temporaryDirectory: run.temporaryDirectory,
            to: run.finalDirectory,
            in: root
        )

        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: current.path),
            run.finalDirectory.lastPathComponent
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: current.appendingPathComponent("marker.txt").path))
        let names = try directoryNames(in: root)
        XCTAssertFalse(names.contains { $0.hasPrefix(".previous-current-") })
        XCTAssertTrue(names.contains(run.finalDirectory.lastPathComponent))
    }

    func testWriteFailurePropagatesErrorAndLeavesTemporaryDirectory() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let storage = SnapshotRunStorage(
            now: { storageFixedNow },
            uniqueSuffix: { "abc123" },
            writeText: { _, _ in throw StubWriteError() }
        )
        let run = try storage.prepareRun(in: root, workspaces: ["1"])

        XCTAssertThrowsError(
            try storage.writeManifest(
                rows: [safariRow(relativePath: "workspace-1/window-42-Safari.jpg")],
                in: run.temporaryDirectory,
                finalDirectory: run.finalDirectory
            )
        ) { error in
            XCTAssertTrue(error is StubWriteError)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: run.temporaryDirectory.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: run.temporaryDirectory.appendingPathComponent("manifest.tsv").path)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("current").path))
    }

    func testRenameFailureRemovesTemporaryLinkAndLeavesFinalDirectory() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let storage = SnapshotRunStorage(
            now: { storageFixedNow },
            uniqueSuffix: { "abc123" },
            renamePath: { _, _ in -1 }
        )
        let run = try prepareManifest(storage: storage, root: root)

        XCTAssertThrowsError(
            try storage.promote(
                temporaryDirectory: run.temporaryDirectory,
                to: run.finalDirectory,
                in: root
            )
        ) { error in
            guard case let SnapshotEngineError.outputDirectoryUnavailable(path) = error else {
                return XCTFail("Expected outputDirectoryUnavailable, got \(error)")
            }
            XCTAssertEqual(path, root.appendingPathComponent("current").path)
        }

        let names = try directoryNames(in: root)
        XCTAssertFalse(names.contains { $0.hasPrefix(".current-link-") })
        XCTAssertTrue(names.contains(run.finalDirectory.lastPathComponent))
        XCTAssertFalse(FileManager.default.fileExists(atPath: run.temporaryDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("current").path))
    }

    func testRenameFailureAfterRetiringLegacyRealCurrentLeavesFinalRun() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let storage = SnapshotRunStorage(
            now: { storageFixedNow },
            uniqueSuffix: { "abc123" },
            renamePath: { _, _ in -1 }
        )
        let run = try prepareManifest(storage: storage, root: root)
        let current = root.appendingPathComponent("current", isDirectory: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try "legacy".write(to: current.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try storage.promote(
                temporaryDirectory: run.temporaryDirectory,
                to: run.finalDirectory,
                in: root
            )
        ) { error in
            guard case let SnapshotEngineError.outputDirectoryUnavailable(path) = error else {
                return XCTFail("Expected outputDirectoryUnavailable, got \(error)")
            }
            XCTAssertEqual(path, current.path)
        }

        let names = try directoryNames(in: root)
        XCTAssertFalse(names.contains { $0.hasPrefix(".previous-current-") })
        XCTAssertFalse(names.contains { $0.hasPrefix(".current-link-") })
        XCTAssertTrue(names.contains(run.finalDirectory.lastPathComponent))
        XCTAssertFalse(FileManager.default.fileExists(atPath: run.temporaryDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: current.path))
    }

    func testPromoteDeletesEngineAndLegacyRunsButKeepsUserCreatedDirectories() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        try seedCleanupEntries(in: root)
        let storage = makeStorage()
        let run = try prepareManifest(storage: storage, root: root)

        try storage.promote(
            temporaryDirectory: run.temporaryDirectory,
            to: run.finalDirectory,
            in: root
        )

        let names = try directoryNames(in: root)
        XCTAssertEqual(
            names.subtracting([run.finalDirectory.lastPathComponent, "current"]),
            ["20240101-120001", "readme.txt", "user-notes"]
        )
        XCTAssertFalse(names.contains(".current-old"))
        XCTAssertFalse(names.contains(".next-stale"))
        XCTAssertFalse(names.contains(".previous-current-zzz"))
        XCTAssertFalse(names.contains("20240101-120000"))
    }

    func testResolveCurrentDirectoryFollowsSymlinkAndIgnoresMissing() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let storage = makeStorage()
        XCTAssertNil(storage.resolveCurrentDirectory(in: root))

        let run = try prepareManifest(storage: storage, root: root)
        try storage.promote(
            temporaryDirectory: run.temporaryDirectory,
            to: run.finalDirectory,
            in: root
        )

        XCTAssertEqual(
            storage.resolveCurrentDirectory(in: root)?.resolvingSymlinksInPath(),
            run.finalDirectory.resolvingSymlinksInPath()
        )
    }

    func testPrepareRunThrowsWhenRootPathIsAnExistingFile() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let file = root.appendingPathComponent("not-a-directory")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let blockedRoot = file.appendingPathComponent("snapshots")

        XCTAssertThrowsError(try makeStorage().prepareRun(in: blockedRoot, workspaces: ["1"])) { error in
            guard case SnapshotEngineError.outputDirectoryUnavailable = error else {
                return XCTFail("Expected outputDirectoryUnavailable, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: blockedRoot.path))
    }

    private func makeStorage() -> SnapshotRunStorage {
        SnapshotRunStorage(now: { storageFixedNow }, uniqueSuffix: { "abc123" })
    }

    private func prepareManifest(storage: SnapshotRunStorage, root: URL) throws -> SnapshotRunDirectories {
        let run = try storage.prepareRun(in: root, workspaces: ["1"])
        try storage.writeManifest(
            rows: [safariRow(relativePath: "workspace-1/window-42-Safari.jpg")],
            in: run.temporaryDirectory,
            finalDirectory: run.finalDirectory
        )
        return run
    }
}

private struct StubWriteError: Error {}

private final class SteppingClock: @unchecked Sendable {
    private let dates: [Date]
    private var index = 0

    init(dates: [Date]) {
        self.dates = dates
    }

    func now() -> Date {
        let date = dates[min(index, dates.count - 1)]
        index += 1
        return date
    }
}

private let manifestHeader = [
    "timestamp", "workspace", "window_id", "app_id", "app_name", "window_title",
    "window_layout", "window_parent_container_layout", "workspace_root_container_layout",
    "file", "status"
]

private func safariRow(
    id: String = "42",
    relativePath: String,
    status: SnapshotStatus = .captured
) -> SnapshotManifestRow {
    SnapshotManifestRow(
        window: WorkspaceWindow(
            id: id,
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari",
            workspace: "1",
            title: "Apple",
            layout: "tiling",
            parentContainerLayout: "h_tiles",
            workspaceRootContainerLayout: "v_tiles"
        ),
        relativePath: relativePath,
        status: status
    )
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aerokit-snapshot-storage-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func removeTemporaryDirectory(_ directory: URL) {
    try? FileManager.default.removeItem(at: directory)
}

private func manifestContents(in directory: URL) throws -> String {
    try String(contentsOf: directory.appendingPathComponent("manifest.tsv"), encoding: .utf8)
}

private func manifestLines(in directory: URL) throws -> [String] {
    try manifestContents(in: directory).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

private func fields(in line: String) -> [String] {
    line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
}

private func directoryNames(in root: URL) throws -> Set<String> {
    try Set(FileManager.default.contentsOfDirectory(atPath: root.path))
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

private func seedCleanupEntries(in root: URL) throws {
    let fileManager = FileManager.default
    for name in [".current-old", ".next-stale", ".previous-current-zzz", "user-notes"] {
        try fileManager.createDirectory(
            at: root.appendingPathComponent(name, isDirectory: true),
            withIntermediateDirectories: true
        )
    }
    let legacyWithManifest = root.appendingPathComponent("20240101-120000", isDirectory: true)
    try fileManager.createDirectory(at: legacyWithManifest, withIntermediateDirectories: true)
    try "header\n".write(
        to: legacyWithManifest.appendingPathComponent("manifest.tsv"),
        atomically: true,
        encoding: .utf8
    )
    try fileManager.createDirectory(
        at: root.appendingPathComponent("20240101-120001", isDirectory: true),
        withIntermediateDirectories: true
    )
    try "keep\n".write(to: root.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
}
