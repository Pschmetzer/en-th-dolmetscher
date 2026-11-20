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

final class Round24Tests: XCTestCase {
    func testPreRollKeepsOnlyNewestWindowInOrder() {
        var p = FeedPreRoll<Int>(maxSeconds: 0.5)
        for i in 1...10 { p.push(i, dur: 0.1) }
        XCTAssertLessThanOrEqual(p.seconds, 0.5 + 1e-9)
        XCTAssertEqual(p.drain(), [6, 7, 8, 9, 10])
        XCTAssertEqual(p.count, 0)
        XCTAssertEqual(p.seconds, 0)
    }

    func testPreRollKeepsAtLeastOneOversizedItem() {
        var p = FeedPreRoll<Int>(maxSeconds: 0.1)
        p.push(1, dur: 1)
        XCTAssertEqual(p.drain(), [1])
    }

    /// Die Zuführung folgt dem Gate: Stille -> Vorlauf; Sprachbeginn -> Vorlauf plus Puffer; Ende -> Puffer.
    func testFeedDecisionFollowsGate() {
        var gate = VoiceGate(pause: 0.3)
        var pre = FeedPreRoll<Int>(maxSeconds: 0.7)
        var fed: [Int] = []
        let loud: Float = 0.2, quiet: Float = 0.001
        var seq: [(Float, Int)] = []
        for i in 0..<30 { seq.append((quiet, i)) }          // 3 s Stille
        for i in 30..<40 { seq.append((loud, i)) }          // 1 s Sprache
        for i in 40..<60 { seq.append((quiet, i)) }         // 2 s Stille
        for (rms, id) in seq {
            let e = gate.step(rms: rms, dur: 0.1)
            if e == .started { fed += pre.drain() }
            if gate.inUtterance || e == .ended { fed.append(id) } else { pre.push(id, dur: 0.1) }
        }
        XCTAssertTrue(fed.count < seq.count / 2, "Stille darf nicht gefüttert werden: \(fed.count)")
        XCTAssertTrue(fed.contains(30), "erster Sprachpuffer fehlt")
        XCTAssertTrue(fed.contains(25), "Vorlauf fehlt")      // 0,7 s vor dem Sprachbeginn (Puffer 23...29)
        XCTAssertEqual(fed, fed.sorted(), "Reihenfolge")
        XCTAssertFalse(fed.contains(5), "frühe Stille wurde gefüttert")
        XCTAssertFalse(fed.contains(59))
    }
}
