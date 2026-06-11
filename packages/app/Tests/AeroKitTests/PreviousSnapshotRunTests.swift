import Foundation
import XCTest
@testable import AeroKitCore
@testable import SwitcherFeature

final class PreviousSnapshotRunTests: XCTestCase {
    private let header = [
        "timestamp", "workspace", "window_id", "app_id", "app_name", "window_title",
        "window_layout", "window_parent_container_layout", "workspace_root_container_layout",
        "file", "status"
    ]

    private func row(
        workspace: String,
        windowID: String,
        file: String,
        status: String
    ) -> [String] {
        [
            "2026-06-10T12:00:00+0900", workspace, windowID, "com.example.app", "App",
            "Title", "tiling", "h_tiles", "h_tiles", file, status
        ]
    }

    private func manifest(rows: [[String]]) -> String {
        ([header] + rows).map { $0.joined(separator: "\t") }.joined(separator: "\n") + "\n"
    }

    func testParseCollectsWorkspacesAndEntries() {
        let manifest = manifest(rows: [
            row(workspace: "1", windowID: "101", file: "/tmp/run/workspace-1/window-101-App.jpg", status: "captured"),
            row(workspace: "1", windowID: "102", file: "/tmp/run/workspace-1/window-102-App.png", status: "cached"),
            row(workspace: "2", windowID: "201", file: "/tmp/run/workspace-2/window-201-App.jpg", status: "failed")
        ])

        let run = PreviousSnapshotRun.parse(manifest: manifest)

        XCTAssertEqual(run.workspaces, ["1", "2"])
        XCTAssertEqual(run.entriesByWindowID.count, 3)
        XCTAssertEqual(run.entriesByWindowID["101"]?.status, .captured)
        XCTAssertEqual(
            run.entriesByWindowID["102"]?.fileURL.path,
            "/tmp/run/workspace-1/window-102-App.png"
        )
        XCTAssertEqual(run.entriesByWindowID["201"]?.status, .failed)
        XCTAssertEqual(run.entriesByWindowID["201"]?.status.isUsable, false)
    }

    func testParseSkipsMalformedRowsButKeepsWorkspace() {
        let manifest = manifest(rows: [
            ["2026-06-10T12:00:00+0900", "3", "301"],
            row(workspace: "4", windowID: "401", file: "/tmp/x.jpg", status: "not-a-status")
        ])

        let run = PreviousSnapshotRun.parse(manifest: manifest)

        XCTAssertEqual(run.workspaces, ["3", "4"])
        XCTAssertTrue(run.entriesByWindowID.isEmpty)
    }

    func testLoadFromMissingManifestKeepsDirectory() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let run = PreviousSnapshotRun.load(fromManifestIn: directory)

        XCTAssertEqual(run.directory, directory)
        XCTAssertTrue(run.workspaces.isEmpty)
        XCTAssertTrue(run.entriesByWindowID.isEmpty)
    }

    func testLoadFromManifestFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = manifest(rows: [
            row(workspace: "Q", windowID: "501", file: "/tmp/run/workspace-Q/window-501-App.jpg", status: "captured")
        ])
        try manifest.write(
            to: directory.appendingPathComponent("manifest.tsv"),
            atomically: true,
            encoding: .utf8
        )

        let run = PreviousSnapshotRun.load(fromManifestIn: directory)

        XCTAssertEqual(run.workspaces, ["Q"])
        XCTAssertEqual(run.entriesByWindowID["501"]?.status, .captured)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aeroswitcher-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
