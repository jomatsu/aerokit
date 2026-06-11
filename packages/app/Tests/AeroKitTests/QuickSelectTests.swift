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
            XCTAssertEqual(character.flatMap(QuickSelect.index(for:)), index)
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
}
