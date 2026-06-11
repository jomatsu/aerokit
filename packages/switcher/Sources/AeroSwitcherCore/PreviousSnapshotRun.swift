import Foundation

/// Index of a prior run's manifest.tsv: which workspaces it covered and
/// where each window's capture lives, so the next run can reuse files
/// without decoding them for re-validation.
struct PreviousSnapshotRun {
    struct Entry {
        var fileURL: URL
        var status: SnapshotStatus
    }

    var directory: URL?
    var workspaces: Set<String> = []
    var entriesByWindowID: [String: Entry] = [:]

    static func load(fromManifestIn directory: URL?) -> PreviousSnapshotRun {
        guard let directory,
              let contents = try? String(
                  contentsOf: directory.appendingPathComponent("manifest.tsv"),
                  encoding: .utf8
              )
        else {
            return PreviousSnapshotRun(directory: directory)
        }
        return parse(manifest: contents, directory: directory)
    }

    /// Columns: timestamp, workspace, window_id, app_id, app_name,
    /// window_title, 3x layout, file, status — same shape the legacy shell
    /// script wrote, so its manifests parse too.
    static func parse(manifest: String, directory: URL? = nil) -> PreviousSnapshotRun {
        var run = PreviousSnapshotRun(directory: directory)
        for line in manifest.split(whereSeparator: \.isNewline).dropFirst() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count > 1 else {
                continue
            }
            run.workspaces.insert(String(fields[1]))

            guard fields.count > 10,
                  let status = SnapshotStatus(rawValue: String(fields[10])),
                  !fields[2].isEmpty,
                  !fields[9].isEmpty
            else {
                continue
            }
            run.entriesByWindowID[String(fields[2])] = Entry(
                fileURL: URL(fileURLWithPath: String(fields[9])),
                status: status
            )
        }
        return run
    }
}
