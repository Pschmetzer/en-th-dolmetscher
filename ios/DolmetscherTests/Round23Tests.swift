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
