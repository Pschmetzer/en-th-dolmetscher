import XCTest
@testable import Dolmetscher

/// Fehlerbehebungen aus IDEEN.md „Zuerst angehen“ (#515–#522).
final class FixTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        let f = dir.appendingPathComponent("history.json")
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: f.path)
        try? FileManager.default.removeItem(at: dir)
    }

    // #515
    func testStoreDistinguishesMissingUnreadableCorrupt() throws {
        let s = JSONStore(dir: dir)
        guard case .missing = s.load([Entry].self, "history.json") else { return XCTFail("missing") }
        XCTAssertTrue(s.store([Entry(src: .en, dst: .th, text: "a")], "history.json"))
        XCTAssertEqual(s.load([Entry].self, "history.json").value?.count, 1)
        try Data("{kaputt".utf8).write(to: s.url("broken.json"))
        guard case .corrupt = s.load([Entry].self, "broken.json") else { return XCTFail("corrupt") }
        // nicht lesbar (wie Datenschutzklasse bei gesperrtem Gerät): Rechte entziehen
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: s.url("history.json").path)
        guard case .unreadable = s.load([Entry].self, "history.json") else { return XCTFail("unreadable") }
    }

    @MainActor
    func testUnreadableHistoryIsNeverOverwritten() throws {
        let s = JSONStore(dir: dir)
        let old = (0..<3).map { Entry(src: .en, dst: .th, text: "alt \($0)") }
        s.store(old, "history.json")
        let path = s.url("history.json").path
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        let m = InterpreterModel(files: s)
        m.historyDays = 30
        XCTAssertTrue(m.isHistoryBlocked)
        XCTAssertTrue(m.entries.isEmpty)
        m.persist()   // darf die Datei nicht mit der leeren Liste ersetzen
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        XCTAssertEqual(s.load([Entry].self, "history.json").value?.map(\.text), old.map(\.text))
        // nach dem Entsperren: nachladen und wieder speichern
        m.reloadIfBlocked()
        XCTAssertFalse(m.isHistoryBlocked)
        XCTAssertEqual(m.entries.map(\.text), old.map(\.text))
    }

    @MainActor
    func testCorruptHistoryIsSetAside() throws {
        let s = JSONStore(dir: dir)
        try Data("{kaputt".utf8).write(to: s.url("history.json"))
        let m = InterpreterModel(files: s)
        XCTAssertFalse(m.isHistoryBlocked)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("history.json.corrupt-") }, "\(names)")
    }

    // #516
    func testMyMemoryErrorIsNotATranslation() {
        let ok = #"{"responseData":{"translatedText":"Hallo"},"responseStatus":200}"#
        let quota = #"{"responseData":{"translatedText":"MYMEMORY WARNING: YOU USED ALL AVAILABLE FREE TRANSLATIONS FOR TODAY"},"responseStatus":429}"#
        let tooLong = #"{"responseData":{"translatedText":"QUERY LENGTH LIMIT EXCEEDED. MAX ALLOWED QUERY : 500 CHARS"},"responseStatus":"403"}"#
        let asString = #"{"responseData":{"translatedText":"Hallo"},"responseStatus":"200"}"#
        XCTAssertEqual(MyMemory.parse(Data(ok.utf8)), "Hallo")
        XCTAssertNil(MyMemory.parse(Data(quota.utf8)))
        XCTAssertNil(MyMemory.parse(Data(tooLong.utf8)))
        XCTAssertEqual(MyMemory.parse(Data(asString.utf8)), "Hallo")
        XCTAssertTrue(MyMemory.fits(String(repeating: "a", count: 500)))
        XCTAssertFalse(MyMemory.fits(String(repeating: "ก", count: 200)))   // 600 Byte
    }

    // #517
    func testBahtAmountParsing() {
        XCTAssertEqual(AmountParser.parse("1,200"), 1200)
        XCTAssertEqual(AmountParser.parse("12,000"), 12000)
        XCTAssertEqual(AmountParser.parse("1,200,000"), 1_200_000)
        XCTAssertEqual(AmountParser.parse("1,200.50"), 1200.5)
        XCTAssertEqual(AmountParser.parse("1.200,50"), 1200.5)
        XCTAssertEqual(AmountParser.parse("1.200"), 1200)
        XCTAssertEqual(AmountParser.parse("12,5"), 12.5)
        XCTAssertEqual(AmountParser.parse("12.5"), 12.5)
        XCTAssertEqual(AmountParser.parse("0.026"), 0.026)
        XCTAssertEqual(AmountParser.parse("฿ 350"), 350)
        XCTAssertEqual(AmountParser.parse("100"), 100)
        XCTAssertNil(AmountParser.parse(""))
        XCTAssertNil(AmountParser.parse("abc"))
    }

    // #518
    func testUndoBufferExpires() {
        var u = UndoBuffer<[Int]>()
        let t0 = Date()
        u.keep([1, 2], now: t0, seconds: 8)
        XCTAssertTrue(u.available(at: t0.addingTimeInterval(5)))
        XCTAssertEqual(u.take(at: t0.addingTimeInterval(5)), [1, 2])
        XCTAssertNil(u.take(at: t0.addingTimeInterval(6)))   // nur einmal
        u.keep([3], now: t0, seconds: 8)
        XCTAssertNil(u.take(at: t0.addingTimeInterval(9)))   // zu spät
    }

    @MainActor
    func testClearCanBeUndone() {
        let m = InterpreterModel(files: JSONStore(dir: dir))
        m.historyDays = 30
        m.submit("Hello", speak: false)
        m.submit("ขอบคุณ", speak: false)
        let before = m.entries.map(\.text)
        m.clear()
        XCTAssertTrue(m.entries.isEmpty)
        XCTAssertTrue(m.canUndoClear)
        m.undoClear()
        XCTAssertEqual(m.entries.map(\.text), before)
        XCTAssertFalse(m.canUndoClear)
    }

    // #521
    func testCircuitBreaker() {
        var b = CircuitBreaker(cooldown: 20)
        let t0 = Date()
        XCTAssertTrue(b.allows(at: t0))
        b.failed(at: t0)
        XCTAssertFalse(b.allows(at: t0.addingTimeInterval(5)))
        XCTAssertTrue(b.allows(at: t0.addingTimeInterval(21)))
        b.failed(at: t0)
        b.succeeded()
        XCTAssertTrue(b.allows(at: t0))
    }

    // #522
    func testOnlineTranslationDefaultsOff() {
        let d = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        XCTAssertFalse(InterpreterModel.allowOnlineSetting(d))
        d.set(true, forKey: "allowOnline")
        XCTAssertTrue(InterpreterModel.allowOnlineSetting(d))
    }

    func testPrivacyManifestDeclaresUserContent() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Dolmetscher/PrivacyInfo.xcprivacy")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        let types = (plist?["NSPrivacyCollectedDataTypes"] as? [[String: Any]])?.compactMap { $0["NSPrivacyCollectedDataType"] as? String }
        XCTAssertEqual(types, ["NSPrivacyCollectedDataTypeOtherUserContent"])
    }

    // Thai-Höflichkeit nur bei Ziel Thai (nicht mehr „Quelle Englisch“)
    func testPolitenessOnlyForThaiTarget() {
        XCTAssertEqual(Entry(src: .de, dst: .th, text: "x").target, .th)
        XCTAssertEqual(Entry(src: .th, dst: .de, text: "x").target, .de)
    }
}
