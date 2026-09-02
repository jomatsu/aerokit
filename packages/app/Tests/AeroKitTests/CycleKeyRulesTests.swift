import XCTest
@testable import ExposeFeature

final class CycleKeyRulesTests: XCTestCase {
    private func key(_ kind: CycleKeyInput.Kind, shifted: Bool = false) -> CycleKeyInput {
        .key(kind, shifted: shifted)
    }

    func testHotKeyKeyDownAdvances() {
        XCTAssertEqual(CycleKeyRules.action(for: key(.hotKey)), .advance)
    }

    func testShiftedHotKeyRetreats() {
        XCTAssertEqual(CycleKeyRules.action(for: key(.hotKey, shifted: true)), .retreat)
    }

    func testArrowsMove() {
        XCTAssertEqual(CycleKeyRules.action(for: key(.rightArrow)), .advance)
        XCTAssertEqual(CycleKeyRules.action(for: key(.leftArrow)), .retreat)
    }

    func testEscapeCancels() {
        XCTAssertEqual(CycleKeyRules.action(for: key(.escape)), .cancel)
    }

    func testUnrelatedKeysSwallowed() {
        XCTAssertEqual(CycleKeyRules.action(for: key(.other)), .swallow)
        XCTAssertEqual(CycleKeyRules.action(for: key(.other, shifted: true)), .swallow)
    }

    func testFlagsChangedReleaseCommits() {
        XCTAssertEqual(
            CycleKeyRules.action(for: .modifiersChanged(triggerHeld: false)),
            .commit
        )
    }

    func testFlagsChangedWhileHeldPassesThrough() {
        XCTAssertEqual(
            CycleKeyRules.action(for: .modifiersChanged(triggerHeld: true)),
            .pass
        )
    }

    func testShiftAloneDoesNotHoldOrCommit() {
        // ⇧ released while the trigger modifiers (⌥) are still held: the
        // trigger is unchanged, so nothing commits and the event passes.
        XCTAssertEqual(
            CycleKeyRules.action(for: .modifiersChanged(triggerHeld: true)),
            .pass
        )
    }
}
