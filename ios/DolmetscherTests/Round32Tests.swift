import XCTest
@testable import Dolmetscher

final class Round32Tests: XCTestCase {
    private func tempStore() -> JSONStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("r32-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return JSONStore(dir: dir)
    }

    // MARK: Schema

    func testMigrationStampsCurrentVersionAndKeepsData() {
        let s = tempStore()
        XCTAssertTrue(s.store(["a": 1], "favorites.json"))
        try? Data().write(to: s.url("x.tmp"))
        XCTAssertEqual(StorageSchema.version(s), 1)
        XCTAssertEqual(StorageSchema.migrate(s), StorageSchema.current)
        XCTAssertEqual(StorageSchema.version(s), StorageSchema.current)
        XCTAssertNotNil(s.load([String: Int].self, "favorites.json").value)
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.url("x.tmp").path))
    }

    func testMigrationIsIdempotentAndNeverDowngrades() {
        let s = tempStore()
        StorageSchema.migrate(s)
        XCTAssertEqual(StorageSchema.migrate(s), StorageSchema.current)
        s.store(["version": 99], StorageSchema.file)
        XCTAssertEqual(StorageSchema.migrate(s), 99)
        XCTAssertEqual(StorageSchema.version(s), 99)
    }

    func testMigrationSkipsFreshInstall() {
        let s = JSONStore(dir: FileManager.default.temporaryDirectory.appendingPathComponent("r32-missing-\(UUID().uuidString)"))
        XCTAssertEqual(StorageSchema.migrate(s), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.dir.path))
    }

    // MARK: Notrufnummern

    func testEmergencyNumbersPerCountry() {
        XCTAssertEqual(EmergencyNumbers.forRegion("th").ambulance, "1669")
        XCTAssertEqual(EmergencyNumbers.forRegion("DE").police, "110")
        XCTAssertEqual(EmergencyNumbers.forRegion("US").fire, "911")
        XCTAssertEqual(EmergencyNumbers.forRegion("XX"), EmergencyNumbers.fallback)
        XCTAssertEqual(EmergencyNumbers.forRegion(nil).police, "112")
        XCTAssertTrue(EmergencyNumbers.summary(EmergencyNumbers.forRegion("TH")).contains("1155"))
    }

    func testRegionMatching() {
        XCTAssertEqual(EmergencyNumbers.region(matching: "th"), "TH")
        XCTAssertEqual(EmergencyNumbers.region(matching: " Thailand "), "TH")
        XCTAssertEqual(EmergencyNumbers.region(matching: "Deutschland"), "DE")
        XCTAssertNil(EmergencyNumbers.region(matching: ""))
        XCTAssertNil(EmergencyNumbers.region(matching: "Atlantis"))
    }

    func testEveryTableEntryHasNumbers() {
        for (code, s) in EmergencyNumbers.table {
            XCTAssertEqual(s.region, code)
            XCTAssertFalse(s.police.isEmpty || s.ambulance.isEmpty || s.fire.isEmpty, code)
        }
    }

    // MARK: Taxi

    func testTaxiPhrasesFillPolitenessAndHaveThai() {
        for item in TaxiCard.items {
            XCTAssertTrue(item.th.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) }, item.id)
            XCTAssertFalse(TaxiCard.thai(item, female: false).contains("{"), item.id)
            XCTAssertFalse(item.roman.isEmpty)
        }
        XCTAssertEqual(Set(TaxiCard.items.map(\.id)).count, TaxiCard.items.count)
        XCTAssertTrue(TaxiCard.thai(TaxiCard.item("stop")!, female: true).hasSuffix("ค่ะ"))
        XCTAssertTrue(TaxiCard.thai(TaxiCard.item("stop")!, female: false).hasSuffix("ครับ"))
        XCTAssertNil(TaxiCard.item("nope"))
    }

    // MARK: Preise

    func testCountersAreBelowAskedRoundedAndDistinct() {
        let o = PriceHelper.counters(asked: 800).map(\.amount)
        XCTAssertEqual(o, [400, 520, 640])
        XCTAssertTrue(o.allSatisfy { $0 % 10 == 0 && $0 <= 800 })
        XCTAssertEqual(PriceHelper.counters(asked: 60).map(\.amount), [30, 40, 50])
        XCTAssertEqual(PriceHelper.counters(asked: 5).map(\.amount), [5])
        XCTAssertTrue(PriceHelper.counters(asked: 0).isEmpty)
        XCTAssertTrue(PriceHelper.counters(asked: -3).isEmpty)
        XCTAssertEqual(PriceHelper.thaiWords(100), "หนึ่งร้อยบาท")
    }

    // MARK: Wort-Lexikon

    func testWordTokensLongestMatch() {
        let t = WordLexicon.tokens("ไปสนามบิน ขอบคุณครับ")
        XCTAssertEqual(t.map(\.text), ["ไป", "สนามบิน", "ขอบคุณ", "ครับ"])
        XCTAssertEqual(t[1].entry?.meaning, "airport")
        XCTAssertEqual(t.map(\.id), [0, 1, 2, 3])
    }

    func testUnknownTextStaysTogetherAndPunctuationSplits() {
        let t = WordLexicon.tokens("xyz, ครับ")
        XCTAssertEqual(t.map(\.text), ["xyz", "ครับ"])
        XCTAssertNil(t[0].entry)
        XCTAssertTrue(WordLexicon.tokens("").isEmpty)
    }

    func testLexiconEntriesComplete() {
        for (k, e) in WordLexicon.entries { XCTAssertFalse(e.roman.isEmpty || e.meaning.isEmpty, k) }
    }

    // MARK: Bildschirmschutz

    func testShieldPolicy() {
        XCTAssertTrue(ScreenShieldPolicy.covers(captured: true, sensitive: true))
        XCTAssertFalse(ScreenShieldPolicy.covers(captured: false, sensitive: true))
        XCTAssertFalse(ScreenShieldPolicy.covers(captured: true, sensitive: false))
        XCTAssertFalse(ScreenShieldPolicy.covers(captured: true, sensitive: true, enabled: false))
    }

    // MARK: Live-Aktivität, Texte

    @MainActor func testStaleDateShorterWhenPaused() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(LiveActivityController.staleDate(now: now, status: .listening).timeIntervalSince(now), 20 * 60)
        XCTAssertEqual(LiveActivityController.staleDate(now: now, status: .paused).timeIntervalSince(now), 5 * 60)
        XCTAssertEqual(LiveActivityController.staleDate(now: now).timeIntervalSince(now), 20 * 60)
    }

    func testRound32TextsCompleteInAllLanguages() {
        for (key, byLang) in L10n.round32 {
            for l in WidgetTexts.languages { XCTAssertFalse((byLang[l] ?? "").isEmpty, "\(key) fehlt in \(l)") }
            XCTAssertNotNil(L10n.text(key, lang: "de"))
        }
        let placeholders = L10n.round32["r32_numbers_for"] ?? [:]
        for (l, v) in placeholders { XCTAssertTrue(v.contains("%@"), l) }
    }

    func testNewWidgetTextsComplete() {
        for key in ["w_listen", "w_listen_d", "w_emergency", "w_emergency_d", "w_taxi", "w_taxi_d"] {
            for l in WidgetTexts.languages { XCTAssertFalse((WidgetTexts.table[key]?[l] ?? "").isEmpty, "\(key) \(l)") }
        }
    }
}
