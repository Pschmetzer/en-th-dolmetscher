import XCTest
import UIKit
import AVFAudio
import CoreSpotlight
@testable import Dolmetscher

/// Runde 7: Robustheit, Barrierefreiheit und kleine Funktionen der iPhone-App.
final class Round7Tests: XCTestCase {
    // MARK: Zeitlimit und Online-Status

    func testTimeoutReturnsNilForSlowOperation() async {
        let slow: Int? = await withTimeout(seconds: 0.1) { try? await Task.sleep(for: .seconds(5)); return 1 }
        XCTAssertNil(slow)
        let fast: Int? = await withTimeout(seconds: 2) { 42 }
        XCTAssertEqual(fast, 42)
    }

    func testOnlineStatusFromHTTPCode() {
        func resp(_ c: Int) -> URLResponse { HTTPURLResponse(url: URL(string: "https://x.test")!, statusCode: c, httpVersion: nil, headerFields: nil)! }
        XCTAssertEqual(OnlineStatus.of(resp(200)), .ok)
        XCTAssertEqual(OnlineStatus.of(resp(429)), .rateLimited)
        XCTAssertEqual(OnlineStatus.of(resp(503)), .failed)
        XCTAssertEqual(OnlineStatus.of(nil), .ok)
    }

    func testRateLimitPausesLonger() {
        var b = CircuitBreaker()
        let t = Date()
        b.failed(at: t)
        XCTAssertFalse(b.allows(at: t.addingTimeInterval(10)))
        XCTAssertTrue(b.allows(at: t.addingTimeInterval(25)))
        b.failed(at: t, rateLimited: true)
        XCTAssertFalse(b.allows(at: t.addingTimeInterval(120)))
    }

    func testTranslatorReportsRateLimit() async {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        StubProtocol.requests = []
        StubProtocol.handler = { _ in (429, Data("{}".utf8)) }
        let t = Translator(http: URLSession(configuration: c), isOnline: { true }, useApple: false)
        do { _ = try await t.translate("Hello there", from: .en, to: .th, allowOnline: true); XCTFail() }
        catch { XCTAssertEqual(error as? TranslateError, .rateLimited) }
        // danach lange Pause: keine weitere Anfrage
        let n = StubProtocol.requests.count
        do { _ = try await t.translate("Hello there", from: .en, to: .th, allowOnline: true); XCTFail() }
        catch { XCTAssertEqual(error as? TranslateError, .cooldown) }
        XCTAssertEqual(StubProtocol.requests.count, n)
        StubProtocol.handler = nil
    }

    // MARK: Spracherkennung

    func testNoiseEstimateFreezesDuringLongSpeech() {
        var g = VoiceGate(pause: 0.8)
        var t = 0.0
        while t < 1.0 { _ = g.step(rms: 0.003, dur: 0.05); t += 0.05 }
        let before = g.threshold
        t = 0
        // 12 s fast ohne Pause: der Grundpegel darf nicht auf Sprachniveau steigen
        while t < 12 { _ = g.step(rms: t.truncatingRemainder(dividingBy: 1) < 0.9 ? 0.08 : 0.02, dur: 0.05); t += 0.05 }
        XCTAssertTrue(g.inUtterance)
        XCTAssertEqual(g.threshold, before, accuracy: 0.0001)
    }

    func testTrailingDebounceFiresOnce() async throws {
        let d = TrailingDebounce(delay: 0.1)
        let count = Counter()
        for _ in 0..<5 { d.fire { count.add() } }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(count.value, 1)
        d.fire { count.add() }
        d.cancel()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(count.value, 1)
    }

    // MARK: Rückübersetzung je Schrift

    func testBackCheckScalesWithScript() {
        // 6 chinesische Zeichen sind ein ganzer Satz
        XCTAssertTrue(BackCheck.deviates(original: "请带我去机场", back: "我要一杯水"))
        XCTAssertFalse(BackCheck.deviates(original: "请带我去机场", back: "请带我去机场"))
        // 2 Zeichen: zu kurz zum Warnen
        XCTAssertFalse(BackCheck.deviates(original: "你好", back: "再见了"))
        // Thai: 6 Zeichen reichen
        XCTAssertTrue(BackCheck.deviates(original: "ขอน้ำหน่อย", back: "ไปสนามบิน"))
        // Latein bleibt bei 8
        XCTAssertFalse(BackCheck.deviates(original: "Hello", back: "Goodbye"))
    }

    // MARK: Satzbuch

    func testPhraseIdsDifferByPackAndPair() {
        let a = Phrase(en: "How much?", th: "x", roman: "", category: "pack.a", pack: "a")
        let b = Phrase(en: "How much?", th: "x", roman: "", category: "pack.b", pack: "b")
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(a.favoriteKey, b.favoriteKey, "Favorit gilt unabhängig vom Paket")
        let c = Phrase(en: "Hallo", th: "x", roman: "", category: "favorites", src: .de, dst: .th)
        let d = Phrase(en: "Hallo", th: "y", roman: "", category: "favorites", src: .de, dst: .ja)
        XCTAssertNotEqual(c.favoriteKey, d.favoriteKey)
        XCTAssertNotEqual(c.id, d.id)
    }

    // MARK: Zahlenfeld

    func testNumberCardDecimals() {
        func type(_ s: String) -> String { s.reduce("") { NumberCard.append($1, to: $0) } }
        XCTAssertEqual(type("12.50"), "12.50")
        XCTAssertEqual(type("12.505"), "12.50", "höchstens zwei Nachkommastellen")
        XCTAssertEqual(type("1.2.3"), "1.23", "nur ein Punkt")
        XCTAssertEqual(type("."), "0.")
        XCTAssertEqual(NumberCard.spoken("12.5", in: .en), "12.5")
        XCTAssertEqual(NumberCard.spoken("12.5", in: .de), "12,5")
        XCTAssertEqual(NumberCard.spoken("12.50", in: .de), "12,50")
        XCTAssertEqual(NumberCard.spoken("1200", in: .en), "1,200")
    }

    // MARK: Foto, Währung, Barrierefreiheit

    func testCameraPhotoIsDownsampled() {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let big = UIGraphicsImageRenderer(size: CGSize(width: 3200, height: 2400), format: fmt).image { c in
            UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: 3200, height: 2400))
        }
        let out = PhotoDownsample.image(big, maxPixels: 1000)
        XCTAssertLessThanOrEqual(max(out.size.width * out.scale, out.size.height * out.scale), 1000)
        let small = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: fmt).image { _ in }
        XCTAssertTrue(PhotoDownsample.image(small, maxPixels: 1000) === small)
    }

    func testFXDefaultsFollowRegion() {
        XCTAssertEqual(FXDefaults.code(for: Locale(identifier: "en_US")), "USD")
        XCTAssertEqual(FXDefaults.code(for: Locale(identifier: "de_DE")), "EUR")
        XCTAssertEqual(FXDefaults.code(for: Locale(identifier: "ja_JP")), "JPY")
        XCTAssertEqual(FXDefaults.code(for: Locale(identifier: "xx_XX")), "EUR")
        XCTAssertEqual(FXDefaults.rate(for: "USD"), 0.028)
    }

    func testVoiceOverLabelCarriesLanguages() {
        let a = A11yLabel.build(src: .th, text: "สวัสดี", target: .de, translation: "Hallo", extras: ["ca. 1 €"], uiLang: "de")
        let s = a.string
        XCTAssertTrue(s.contains("สวัสดี") && s.contains("Hallo") && s.contains("ca. 1 €"))
        func lang(of word: String) -> String? {
            let r = (s as NSString).range(of: word)
            return a.attribute(.accessibilitySpeechLanguage, at: r.location, effectiveRange: nil) as? String
        }
        XCTAssertEqual(lang(of: "สวัสดี"), Lang.th.voiceLocale)
        XCTAssertEqual(lang(of: "Hallo"), Lang.de.voiceLocale)
        XCTAssertNil(lang(of: "ca. 1"))
    }

    func testSummaryShrinksForLongConversations() {
        let lines = (1...80).map { "A: \($0)" }
        let half = ConversationSummary.shrink(lines)
        XCTAssertEqual(half?.count, 40)
        XCTAssertEqual(half?.last, "A: 80", "neuere Zeilen bleiben")
        XCTAssertNil(ConversationSummary.shrink(["A: 1", "B: 2", "A: 3"]))
    }

    func testWhisperQueueIsBounded() {
        XCTAssertEqual(WhisperSpeechEngine.maxQueuedJobs, 2)
        XCTAssertGreaterThanOrEqual(WhisperSpeechEngine.maxConsecutiveFailures, 2)
    }

    // MARK: Runde 7b: Modus, Verlauf, Lernkasten

    func testExpectSpeakerNeverChangesStoredMode() {
        let pair = LangPair(mine: .en, partner: .th)
        XCTAssertEqual(ListenOverride.needed(for: .th, mode: .mine, pair: pair), .partner)
        XCTAssertEqual(ListenOverride.needed(for: .en, mode: .partner, pair: pair), .mine)
        XCTAssertNil(ListenOverride.needed(for: .th, mode: .auto, pair: pair))
        XCTAssertNil(ListenOverride.needed(for: .de, mode: .mine, pair: pair), "Sprache nicht im Paar")
    }

    func testRetentionCap() {
        XCTAssertEqual(Retention.cap(days: 0), 300)
        XCTAssertEqual(Retention.cap(days: 1), 300)
        XCTAssertEqual(Retention.cap(days: 30), 2000)
        XCTAssertEqual(Retention.cap(days: -1), 2000)
    }

    func testTalkCardsExpireButFavoritesStay() {
        var deck = LeitnerDeck()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        deck.sync([.init(front: "Hallo", back: "สวัสดี", lang: .th),
                   .init(front: "Preis?", back: "ราคา", lang: .th, talk: true)], now: t0)
        XCTAssertEqual(deck.cards.count, 2)
        XCTAssertEqual(deck.pruneTalk(olderThan: t0.addingTimeInterval(-10)), 0, "noch innerhalb der Aufbewahrung")
        XCTAssertEqual(deck.pruneTalk(olderThan: t0.addingTimeInterval(10)), 1)
        XCTAssertEqual(deck.cards.map(\.front), ["Hallo"])
    }

    func testDismissedCardDoesNotComeBack() {
        var deck = LeitnerDeck()
        let s = LeitnerDeck.Source(front: "Hallo", back: "สวัสดี", lang: .th)
        deck.sync([s])
        deck.dismiss(s.id)
        XCTAssertTrue(deck.cards.isEmpty)
        XCTAssertEqual(deck.sync([s]), 0)
        // alte learn.json ohne die neuen Felder bleibt lesbar
        let old = #"{"cards":[{"id":"th|x","front":"a","back":"b","lang":"th","box":1,"due":0}]}"#
        XCTAssertEqual(try? JSONDecoder().decode(LeitnerDeck.self, from: Data(old.utf8)).cards.count, 1)
    }

    func testPhotoLinesAreNotLearnCards() {
        var e = Entry(src: .en, dst: .th, text: "Pad Thai 80", translation: "ผัดไทย 80")
        XCTAssertNotNil(LeitnerDeck.Source.from(e, pair: LangPair(mine: .en, partner: .th)))
        e.photo = true
        XCTAssertNil(LeitnerDeck.Source.from(e, pair: LangPair(mine: .en, partner: .th)))
        XCTAssertFalse(TranscriptExport.text([e], lang: "en").contains("Pad Thai"))
    }

    func testFuzzyPhraseNeverSwapsKnownWords() {
        let bill = Phrase(en: "Can I have the bill", th: "x", roman: "", category: "c")
        let pill = Phrase(en: "Do you have a pill for headache", th: "y", roman: "", category: "c")
        let list = [bill, pill]
        XCTAssertNil(Phrasebook.match("Can I have the pill", lang: .en, in: list), "pill ist ein bekanntes Wort: anderer Satz")
        XCTAssertEqual(Phrasebook.match("Can I have the billl", lang: .en, in: list)?.en, "Can I have the bill", "echter Tippfehler")
        let num = Phrase(en: "The room costs 500 baht per night", th: "z", roman: "", category: "c")
        XCTAssertNil(Phrasebook.match("The room costs 800 baht per night", lang: .en, in: [num]), "andere Zahl: nie ersetzen")
    }

    func testPhotoRowsKeepColumnsApartAndJoinPrices() {
        func c(_ t: String, _ y: Double, _ x: Double) -> TextScanner.Cell { .init(text: t, midY: y, height: 0.02, minX: x) }
        let lines = TextScanner.arrange([c("80", 0.80, 0.8), c("Pad Thai", 0.80, 0.1), c("Tom Yum", 0.70, 0.1),
                                         c("Som Tam", 0.70, 0.55), c("Rice", 0.60, 0.1), c("฿120", 0.601, 0.8)])
        XCTAssertEqual(lines, ["Pad Thai 80", "Tom Yum", "Som Tam", "Rice ฿120"])
        XCTAssertTrue(TextScanner.looksLikePrice("120 บาท"))
        XCTAssertTrue(TextScanner.looksLikePrice("12,50 €"))
        XCTAssertFalse(TextScanner.looksLikePrice("Pad Thai"))
    }

    func testAbandonableReturnsOnCancel() async {
        let t = Task { () -> String in
            do { _ = try await abandonable { try? await Task.sleep(for: .seconds(30)); return 1 }; return "done" }
            catch is CancellationError { return "cancelled" } catch { return "other" }
        }
        try? await Task.sleep(for: .milliseconds(100))
        t.cancel()
        let r = await withTimeout(seconds: 3) { await t.value }
        XCTAssertEqual(r, "cancelled")
        let ok = try? await abandonable { 7 }
        XCTAssertEqual(ok, 7)
    }

    func testInterruptionResumePolicyAndWhisperSize() {
        XCTAssertTrue(InterruptionPolicy.shouldRestart(optionsRaw: AVAudioSession.InterruptionOptions.shouldResume.rawValue))
        XCTAssertFalse(InterruptionPolicy.shouldRestart(optionsRaw: 0))
        XCTAssertEqual(WhisperSize.requiredBytes(sizeMB: 500), 1_000_000_000)
        XCTAssertNil(WhisperSize.requiredBytes(sizeMB: nil))
    }

    func testRecentPairsKeepOrderWithoutDuplicates() {
        let d = UserDefaults(suiteName: "r7-recent-\(UUID().uuidString)")!
        let a = LangPair(mine: .en, partner: .th), b = LangPair(mine: .de, partner: .th), c = LangPair(mine: .en, partner: .ja)
        RecentPairs.remember(a, current: b, in: d)
        RecentPairs.remember(b, current: c, in: d)
        RecentPairs.remember(c, current: a, in: d)
        let list = RecentPairs.load(from: d)
        XCTAssertEqual(list.first, c, "zuletzt verlassenes Paar zuerst")
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(Set(list.map { "\($0.mine.rawValue)\($0.partner.rawValue)" }).count, 3)
    }

    func testCSVExportHasBOMQuotesAndSkipsPhotos() {
        var photo = Entry(src: .en, dst: .th, text: "Menu", translation: "เมนู"); photo.photo = true
        let e = Entry(src: .en, dst: .th, text: "Say \"hi\", ok", translation: "สวัสดี")
        let csv = TranscriptCSV.csv([e, photo])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}date,from,to,text,translation"))
        XCTAssertTrue(csv.contains("\"Say \"\"hi\"\", ok\""))
        XCTAssertTrue(csv.contains("สวัสดี"))
        XCTAssertFalse(csv.contains("Menu"))
    }

    func testFXParse() {
        let json = #"{"amount":1.0,"base":"THB","date":"2026-11-17","rates":{"EUR":0.0268}}"#
        XCTAssertEqual(FXFetch.parse(Data(json.utf8), code: "eur")?.rate, 0.0268)
        XCTAssertEqual(FXFetch.parse(Data(json.utf8), code: "EUR")?.date, "2026-11-17")
        XCTAssertNil(FXFetch.parse(Data(json.utf8), code: "USD"))
        XCTAssertNil(FXFetch.parse(Data("{}".utf8), code: "EUR"))
    }

    func testMachineRomanizationIsMarkedApproximate() {
        var e = Entry(src: .en, dst: .th, text: "Hello", translation: "สวัสดี")
        XCTAssertTrue(e.romanIsApproximate)
        e.roman = "sawatdee"
        XCTAssertFalse(e.romanIsApproximate)
    }

    func testSpotlightItemsFromFavorites() {
        let favs = [Phrase(en: "Hello", th: "สวัสดี", roman: "", category: "favorites"),
                    Phrase(en: "Hallo", th: "x", roman: "", category: "favorites", src: .de, dst: .ja)]
        let items = SpotlightIndexer.items(favs)
        XCTAssertEqual(items.map(\.uniqueIdentifier), ["en>th|Hello", "de>ja|Hallo"])
        XCTAssertEqual(items.first?.attributeSet.title, "Hello")
    }

    func testReduceMotionDropsAnimation() {
        XCTAssertNil(Motion.animation(reduce: true))
        XCTAssertNotNil(Motion.animation(reduce: false))
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func add() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}
