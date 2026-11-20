import XCTest
@testable import Dolmetscher

final class Round21Tests: XCTestCase {
    func testBillSplit() {
        let r = BillSplit.split(bill: 1000, tipPercent: 10, people: 3)
        XCTAssertEqual(r, BillSplit.Result(tip: 100, total: 1100, perPerson: 367))
        XCTAssertEqual(BillSplit.split(bill: 250, tipPercent: 0, people: 0)?.perPerson, 250)   // 0 Personen = 1
        XCTAssertNil(BillSplit.split(bill: -1, tipPercent: 10, people: 2))
        XCTAssertNil(BillSplit.split(bill: .nan, tipPercent: 10, people: 2))
        XCTAssertNil(BillSplit.split(bill: 100, tipPercent: 500, people: 2))
        XCTAssertNil(BillSplit.split(bill: 1e12, tipPercent: 10, people: 2))
    }

    func testUnits() {
        XCTAssertEqual(UnitConvert.toImperial(30, .temperature), 86, accuracy: 0.001)
        XCTAssertEqual(UnitConvert.toMetric(86, .temperature), 30, accuracy: 0.001)
        XCTAssertEqual(UnitConvert.toImperial(10, .distance), 6.21371, accuracy: 0.0001)
        XCTAssertEqual(UnitConvert.toMetric(UnitConvert.toImperial(7, .weight), .weight), 7, accuracy: 0.0001)
        XCTAssertEqual(UnitConvert.line(30, kind: .temperature, toImperial: true), "30 °C = 86 °F")
        XCTAssertNil(UnitConvert.line(.infinity, kind: .weight, toImperial: true))
    }

    func testThaiClock() {
        XCTAssertEqual(ThaiClock.spoken(hour: 14, minute: 30), "บ่ายสองโมงครึ่ง")
        XCTAssertEqual(ThaiClock.spoken(hour: 13, minute: 0), "บ่ายโมง")
        XCTAssertEqual(ThaiClock.spoken(hour: 12, minute: 0), "เที่ยง")
        XCTAssertEqual(ThaiClock.spoken(hour: 0, minute: 0), "เที่ยงคืน")
        XCTAssertEqual(ThaiClock.spoken(hour: 3, minute: 0), "ตีสาม")
        XCTAssertEqual(ThaiClock.spoken(hour: 7, minute: 15), "เจ็ดโมงเช้าสิบห้านาที")
        XCTAssertEqual(ThaiClock.spoken(hour: 17, minute: 0), "ห้าโมงเย็น")
        XCTAssertEqual(ThaiClock.spoken(hour: 20, minute: 21), "สองทุ่มยี่สิบเอ็ดนาที")
        XCTAssertNil(ThaiClock.spoken(hour: 24, minute: 0))
        XCTAssertNil(ThaiClock.spoken(hour: 5, minute: 60))
        for h in 0..<24 { for m in [0, 1, 30, 59] { XCTAssertNotNil(ThaiClock.spoken(hour: h, minute: m)) } }
    }

    func testPhoneDigits() {
        XCTAssertEqual(PhoneDigits.spoken("081-234"), "ศูนย์ แปด หนึ่ง  สอง สาม สี่")
        XCTAssertEqual(PhoneDigits.spoken("๐๘"), "ศูนย์ แปด")
        XCTAssertNil(PhoneDigits.spoken("abc"))
        XCTAssertNil(PhoneDigits.spoken(String(repeating: "1", count: 21)))
    }

    func testAmountParserRejectsNonFinite() {
        XCTAssertNil(AmountParser.parse("nan"))
        XCTAssertNil(AmountParser.parse("inf"))
        XCTAssertNil(AmountParser.parse("infinity"))
        XCTAssertEqual(AmountParser.parse("1,200"), 1200)
    }

    func testExportCleanup() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "r21-" + UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        for n in ["Dolmetscher-2026-03-10.csv", "Dolmetscher-2026-03-11.csv", "other.csv", "Dolmetscher-notes.txt"] {
            fm.createFile(atPath: dir.appending(path: n).path, contents: Data("x".utf8))
        }
        XCTAssertEqual(ExportCleanup.purge(in: dir), 2)
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: dir.path)), ["other.csv", "Dolmetscher-notes.txt"])
    }

    func testTranslatorUsesNonPersistentSession() {
        let c = Translator.privateSession.configuration
        XCTAssertNil(c.urlCache)
        XCTAssertEqual(c.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertFalse(c.httpShouldSetCookies)
    }

    func testTextsCompleteInAllLanguages() {
        let langs = ["de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id"]
        XCTAssertFalse(L10n.round21.isEmpty)
        for (key, row) in L10n.round21 {
            XCTAssertEqual(Set(row.keys), Set(langs), key)
            XCTAssertTrue(row.values.allSatisfy { !$0.isEmpty }, key)
            XCTAssertTrue(row.values.allSatisfy { $0.components(separatedBy: "%d").count == (row["en"] ?? "").components(separatedBy: "%d").count }, key)
        }
        for k in UnitConvert.Kind.allCases { XCTAssertNotNil(L10n.round21[k.textKey], k.textKey) }
        for k in ["trv_title", "trv_tip_split", "trv_people", "trv_phone", "trv_time", "trv_units"] { XCTAssertNotNil(L10n.round21[k], k) }
    }
}

final class Round21StorageTests: XCTestCase {
    func testPruneCopiesKeepsNewest() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "r21s-" + UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let store = JSONStore(dir: dir)
        for t in [100, 200, 300, 400, 500] { fm.createFile(atPath: dir.appending(path: "history.json.bak-\(t)").path, contents: Data("x".utf8)) }
        fm.createFile(atPath: dir.appending(path: "history.json").path, contents: Data("[]".utf8))
        store.pruneCopies("history.json", marker: ".bak-", keep: 2)
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: dir.path)), ["history.json", "history.json.bak-500", "history.json.bak-400"])
    }

    func testLossyLoadMakesBoundedPrivateBackups() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "r21l-" + UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let store = JSONStore(dir: dir)
        try Data(#"[1, "x", 3]"#.utf8).write(to: dir.appending(path: "n.json"))
        guard case .ok(let rows) = store.loadLossy(Int.self, "n.json") else { return XCTFail("not ok") }
        XCTAssertEqual(rows, [1, 3])
        let baks = try fm.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("n.json.bak-") }
        XCTAssertEqual(baks.count, 1)
        let v = try dir.appending(path: baks[0]).resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(v.isExcludedFromBackup, true)
    }
}

final class Round21LearnTests: XCTestCase {
    func testDismissedListIsCapped() {
        var d = LeitnerDeck()
        for i in 0..<(LeitnerDeck.maxDismissed + 40) { d.dismiss("id-\(i)") }
        XCTAssertEqual(d.dismissed?.count, LeitnerDeck.maxDismissed)
        XCTAssertEqual(d.dismissed?.last, "id-\(LeitnerDeck.maxDismissed + 39)")
        XCTAssertFalse(d.dismissed?.contains("id-0") ?? true)
    }
}
