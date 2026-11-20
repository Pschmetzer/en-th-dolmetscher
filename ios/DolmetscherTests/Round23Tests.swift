import XCTest
@testable import Dolmetscher

final class Round23Tests: XCTestCase {
    func testRaceTimeoutReturnsEvenIfOperationIgnoresCancellation() async {
        let start = Date()
        await raceTimeout(seconds: 0.3) { await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in } }   // hängt für immer
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testRaceTimeoutReturnsEarlyWhenOperationFinishes() async {
        let start = Date()
        await raceTimeout(seconds: 5) { }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testForeignLanguageDetectedForUnspacedScripts() {
        let pair = LangPair(mine: .en, partner: .th)
        XCTAssertEqual(TypedLanguageCheck.foreign("これは日本語で書かれた長い文章です。", pair: pair), "ja")
        XCTAssertNil(TypedLanguageCheck.foreign("สวัสดีครับ ยินดีที่ได้รู้จักนะครับ", pair: pair))
        XCTAssertNil(TypedLanguageCheck.foreign("Entschuldigung", pair: pair))   // ein langes Wort bleibt unbeanstandet
    }
}

final class Round23CacheTests: XCTestCase {
    func testRenderCacheMatchesDirectComputation() {
        for _ in 0..<2 {   // zweiter Durchlauf trifft den Cache
            XCTAssertEqual(RenderCache.roman("สวัสดีครับ", .th), Romanizer.latin("สวัสดีครับ", .th))
            XCTAssertEqual(RenderCache.roman("hello", .en), Romanizer.latin("hello", .en))
            XCTAssertEqual(RenderCache.deviates("Where is the toilet", "Where is the hospital"),
                           BackCheck.deviates(original: "Where is the toilet", back: "Where is the hospital"))
        }
    }

    func testStoreCreatesMissingDirectoryOnWrite() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "r23-" + UUID().uuidString).appending(path: "sub")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let store = JSONStore(dir: dir)
        if case .missing = store.load([Int].self, "x.json") {} else { XCTFail("sollte fehlen") }
        XCTAssertTrue(store.store([1, 2], "x.json"))
        XCTAssertEqual(store.load([Int].self, "x.json").value, [1, 2])
    }
}
