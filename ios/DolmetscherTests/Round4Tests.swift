import XCTest
@testable import Dolmetscher

/// Runde 4: reine Logik (Zahlwörter, Preise, Auto-Stopp, Stau, Vorbereitung, Satzbuch zuerst, Lexikon).
final class Round4Tests: XCTestCase {
    func testThaiNumberWordsRoundTrip() {
        for n in [0, 1, 10, 11, 20, 21, 99, 100, 101, 111, 350, 1_000, 1_200, 2_500, 10_001, 120_000, 999_999,
                  1_000_000, 1_200_000, 21_000_021, 100_000_000] {
            let w = ThaiNumber.words(n)!
            XCTAssertEqual(ThaiNumber.parse(w), n, w)
        }
        XCTAssertEqual(ThaiNumber.parse("สามร้อยห้าสิบ"), 350)
        XCTAssertEqual(ThaiNumber.parse("ร้อย"), 100)
        XCTAssertNil(ThaiNumber.parse("สวัสดี"))
        XCTAssertNil(ThaiNumber.parse("สองสาม"))   // zwei Ziffern ohne Stelle
        XCTAssertNil(ThaiNumber.parse(""))
    }

    func testPriceSpotter() {
        XCTAssertEqual(PriceSpotter.amounts(in: "ราคา ฿350 ครับ"), [350])
        XCTAssertEqual(PriceSpotter.amounts(in: "It costs 1,200 baht"), [1200])
        XCTAssertEqual(PriceSpotter.amounts(in: "๑๒๐ บาท"), [120])
        XCTAssertEqual(PriceSpotter.amounts(in: "สามร้อยห้าสิบบาทครับ"), [350])
        XCTAssertEqual(PriceSpotter.amounts(in: "Two coffees, 80 THB each"), [80])
        XCTAssertEqual(PriceSpotter.amounts(in: "Where is the toilet?"), [])
        XCTAssertEqual(PriceSpotter.amounts(in: "฿50 · 50 บาท"), [50])   // doppelt nur einmal
        let line = PriceSpotter.line([350], rate: 0.026, code: "EUR", locale: Locale(identifier: "de"))
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("9,10"), line!)
        XCTAssertNil(PriceSpotter.line([350], rate: 0, code: "EUR", locale: Locale(identifier: "de")))
    }

    func testIdlePolicyWarnsBeforeStopping() {
        let limit = IdlePolicy.limit(minutes: 10, lowPower: false)
        XCTAssertEqual(limit, 600)
        XCTAssertEqual(IdlePolicy.state(idle: 100, limit: limit), .ok)
        XCTAssertEqual(IdlePolicy.state(idle: 575, limit: limit), .warn)
        XCTAssertEqual(IdlePolicy.state(idle: 600, limit: limit), .stop)
        XCTAssertNil(IdlePolicy.limit(minutes: 0, lowPower: true))
        XCTAssertEqual(IdlePolicy.limit(minutes: 30, lowPower: true), 180)   // Energiesparmodus: kürzer
        XCTAssertEqual(IdlePolicy.state(idle: 9_999, limit: nil), .ok)
    }

    func testEnergyPolicy() {
        XCTAssertTrue(EnergyPolicy.hot(.serious))
        XCTAssertTrue(EnergyPolicy.hot(.critical))
        XCTAssertFalse(EnergyPolicy.hot(.fair))
        let p = LangPair.standard
        XCTAssertEqual(EnergyPolicy.coolMode(pair: p, lastSpoken: .en), .partner)   // nach Englisch kommt Thai
        XCTAssertEqual(EnergyPolicy.coolMode(pair: p, lastSpoken: .th), .mine)
        XCTAssertEqual(EnergyPolicy.coolMode(pair: p, lastSpoken: nil), .mine)
    }

    func testSpeechBacklog() {
        XCTAssertFalse(SpeechBacklog.skip(seq: 5, latest: 5))
        XCTAssertFalse(SpeechBacklog.skip(seq: 4, latest: 5))
        XCTAssertTrue(SpeechBacklog.skip(seq: 3, latest: 5))
    }

    func testReadinessReport() {
        var r = ReadinessReport()
        XCTAssertFalse(r.allReady)
        XCTAssertEqual(r.missing, ReadinessReport.Item.allCases)
        r.recognizerMine = .installed; r.recognizerPartner = .installed
        r.translation = ReadinessReport.combine(.installed, .installed)
        r.voiceMine = true; r.voicePartner = true; r.micAllowed = true
        XCTAssertTrue(r.allReady)
        XCTAssertEqual(ReadinessReport.combine(.installed, .downloadable), .downloadable)
        XCTAssertEqual(ReadinessReport.combine(.installed, .unsupported), .unsupported)
    }

    func testPhraseDataIsConsistent() {
        let all = PhraseData.all
        XCTAssertGreaterThanOrEqual(all.count, 70)
        XCTAssertEqual(Set(all.map(\.en)).count, all.count, "doppelte en-Schlüssel stören SwiftUI-Listen")
        let cats = Set(PhraseData.categories.map(\.key))
        for p in all {
            XCTAssertTrue(cats.contains(p.category), p.en)
            XCTAssertFalse((p.de ?? "").isEmpty, "deutsche Glosse fehlt: \(p.en)")
            XCTAssertFalse(p.roman.isEmpty, "Umschrift fehlt: \(p.en)")
            for ph in ["{p}", "{q}", "{i}"] {
                XCTAssertEqual(p.th.contains(ph), p.roman.contains(ph), "\(ph) in Thai und Umschrift: \(p.en)")
            }
        }
        XCTAssertEqual(Phrasebook.builtIn.count, all.count)
        XCTAssertEqual(PhraseData.fill("{i}ไม่เข้าใจ{p}", female: true), "ฉันไม่เข้าใจค่ะ")
    }

    func testPhrasebookFirst() {
        XCTAssertEqual(Phrasebook.match("Where is the toilet?", lang: .en)?.en, "Where is the toilet?")
        XCTAssertEqual(Phrasebook.match("where is the toilet", lang: .en)?.en, "Where is the toilet?")
        XCTAssertEqual(Phrasebook.match("Water please!", lang: .en)?.en, "Water, please")
        XCTAssertEqual(Phrasebook.match("Wo ist die Toilette?", lang: .de)?.en, "Where is the toilet?")
        XCTAssertEqual(Phrasebook.match("Where is the toilett?", lang: .en)?.en, "Where is the toilet?")   // Tippfehler
        XCTAssertNil(Phrasebook.match("Where is the toilet in the museum?", lang: .en))
        XCTAssertNil(Phrasebook.match("Yes", lang: .th))
        XCTAssertNil(Phrasebook.match("Yess", lang: .en))   // kurze Sätze nur genau
        XCTAssertFalse(Phrasebook.suggestions("toil").isEmpty)
        XCTAssertTrue(Phrasebook.suggestions("to").isEmpty)
        XCTAssertLessThanOrEqual(Phrasebook.suggestions("the").count, 3)
    }

    func testWakeWindowOnlyShortCommands() {
        XCTAssertEqual(Commands.detect("pause", awake: true), .pause)
        XCTAssertEqual(Commands.detect("slow down please", awake: true), .slower)
        XCTAssertNil(Commands.detect("A quiet room please", awake: true))
        XCTAssertNil(Commands.detect("Help me find the hotel", awake: true))
    }

    func testDishesAndBuddhistYear() {
        XCTAssertEqual(Dishes.find("ต้มยำกุ้ง 120 บาท").map(\.roman), ["tom yam kung"])
        XCTAssertEqual(Dishes.find("ข้าวผัด หมู").first?.en, "Fried rice")
        XCTAssertTrue(Dishes.find("Coca-Cola").isEmpty)
        XCTAssertTrue(Dishes.find("ส้มตำ").first!.notes.contains(.peanut))
        XCTAssertEqual(Set(Dishes.all.map(\.th)).count, Dishes.all.count)
        XCTAssertEqual(BuddhistYear.notes(in: "EXP 12/2570"), ["2570 = 2027"])
        XCTAssertEqual(BuddhistYear.notes(in: "หมดอายุ ๑๒/๒๕๖๙"), ["2569 = 2026"])
        XCTAssertEqual(BuddhistYear.notes(in: "Tel 025701234"), [])
    }

    func testPlaces() throws {
        let p = Place(name: "Hotel", local: "โรงแรม ริเวอร์ไซด์ & สปา")
        let url = try XCTUnwrap(p.mapsURL)
        XCTAssertEqual(url.host, "maps.apple.com")
        XCTAssertTrue(url.absoluteString.contains("%26"), url.absoluteString)
        XCTAssertEqual(Place.takeMeThai(.female), "ช่วยพาไปที่นี่หน่อยค่ะ")
        let data = try JSONEncoder().encode([p])
        XCTAssertEqual(try JSONDecoder().decode([Place].self, from: data), [p])
    }
}

// MARK: Übersetzer mit URLProtocol-Stub (532)

final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

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
        Self.requests.append(req)
        let (code, data) = Self.handler?(req) ?? (500, Data())
        let resp = HTTPURLResponse(url: req.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class TranslatorTests: XCTestCase {
    private func make(online: Bool = true) -> Translator {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        return Translator(http: URLSession(configuration: c), isOnline: { online }, useApple: false)
    }

    override func setUp() { StubProtocol.requests = []; StubProtocol.handler = nil }

    func testGoogleResult() async throws {
        StubProtocol.handler = { _ in (200, Data(#"[[["สวัสดี","Hello",null,null]],null,"en"]"#.utf8)) }
        let r = try await make().translate("Hello", from: .en, to: .th, allowOnline: true)
        XCTAssertEqual(r.text, "สวัสดี")
        XCTAssertEqual(r.provider, "google")
    }

    func testFallsBackToMyMemoryAndIgnoresErrorText() async throws {
        StubProtocol.handler = { req in
            if req.url?.host == "translate.googleapis.com" { return (429, Data("busy".utf8)) }
            return (200, Data(#"{"responseStatus":200,"responseData":{"translatedText":"ขอบคุณ"}}"#.utf8))
        }
        let r = try await make().translate("Thanks", from: .en, to: .th, allowOnline: true)
        XCTAssertEqual(r.provider, "mymemory")
        XCTAssertEqual(r.text, "ขอบคุณ")
    }

    func testBothFailThenCooldown() async {
        StubProtocol.handler = { _ in (200, Data(#"{"responseStatus":"429","responseData":{"translatedText":"MYMEMORY WARNING"}}"#.utf8)) }
        let t = make()
        do { _ = try await t.translate("Hi", from: .en, to: .th, allowOnline: true); XCTFail() }
        catch { XCTAssertEqual(error as? TranslateError, .failed) }
        let before = StubProtocol.requests.count
        do { _ = try await t.translate("Hi", from: .en, to: .th, allowOnline: true); XCTFail() }
        catch { XCTAssertEqual(error as? TranslateError, .cooldown) }
        XCTAssertEqual(StubProtocol.requests.count, before, "im Cooldown keine neue Anfrage")
    }

    func testOfflineAndNotAllowed() async {
        do { _ = try await make(online: false).translate("Hi", from: .en, to: .th, allowOnline: true); XCTFail() }
        catch { XCTAssertEqual(error as? TranslateError, .noNetwork) }
        do { _ = try await make().translate("Hi", from: .en, to: .th, allowOnline: false); XCTFail() }
        catch { XCTAssertEqual(error as? TranslateError, .offlineMissing) }
        XCTAssertTrue(StubProtocol.requests.isEmpty)
    }

    func testFormEncodesSpecialCharacters() async throws {
        StubProtocol.handler = { _ in (200, Data(#"[[["x","y"]]]"#.utf8)) }
        _ = try await make().translate("1+1=2 & 50% off", from: .en, to: .th, allowOnline: true)
        let body = String(data: StubProtocol.requests.first?.httpBody ?? Data(), encoding: .utf8) ?? ""
        let q = body.split(separator: "&").first { $0.hasPrefix("q=") }.map { String($0.dropFirst(2)) }
        XCTAssertEqual(q?.removingPercentEncoding, "1+1=2 & 50% off", body)
        XCTAssertTrue(body.contains("%2B"), "+ muss kodiert sein: \(body)")
    }
}

// MARK: Modell mit Test-Engine (531)

final class FakeEngine: SpeechEngine, @unchecked Sendable {
    let events: AsyncStream<SpeechEvent>
    private let cont: AsyncStream<SpeechEvent>.Continuation
    private let lock = NSLock()
    private var _muted: [Bool] = []
    private(set) var langs: [Lang] = []
    private(set) var started = false
    private(set) var stopped = false
    private(set) var flushed = 0

    var muted: [Bool] { lock.lock(); defer { lock.unlock() }; return _muted }

    init() { (events, cont) = AsyncStream<SpeechEvent>.makeStream() }

    func start(langs: [Lang], pauseSeconds: Double, options: AudioOptions,
               onDownload: @escaping @Sendable (Lang, Double) -> Void) async throws {
        self.langs = langs
        started = true
    }
    func stop() async { stopped = true; cont.finish() }
    func setMuted(_ on: Bool) { lock.lock(); _muted.append(on); lock.unlock() }
    func setPause(_ seconds: Double) {}
    func flush() { flushed += 1 }
    func send(_ e: SpeechEvent) { cont.yield(e) }
}

@MainActor
final class ModelEngineTests: XCTestCase {
    private var dir: URL!
    private var saved: [String: Any] = [:]
    private let keys = ["autoSpeak", "pushToTalk", "liveActivity", "politeness", "mode", "langMine", "langPartner", "historyDays"]

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("r4-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for k in keys { saved[k] = UserDefaults.standard.object(forKey: k) }
    }

    override func tearDown() async throws {
        for k in keys { UserDefaults.standard.set(saved[k], forKey: k) }
        try? FileManager.default.removeItem(at: dir)
    }

    private func model(_ fake: FakeEngine) -> InterpreterModel {
        let m = InterpreterModel(files: JSONStore(dir: dir))
        m.pair = .standard
        m.autoSpeak = false
        m.liveActivity = false
        m.pushToTalk = false
        m.politeness = .male
        m.mode = .auto
        m.checkModels = false
        m.makeEngine = { fake }
        return m
    }

    private func wait(_ what: String, _ cond: () -> Bool) async {
        for _ in 0..<100 where !cond() { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(cond(), what)
    }

    func testStartHearTranslateStop() async {
        let fake = FakeEngine()
        let m = model(fake)
        m.start()
        await wait("hört zu") { m.isListening }
        XCTAssertEqual(Set(fake.langs), [.en, .th])
        fake.send(.utterance([.en: Hypothesis(text: "Where is the toilet?", confidence: 0.9),
                              .th: Hypothesis(text: "แวร์ อิส", confidence: 0.2)]))
        await wait("Satz angekommen") { !m.entries.isEmpty }
        let e = m.entries.last!
        XCTAssertEqual(e.src, .en)
        XCTAssertEqual(e.provider, "phrasebook", "Satzbuch zuerst")
        XCTAssertEqual(e.translation, "ห้องน้ำอยู่ที่ไหนครับ")
        m.stop()
        XCTAssertEqual(m.phase, .idle)
        await wait("Engine gestoppt") { fake.stopped }
    }

    func testStopDuringStartNeverListens() async {
        let fake = FakeEngine()
        let m = model(fake)
        m.start()
        m.stop()
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(m.phase, .idle)
        XCTAssertFalse(m.isListening)
    }

    func testPushToTalkMutesUntilHeld() async {
        let fake = FakeEngine()
        let m = model(fake)
        m.pushToTalk = true
        m.start()
        await wait("hört zu") { m.isListening }
        XCTAssertEqual(fake.muted.last, true, "ohne Halten taub")
        m.pttPress()
        XCTAssertEqual(fake.muted.last, false)
        m.pttRelease()
        XCTAssertEqual(fake.flushed, 1)
        XCTAssertEqual(fake.muted.last, false, "bis zum Ergebnis noch offen")
        fake.send(.utterance([.th: Hypothesis(text: "ใช่", confidence: 0.9)]))
        await wait("wieder taub") { fake.muted.last == true }
        m.stop()
    }

    func testHotSwitchesToOneLanguageAndBack() {
        let m = model(FakeEngine())
        m.thermalChanged(.serious)
        XCTAssertTrue(m.hot)
        XCTAssertNotEqual(m.mode, .auto)
        m.thermalChanged(.nominal)
        XCTAssertFalse(m.hot)
        XCTAssertEqual(m.mode, .auto)
    }

    func testShowLastBigAndSayBuiltIn() {
        let m = model(FakeEngine())
        m.sayBuiltIn("Thank you")
        XCTAssertEqual(m.entries.last?.translation, "ขอบคุณครับ")
        m.showLastBig()
        XCTAssertEqual(m.bigRequest, m.entries.last?.id)
    }
}
