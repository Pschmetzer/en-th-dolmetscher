import AVFoundation
import XCTest
@testable import Dolmetscher

/// Google antwortet nach `googleDelay`, MyMemory sofort; zählt die Anfragen je Host.
final class HedgeProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var googleDelay = 3.0
    nonisolated(unsafe) static var requests: [URLRequest] = []
    private static let lock = NSLock()
    private var work: DispatchWorkItem?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var req = request
        if req.httpBody == nil, let s = req.httpBodyStream {
            s.open(); defer { s.close() }
            var d = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; d.append(buf, count: n) }
            req.httpBody = d
        }
        Self.lock.lock(); Self.requests.append(req); Self.lock.unlock()
        let google = req.url?.host == "translate.googleapis.com"
        let body = google ? Data(#"[[["จากกูเกิล","x"]]]"#.utf8)
                          : Data(#"{"responseStatus":200,"responseData":{"translatedText":"จากมายเมโมรี"}}"#.utf8)
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            self.client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        work = item
        DispatchQueue.global().asyncAfter(deadline: .now() + (google ? Self.googleDelay : 0), execute: item)
    }
    override func stopLoading() { work?.cancel() }

    static func hosts() -> [String] { lock.lock(); defer { lock.unlock() }; return requests.compactMap { $0.url?.host } }
    static func reset() { lock.lock(); requests = []; lock.unlock() }
}

final class Round30Tests: XCTestCase {
    private func hedgeTranslator() -> Translator {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [HedgeProtocol.self]
        return Translator(http: URLSession(configuration: c), isOnline: { true }, useApple: false)
    }

    // MARK: Übersetzer

    func testSlowGoogleIsOvertakenByMyMemory() async throws {
        HedgeProtocol.reset(); HedgeProtocol.googleDelay = 3
        let t0 = Date()
        let r = try await hedgeTranslator().translate("Thanks", from: .en, to: .th, allowOnline: true)
        XCTAssertEqual(r.provider, "mymemory")
        XCTAssertLessThan(Date().timeIntervalSince(t0), 2.9, "MyMemory startet nach hedgeDelay parallel, statt auf Google zu warten")
        XCTAssertEqual(Set(HedgeProtocol.hosts()), ["translate.googleapis.com", "api.mymemory.translated.net"])
    }

    func testFastGoogleNeverCallsMyMemory() async throws {
        HedgeProtocol.reset(); HedgeProtocol.googleDelay = 0
        let r = try await hedgeTranslator().translate("Thanks", from: .en, to: .th, allowOnline: true)
        XCTAssertEqual(r.provider, "google")
        try await Task.sleep(for: .seconds(Translator.OnlineTiming.hedgeDelay + 0.5))
        XCTAssertEqual(HedgeProtocol.hosts(), ["translate.googleapis.com"], "schnelle Antwort: kein zweiter Dienst, kein Textabfluss")
    }

    func testMyMemoryUsesPostWithoutTextInURL() async throws {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        StubProtocol.requests = []
        StubProtocol.handler = { req in
            req.url?.host == "translate.googleapis.com" ? (500, Data()) :
                (200, Data(#"{"responseStatus":200,"responseData":{"translatedText":"ขอบคุณ"}}"#.utf8))
        }
        defer { StubProtocol.handler = nil }
        let t = Translator(http: URLSession(configuration: c), isOnline: { true }, useApple: false)
        let r = try await t.translate("Secret sentence & more", from: .en, to: .th, allowOnline: true)
        XCTAssertEqual(r.provider, "mymemory")
        let mm = try XCTUnwrap(StubProtocol.requests.first { $0.url?.host == "api.mymemory.translated.net" })
        XCTAssertEqual(mm.httpMethod, "POST")
        XCTAssertNil(mm.url?.query, "kein Gesprächstext in der URL")
        let body = String(data: mm.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("q=Secret"), body)
        XCTAssertTrue(body.contains("langpair=en%7Cth") || body.contains("langpair=en|th"), body)
    }

    func testLongTextSkipsMyMemory() async {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        StubProtocol.requests = []
        StubProtocol.handler = { _ in (500, Data()) }
        defer { StubProtocol.handler = nil }
        let t = Translator(http: URLSession(configuration: c), isOnline: { true }, useApple: false)
        do { _ = try await t.translate(String(repeating: "ก", count: 200), from: .th, to: .en, allowOnline: true); XCTFail() }
        catch { XCTAssertEqual(error as? TranslateError, .failed) }
        XCTAssertTrue(StubProtocol.requests.allSatisfy { $0.url?.host == "translate.googleapis.com" })
    }

    func testRateLimitedWhenBothLimit() async {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        StubProtocol.handler = { _ in (429, Data("{}".utf8)) }
        defer { StubProtocol.handler = nil }
        let t = Translator(http: URLSession(configuration: c), isOnline: { true }, useApple: false)
        do { _ = try await t.translate("Hi", from: .en, to: .th, allowOnline: true); XCTFail() }
        catch { XCTAssertEqual(error as? TranslateError, .rateLimited) }
    }

    func testTimeoutsAreShortAndWithinSpeechBudget() {
        typealias O = Translator.OnlineTiming
        XCTAssertLessThanOrEqual(O.googleTimeout, 3)
        XCTAssertLessThan(O.hedgeDelay, O.googleTimeout)
        // schlimmster Fall: Apple-Zeitlimit, dann Google hängt, MyMemory startet nach dem Hedge
        let worst = Translator.appleTimeout + O.hedgeDelay + O.myMemoryTimeout
        XCTAssertLessThan(worst, SpeechTiming.produceTimeout)
    }

    func testPrivateSessionIsEphemeralWithShortResourceTimeout() {
        let c = Translator.privateSession.configuration
        XCTAssertNil(c.urlCache)
        XCTAssertNil(c.httpCookieStorage)
        XCTAssertFalse(c.waitsForConnectivity)
        XCTAssertEqual(c.timeoutIntervalForResource, Translator.OnlineTiming.resourceTimeout)
        XCTAssertLessThanOrEqual(c.timeoutIntervalForResource, 10)
    }

    func testSpeechRateBounds() {
        XCTAssertLessThan(SpeechRate.minRate, 1)
        XCTAssertGreaterThan(SpeechRate.maxRate, 1)
        XCTAssertLessThanOrEqual(SpeechRate.minRate + SpeechRate.step, SpeechRate.maxRate)
    }

    func testWithTimeoutReturnsNilOnHang() async {
        let r: Int? = await withTimeout(seconds: 0.2) { try? await Task.sleep(for: .seconds(5)); return 1 }
        XCTAssertNil(r)
        let ok: Int? = await withTimeout(seconds: 2) { 7 }
        XCTAssertEqual(ok, 7)
    }

    // MARK: Speicher

    private func tempStore() -> JSONStore {
        JSONStore(dir: FileManager.default.temporaryDirectory.appendingPathComponent("r30-\(UUID().uuidString)"))
    }

    func testStoreRoundTripLeavesNoTempFiles() throws {
        let s = tempStore()
        defer { try? FileManager.default.removeItem(at: s.dir) }
        XCTAssertTrue(s.store(["a", "b"], "list.json"))
        XCTAssertEqual(s.load([String].self, "list.json").value, ["a", "b"])
        XCTAssertTrue(s.store(["c"], "list.json"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: s.dir.path), ["list.json"])
    }

    func testStoreFailsCleanlyWhenFolderIsAFile() throws {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("r30-file-\(UUID().uuidString)")
        try Data("x".utf8).write(to: f)
        defer { try? FileManager.default.removeItem(at: f) }
        XCTAssertFalse(JSONStore(dir: f).store(["x"], "a.json"))
    }

    func testCorruptAndMissingAreDistinguished() throws {
        let s = tempStore()
        defer { try? FileManager.default.removeItem(at: s.dir) }
        if case .missing = s.load([String].self, "x.json") {} else { XCTFail("missing") }
        try FileManager.default.createDirectory(at: s.dir, withIntermediateDirectories: true)
        try Data("{kaputt".utf8).write(to: s.url("x.json"))
        if case .corrupt = s.load([String].self, "x.json") {} else { XCTFail("corrupt") }
        s.quarantine("x.json")
        if case .missing = s.load([String].self, "x.json") {} else { XCTFail("missing nach Quarantäne") }
    }

    func testRemoveOfMissingFileIsHarmlessAndPrunesKeepNewest() throws {
        let s = tempStore()
        defer { try? FileManager.default.removeItem(at: s.dir) }
        s.remove("gibt-es-nicht.json")
        try FileManager.default.createDirectory(at: s.dir, withIntermediateDirectories: true)
        for i in 1...6 { try Data("x".utf8).write(to: s.url("h.json.bak-\(i)")) }
        s.pruneCopies("h.json", marker: ".bak-")
        let left = try FileManager.default.contentsOfDirectory(atPath: s.dir.path).sorted()
        XCTAssertEqual(left, ["h.json.bak-4", "h.json.bak-5", "h.json.bak-6"])
        XCTAssertEqual(StorageLimits.keepCopies, 3)
    }

    func testLossyKeepsGoodEntriesAndSavesBackup() throws {
        struct Row: Codable, Equatable { var n: Int }
        let s = tempStore()
        defer { try? FileManager.default.removeItem(at: s.dir) }
        try FileManager.default.createDirectory(at: s.dir, withIntermediateDirectories: true)
        try Data(#"[{"n":1},{"n":"kaputt"},{"n":3}]"#.utf8).write(to: s.url("r.json"))
        XCTAssertEqual(s.loadLossy(Row.self, "r.json").value, [Row(n: 1), Row(n: 3)])
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: s.dir.path).contains { $0.hasPrefix("r.json.bak-") })
    }

    // MARK: Audio-Sitzung, Sprachausgabe

    func testSessionAttemptReportsFailureInsteadOfSwallowing() {
        struct Boom: Error {}
        let s = AVAudioSession.sharedInstance()
        XCTAssertFalse(s.attempt("test") { _ in throw Boom() })
        XCTAssertTrue(s.attempt("test") { _ in })
    }

    func testClearSpeechTimeoutFormulaUnchanged() {
        XCTAssertEqual(ClearSpeech.timeout(chars: 40, rate: 1, pauses: 0), 18, accuracy: 0.001)
        XCTAssertEqual(ClearSpeech.timeout(chars: 40, rate: 0.5, pauses: 2), 36 + 0.7, accuracy: 0.001)
        XCTAssertEqual(ClearSpeech.timeout(chars: 0, rate: 0.01, pauses: 0), 8 / 0.3, accuracy: 0.001)   // Untergrenze der Rate
    }

    func testSpeechTextBahtNormalisation() {
        XCTAssertEqual(SpeechText.normalize("฿120", lang: .en), "120 baht")
        XCTAssertEqual(SpeechText.normalize("120 ฿", lang: .th), "120 บาท")
    }

    // MARK: Whisper-Filter

    func testMultilingualOutroPhrasesAreJunk() {
        for s in ["ご視聴ありがとうございました", "시청해 주셔서 감사합니다", "谢谢观看", "Gracias por ver el video.",
                  "Merci d'avoir regardé cette vidéo !", "Terima kasih telah menonton", "Vielen Dank fürs Zuschauen"] {
            XCTAssertTrue(Hallucination.isJunk(s), s)
            XCTAssertNil(Hallucination.clean(s, duration: 3, rms: 0.05, compressionRatios: [1.2]), s)
        }
    }

    func testRealSentencesAreNotJunk() {
        for s in ["Thanks for listening to me", "Thank you for listening", "Thank you for watching my bag, I will be back in five minutes", "谢谢观看护我的包", "Gracias por ver a mi madre",
                  "ขอบคุณที่รับชมของผมนะครับ ผมจะกลับมา"] {
            XCTAssertFalse(Hallucination.isJunk(s), s)
        }
    }

    // MARK: Kurzbefehle

    func testIntentInputCleaning() {
        XCTAssertNil(IntentInput.clean("   \n"))
        XCTAssertEqual(IntentInput.clean("  hello \n"), "hello")
        XCTAssertEqual(IntentInput.clean(String(repeating: "a", count: 5000))?.count, IntentInput.maxChars)
    }

    // MARK: Übersetzungstexte

    private func placeholders(_ s: String) -> [String] {
        let rx = try! NSRegularExpression(pattern: #"%(?:\d\$)?[@df]|%\.\d+f"#)
        return rx.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range, in: s)!]) }.sorted()
    }

    /// Alle späten Runden (9, 13–30): jede Sprache vorhanden, nicht leer, gleiche Platzhalter wie Englisch, keine doppelten Schlüssel.
    func testLateRoundsCompleteInAllLanguages() {
        let rounds: [(String, [String: [String: String]])] = [("9", L10n.round9), ("13", L10n.round13), ("14", L10n.round14), ("15", L10n.round15),
            ("16", L10n.round16), ("17", L10n.round17), ("18", L10n.round18), ("19", L10n.round19), ("21", L10n.round21), ("25", L10n.round25), ("30", L10n.round30)]
        var seen = Set(L10n.table.keys).union(L10n.round4.keys).union(L10n.round5.keys).union(L10n.round6.keys).union(L10n.round7.keys).union(L10n.round8.keys)
        for (name, r) in rounds {
            XCTAssertTrue(seen.isDisjoint(with: r.keys), "Runde \(name): Schlüssel doppelt: \(seen.intersection(r.keys).sorted())")
            seen.formUnion(r.keys)
            for (key, row) in r {
                for lang in L10n.languages {
                    let text = row[lang] ?? ""
                    XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty, "Runde \(name) \(lang): \(key) fehlt")
                    XCTAssertEqual(placeholders(text), placeholders(row["en"] ?? ""), "Runde \(name) \(lang): \(key) Platzhalter")
                }
            }
        }
        XCTAssertTrue(seen.isSubset(of: L10n.allKeys), "allKeys kennt nicht alle Runden")
    }

    func testVoiceMissingHintFormats() {
        for lang in L10n.languages {
            let t = L10n.text("voice_missing", lang: lang)
            XCTAssertNotNil(t, lang)
            XCTAssertEqual(String(format: t ?? "", "Thai").contains("Thai"), true, lang)
        }
    }

    /// Kurzbefehle-Titel (Localizable.strings): in allen Oberflächensprachen die gleichen Schlüssel, nichts leer.
    func testIntentStringsHaveSameKeysEverywhere() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Dolmetscher")
        var all: [String: Set<String>] = [:]
        for lang in L10n.languages where lang != "en" {
            let u = app.appendingPathComponent("\(lang).lproj/Localizable.strings")
            let d = try XCTUnwrap(NSDictionary(contentsOf: u) as? [String: String], "\(lang): Localizable.strings fehlt/kaputt")
            XCTAssertFalse(d.values.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }, lang)
            all[lang] = Set(d.keys)
        }
        let first = try XCTUnwrap(all["de"])
        for (lang, keys) in all { XCTAssertEqual(keys, first, "\(lang) weicht ab") }
        for key in ["Start interpreting", "Say phrase", "Translate text", "Swap language pair"] { XCTAssertTrue(first.contains(key), key) }
    }

    func testWidgetStringsHaveSameKeysEverywhere() throws {
        let w = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("DolmetscherWidget")
        var all: [String: Set<String>] = [:]
        for lang in L10n.languages where lang != "en" {
            let u = w.appendingPathComponent("\(lang).lproj/Localizable.strings")
            let d = try XCTUnwrap(NSDictionary(contentsOf: u) as? [String: String], "\(lang): Widget-Localizable.strings fehlt/kaputt")
            XCTAssertFalse(d.values.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }, lang)
            all[lang] = Set(d.keys)
        }
        let first = try XCTUnwrap(all["de"])
        for (lang, keys) in all { XCTAssertEqual(keys, first, "\(lang) weicht ab") }
        for key in ["Stop interpreting", "Quick phrases", "Speak last translation"] { XCTAssertTrue(first.contains(key), key) }
    }

    /// `i18n/en.json` und `th.json` (Texte der Mac-/Web-Oberfläche): gleiche Schlüssel, gleiche {Platzhalter}.
    func testSharedI18nFilesAreInParity() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func load(_ n: String) throws -> [String: String] {
            let d = try Data(contentsOf: root.appendingPathComponent("i18n/\(n).json"))
            return try XCTUnwrap(try JSONSerialization.jsonObject(with: d) as? [String: String], n)
        }
        let en = try load("en"), th = try load("th")
        XCTAssertEqual(Set(en.keys), Set(th.keys), "Schlüssel weichen ab")
        let rx = try NSRegularExpression(pattern: #"\{\w*\}|%(?:\d\$)?[@dsf]"#)
        func ph(_ s: String) -> [String] { rx.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range, in: s)!]) }.sorted() }
        for (k, v) in en { XCTAssertEqual(ph(v), ph(th[k] ?? ""), "Platzhalter in \(k)") }
        for (k, v) in th { XCTAssertFalse(v.trimmingCharacters(in: .whitespaces).isEmpty, "th leer: \(k)") }
    }
}
