import XCTest
@testable import SwitcherFeature

final class WorkspaceNameTests: XCTestCase {
    func testSanitizedFileStemKeepsSafeWorkspaceNames() {
        XCTAssertEqual(WorkspaceName.sanitizedFileStem("1"), "1")
        XCTAssertEqual(WorkspaceName.sanitizedFileStem("Q"), "Q")
        XCTAssertEqual(WorkspaceName.sanitizedFileStem("dev.main-2"), "dev.main-2")
    }

    func testSanitizedFileStemReplacesUnsafeCharacters() {
        XCTAssertEqual(WorkspaceName.sanitizedFileStem("work space/2"), "work_space_2")
    }
}
