import XCTest
@testable import SwipeFeature

final class WorkspaceChangeFlashTests: XCTestCase {
    private let now = ContinuousClock.Instant.now

    func testShowsWithoutPriorOwnCommit() {
        let shows = WorkspaceChangeFlash.shouldShow(gestureActive: false, lastOwnCommit: nil, now: now)
        XCTAssertTrue(shows)
    }

    func testSuppressedWhileGestureOwnsThePanel() {
        let shows = WorkspaceChangeFlash.shouldShow(gestureActive: true, lastOwnCommit: nil, now: now)
        XCTAssertFalse(shows)
    }

    func testSuppressedWithinWindowAfterOwnCommit() {
        let commit = now - WorkspaceChangeFlash.ownCommitSuppression
        let shows = WorkspaceChangeFlash.shouldShow(gestureActive: false, lastOwnCommit: commit, now: now)
        XCTAssertFalse(shows)
    }

    func testShowsAfterSuppressionWindowPasses() {
        let commit = now - WorkspaceChangeFlash.ownCommitSuppression - .milliseconds(1)
        let shows = WorkspaceChangeFlash.shouldShow(gestureActive: false, lastOwnCommit: commit, now: now)
        XCTAssertTrue(shows)
    }

    func testSnippetEmbedsExecutablePathAndInvocation() {
        let snippet = WorkspaceChangeFlash.tomlSnippet(
            executablePath: "/Applications/AeroKit.app/Contents/MacOS/AeroKit"
        )
        XCTAssertEqual(
            snippet,
            "exec-on-workspace-change = ['/Applications/AeroKit.app/Contents/MacOS/AeroKit', '--workspace-changed']"
        )
    }
}
