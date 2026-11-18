import XCTest
import UIKit
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
