import XCTest
@testable import DolmetscherLogic

final class QuickInputTests: XCTestCase {
    func testPrepareFlattensWhitespace() {
        XCTAssertEqual(ClipboardLogic.prepare("  Hallo \n\n Welt\t!  "), "Hallo Welt !")
    }

    func testPrepareRejectsEmpty() {
        XCTAssertNil(ClipboardLogic.prepare(nil))
        XCTAssertNil(ClipboardLogic.prepare(" \n\t "))
    }

    func testPrepareTruncatesAtWordBoundary() {
        let text = String(repeating: "wort ", count: 400)
        let p = ClipboardLogic.prepare(text, limit: 100)!
        XCTAssertLessThanOrEqual(p.count, 100)
        XCTAssertTrue(p.hasSuffix("wort"))
        XCTAssertTrue(ClipboardLogic.wasTruncated(text, limit: 100))
        XCTAssertFalse(ClipboardLogic.wasTruncated("kurz", limit: 100))
    }

    func testPrepareHardCutWithoutSpaces() {
        let p = ClipboardLogic.prepare(String(repeating: "x", count: 500), limit: 50)!
        XCTAssertEqual(p.count, 50)
    }

    func testThaiTextKeptIntact() {
        XCTAssertEqual(ClipboardLogic.prepare("สวัสดีครับ"), "สวัสดีครับ")
    }

    func testSystemVoiceVolumeClamped() {
        XCTAssertEqual(VolumeLogic.systemVoice(2.0), 1)
        XCTAssertEqual(VolumeLogic.systemVoice(0), 0.1)
        XCTAssertEqual(VolumeLogic.systemVoice(0.5), 0.5)
        XCTAssertEqual(VolumeLogic.systemVoice(.nan), 1)
        XCTAssertTrue(VolumeLogic.exceedsSystemVoice(1.5))
        XCTAssertFalse(VolumeLogic.exceedsSystemVoice(1.0))
    }
}
