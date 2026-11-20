import XCTest
@testable import DolmetscherLogic

final class QuickPhraseImportTests: XCTestCase {
    func testMergeSkipsDuplicatesAndBlank() {
        let r = QuickPhraseImport.merge(existing: "Hello\nThanks", imported: "hello\r\n\r\nWater please\nThanks")
        XCTAssertEqual(r, "Hello\nThanks\nWater please")
    }
}
