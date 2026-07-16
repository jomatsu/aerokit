import AeroKitCore
import Foundation

private let log = AppLog(category: "switcher")

/// One-time move of the snapshot tree out of ~/Pictures (a user-visible
/// folder holding window captures and titles) into Application Support.
/// Idempotent: two stat calls per launch once the move has happened.
public enum SnapshotLocationMigration {
    public static func migrateIfNeeded(
        configuration: SwitcherConfiguration = SwitcherConfiguration(),
        fileManager: FileManager = .default
    ) {
        let legacy = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/AeroSpace Workspaces", isDirectory: true)
        let destination = URL(fileURLWithPath: configuration.snapshotRootPath, isDirectory: true)
        guard fileManager.fileExists(atPath: legacy.path),
              !fileManager.fileExists(atPath: destination.path)
        else {
            return
        }
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: legacy, to: destination)
        } catch {
            // Next refresh simply starts fresh in the new location; the old
            // tree stays where the user can still delete it.
            log.error("moving snapshots to Application Support failed: \(error)")
        }
    }
}
