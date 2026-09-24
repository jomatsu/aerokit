import XCTest
@testable import ExposeFeature

final class CycleKeyRulesTests: XCTestCase {
    func testHotKeyKeyDownAdvances() {
        XCTAssertEqual(CycleKeyRules.action(for: .hotKey), .advance)
    }

    func testShiftedHotKeyRetreats() {
        XCTAssertEqual(CycleKeyRules.action(for: .hotKey, shifted: true), .retreat)
    }

    func testArrowsMove() {
        XCTAssertEqual(CycleKeyRules.action(for: .rightArrow), .advance)
        XCTAssertEqual(CycleKeyRules.action(for: .leftArrow), .retreat)
    }

    func testEscapeCancels() {
        XCTAssertEqual(CycleKeyRules.action(for: .escape), .cancel)
    }

    func testUnrelatedKeysSwallowed() {
        XCTAssertEqual(CycleKeyRules.action(for: .other), .swallow)
        XCTAssertEqual(CycleKeyRules.action(for: .other, shifted: true), .swallow)
    }
}
