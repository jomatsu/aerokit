import AppKit
import XCTest
@testable import AeroKitCore

@MainActor
final class HoldToCommitDismissTests: XCTestCase {
    func testReleaseCommitsOnceAndCanBeRearmedByAKeyPress() throws {
        let dismissor = HoldToCommitDismiss(triggerFlags: .option, heldAtShow: true)
        var commits = 0
        dismissor.onModifierRelease = { commits += 1 }

        XCTAssertTrue(try dismissor.noteFlagsChanged(event(flags: [])))
        XCTAssertFalse(try dismissor.noteFlagsChanged(event(flags: [])))
        XCTAssertEqual(commits, 1)

        try dismissor.noteKeyEvent(event(flags: .option, type: .keyDown))
        XCTAssertTrue(try dismissor.noteFlagsChanged(event(flags: [])))
        XCTAssertEqual(commits, 2)
    }

    func testShiftChangesDoNotCommitWhileTriggerModifiersRemainHeld() throws {
        let dismissor = HoldToCommitDismiss(triggerFlags: [.option, .control], heldAtShow: true)
        var commits = 0
        dismissor.onModifierRelease = { commits += 1 }

        XCTAssertFalse(try dismissor.noteFlagsChanged(event(flags: [.option, .control, .shift])))
        XCTAssertFalse(try dismissor.noteFlagsChanged(event(flags: [.option, .control])))
        XCTAssertEqual(commits, 0)
        XCTAssertTrue(try dismissor.noteFlagsChanged(event(flags: .option)))
        XCTAssertEqual(commits, 1)
    }

    func testEndingSessionPreventsAStaleReleaseFromCommitting() throws {
        let dismissor = HoldToCommitDismiss(triggerFlags: .option, heldAtShow: true)
        var commits = 0
        dismissor.onModifierRelease = { commits += 1 }

        dismissor.endSession()

        XCTAssertFalse(try dismissor.noteFlagsChanged(event(flags: [])))
        XCTAssertEqual(commits, 0)
    }

    private func event(flags: NSEvent.ModifierFlags, type: NSEvent.EventType = .flagsChanged) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: KeyCode.tab
        ))
    }
}
