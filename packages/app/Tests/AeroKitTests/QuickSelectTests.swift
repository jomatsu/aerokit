import XCTest
@testable import ExposeFeature

final class QuickSelectTests: XCTestCase {
    func testLabelsAreDigitsThenLetters() {
        XCTAssertEqual(QuickSelect.label(forIndex: 0), "1")
        XCTAssertEqual(QuickSelect.label(forIndex: 8), "9")
        XCTAssertEqual(QuickSelect.label(forIndex: 9), "A")
        XCTAssertEqual(QuickSelect.label(forIndex: 34), "Z")
    }

    func testLabelIsNilOutsideAddressableRange() {
        XCTAssertNil(QuickSelect.label(forIndex: -1))
        XCTAssertNil(QuickSelect.label(forIndex: 35))
    }

    func testIndexRoundTripsEveryLabel() {
        for index in 0 ..< 35 {
            let label = QuickSelect.label(forIndex: index)
            let character = try? XCTUnwrap(label?.first)
            XCTAssertEqual(character.flatMap { QuickSelect.index(for: $0) }, index)
        }
    }

    func testIndexAcceptsLowercaseLetters() {
        XCTAssertEqual(QuickSelect.index(for: "a"), 9)
        XCTAssertEqual(QuickSelect.index(for: "z"), 34)
    }

    func testIndexRejectsUnboundCharacters() {
        XCTAssertNil(QuickSelect.index(for: "0"))
        XCTAssertNil(QuickSelect.index(for: " "))
        XCTAssertNil(QuickSelect.index(for: "-"))
        XCTAssertNil(QuickSelect.index(for: "あ"))
    }

    func testExcludedKeyIsCarvedOutOfTheSequence() {
        XCTAssertEqual(QuickSelect.label(forIndex: 4, excluding: "5"), "6")
        XCTAssertNil(QuickSelect.index(for: "5", excluding: "5"))
        XCTAssertEqual(QuickSelect.index(for: "6", excluding: "5"), 4)

        XCTAssertEqual(QuickSelect.label(forIndex: 33, excluding: "5"), "Z")
        XCTAssertNil(QuickSelect.label(forIndex: 34, excluding: "5"), "34 keys remain after the carve-out")
    }

    func testExclusionMatchesCaseInsensitively() {
        XCTAssertEqual(QuickSelect.label(forIndex: 15, excluding: "g"), "H")
        XCTAssertNil(QuickSelect.index(for: "G", excluding: "g"))
        XCTAssertEqual(QuickSelect.index(for: "h", excluding: "G"), 15)
    }

    func testExclusionOutsideTheSequenceChangesNothing() {
        XCTAssertEqual(QuickSelect.label(forIndex: 0, excluding: "0"), "1")
        XCTAssertEqual(QuickSelect.label(forIndex: 34, excluding: "0"), "Z")
        XCTAssertEqual(QuickSelect.index(for: "a", excluding: "0"), 9)
    }
}
