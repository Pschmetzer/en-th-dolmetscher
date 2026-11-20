import XCTest
@testable import Dolmetscher

/// Runde 31: Whisper-Zeitbudget/Prompt/Pause, Akku-Stufen, Audio-Sitzung, Übersetzungs-Cache, Namensschutz, Brücke, Konstanten.
final class Round31Tests: XCTestCase {
    // MARK: Akku / Thermik
    func testPowerProfile() {
        XCTAssertEqual(PowerProfile.from(lowPower: false, thermal: .nominal), .full)
        XCTAssertEqual(PowerProfile.from(lowPower: false, thermal: .fair), .full)
        XCTAssertEqual(PowerProfile.from(lowPower: true, thermal: .nominal), .reduced)
        XCTAssertEqual(PowerProfile.from(lowPower: false, thermal: .serious), .reduced)
        XCTAssertEqual(PowerProfile.from(lowPower: true, thermal: .serious), .minimal)
        XCTAssertEqual(PowerProfile.from(lowPower: false, thermal: .critical), .minimal)
        XCTAssertTrue(PowerProfile.full < PowerProfile.minimal)
    }

    func testFallbackCountShrinksWithProfile() {
        XCTAssertEqual(WhisperTuning.fallbackCount(.full), 3)
        XCTAssertEqual(WhisperTuning.fallbackCount(.reduced), 1)
        XCTAssertEqual(WhisperTuning.fallbackCount(.minimal), 0)
    }

    func testTimeBudgetBounds() {
        XCTAssertEqual(WhisperTuning.timeBudget(duration: 0.5, .full), WhisperTuning.minBudget)
        XCTAssertEqual(WhisperTuning.timeBudget(duration: 5, .full), 15)
        XCTAssertEqual(WhisperTuning.timeBudget(duration: 5, .minimal), 7.5)
        XCTAssertEqual(WhisperTuning.timeBudget(duration: 28, .full), 60)   // Deckel
        XCTAssertLessThanOrEqual(WhisperTuning.timeBudget(duration: 1000, .full), WhisperTuning.maxBudget)
    }

    func testQueueDepthAndWarmUp() {
        XCTAssertEqual(WhisperTuning.maxQueuedJobs(.full), 2)
        XCTAssertEqual(WhisperTuning.maxQueuedJobs(.minimal), 1)
        XCTAssertTrue(WhisperTuning.shouldWarmUp(freshlyLoaded: true, .full))
        XCTAssertFalse(WhisperTuning.shouldWarmUp(freshlyLoaded: true, .reduced))
        XCTAssertFalse(WhisperTuning.shouldWarmUp(freshlyLoaded: false, .full))
    }

    func testShouldDecode() {
        XCTAssertFalse(WhisperTuning.shouldDecode(duration: 0.1, rms: 0.1))
        XCTAssertFalse(WhisperTuning.shouldDecode(duration: 2, rms: 0.0005))
        XCTAssertTrue(WhisperTuning.shouldDecode(duration: 0.3, rms: 0.05))
    }

    // MARK: Prompt
    func testPromptTextDedupesTrimsAndCaps() {
        XCTAssertNil(WhisperTuning.promptText(vocabulary: []))
        XCTAssertNil(WhisperTuning.promptText(vocabulary: ["  ", ""]))
        XCTAssertEqual(WhisperTuning.promptText(vocabulary: ["Somchai", " somchai ", "Chiang Mai"]), "Somchai, Chiang Mai")
        let long = WhisperTuning.promptText(vocabulary: ["Alpha", "Bravo", "Charlie"], maxChars: 14)
        XCTAssertEqual(long, "Alpha, Bravo")   // „Charlie“ passt nicht mehr ganz
    }

    // MARK: Adaptive Pause
    func testAdaptivePause() {
        XCTAssertEqual(AdaptivePause.pause(base: 0.8, lastUtterance: nil), 0.8)
        XCTAssertEqual(AdaptivePause.pause(base: 0.8, lastUtterance: 0.5), 0.8 * AdaptivePause.shortFactor, accuracy: 1e-9)
        XCTAssertEqual(AdaptivePause.pause(base: 0.8, lastUtterance: 3), 0.8)
        XCTAssertEqual(AdaptivePause.pause(base: 0.8, lastUtterance: 12), 0.8 * AdaptivePause.longFactor, accuracy: 1e-9)
        XCTAssertEqual(AdaptivePause.pause(base: 0.55, lastUtterance: 0.4), AdaptivePause.minPause)
        XCTAssertEqual(AdaptivePause.pause(base: 1.5, lastUtterance: 20), AdaptivePause.maxPause)
    }

    // MARK: Sprach-Trägheit
    func testLangStickiness() {
        let langs: [Lang] = [.en, .th]
        // klar Thai: wechselt
        XCTAssertEqual(LangStickiness.choose(probs: ["en": 0.2, "th": 0.8], langs: langs, previous: .en), .th)
        // knapp: bleibt bei der vorigen Sprache
        XCTAssertEqual(LangStickiness.choose(probs: ["en": 0.48, "th": 0.52], langs: langs, previous: .en), .en)
        // ohne Vorgänger: normale Wahl
        XCTAssertEqual(LangStickiness.choose(probs: ["en": 0.48, "th": 0.52], langs: langs, previous: nil), .th)
        // nichts erkannt
        XCTAssertNil(LangStickiness.choose(probs: ["lo": 0.9], langs: langs, previous: .en))
    }

    // MARK: Audio-Sitzung
    func testCategoryOnlyWhenChanged() {
        XCTAssertFalse(SessionTuning.needsCategory(currentCategory: "a", currentOptionsRaw: 3, wantCategory: "a", wantOptionsRaw: 3))
        XCTAssertTrue(SessionTuning.needsCategory(currentCategory: "a", currentOptionsRaw: 3, wantCategory: "a", wantOptionsRaw: 7))
        XCTAssertTrue(SessionTuning.needsCategory(currentCategory: "b", currentOptionsRaw: 3, wantCategory: "a", wantOptionsRaw: 3))
    }

    func testNarrowbandDetection() {
        XCTAssertTrue(SessionTuning.isNarrowband(isHFP: true, sampleRate: 16_000))
        XCTAssertTrue(SessionTuning.isNarrowband(isHFP: true, sampleRate: 8_000))
        XCTAssertFalse(SessionTuning.isNarrowband(isHFP: true, sampleRate: 48_000))
        XCTAssertFalse(SessionTuning.isNarrowband(isHFP: false, sampleRate: 8_000))
        XCTAssertFalse(SessionTuning.isNarrowband(isHFP: true, sampleRate: 0))
        XCTAssertTrue(SessionTuning.warnText(lang: "de").contains("Bluetooth"))
        XCTAssertTrue(SessionTuning.warnText(lang: "th").contains("บลูทูธ"))
    }

    func testRouteActionsStillHold() {
        XCTAssertEqual(AudioSessionPolicy.routeAction(reason: .oldDeviceUnavailable, inputsBefore: ["bt"], inputsAfter: ["mic"]), .inputLost)
        XCTAssertEqual(AudioSessionPolicy.routeAction(reason: .oldDeviceUnavailable, inputsBefore: ["mic"], inputsAfter: ["mic"]), .outputLost)
        XCTAssertEqual(AudioSessionPolicy.routeAction(reason: .newDeviceAvailable, inputsBefore: ["mic"], inputsAfter: ["mic"]), .ignore)
    }

    @MainActor func testHapticThrottle() {
        var t = HapticThrottle()
        let now = Date()
        XCTAssertTrue(t.allow(at: now))
        XCTAssertFalse(t.allow(at: now.addingTimeInterval(0.05)))
        XCTAssertTrue(t.allow(at: now.addingTimeInterval(0.2)))
    }

    // MARK: Breaker
    func testBreakerBackoffAndRemaining() {
        var b = CircuitBreaker()
        let t0 = Date()
        b.failed(at: t0)
        XCTAssertEqual(b.remaining(at: t0), 20, accuracy: 0.01)
        XCTAssertFalse(b.allows(at: t0.addingTimeInterval(10)))
        b.failed(at: t0)
        XCTAssertEqual(b.remaining(at: t0), 40, accuracy: 0.01)
        for _ in 0..<10 { b.failed(at: t0) }
        XCTAssertEqual(b.remaining(at: t0), 120, accuracy: 0.01)   // Deckel
        XCTAssertEqual(b.remaining(at: t0.addingTimeInterval(500)), 0)
        b.succeeded()
        XCTAssertEqual(b.consecutiveFailures, 0)
        b.failed(at: t0, rateLimited: true)
        XCTAssertEqual(b.remaining(at: t0), 300, accuracy: 0.01)
    }

    func testCooldownLabel() {
        XCTAssertEqual(ModelTuning.cooldownLabel("Pause", remaining: 12.2), "Pause (13 s)")
        XCTAssertEqual(ModelTuning.cooldownLabel("Pause", remaining: 0), "Pause")
    }

    // MARK: Cache
    func testCacheLRU() {
        var c = TranslationCache(capacity: 2)
        func r(_ s: String) -> TranslationResult { TranslationResult(text: s, provider: "apple") }
        c.put(r("a"), text: "one", from: .en, to: .th)
        c.put(r("b"), text: "two", from: .en, to: .th)
        XCTAssertEqual(c.get("one", from: .en, to: .th)?.text, "a")   // „one“ jetzt neueste
        c.put(r("c"), text: "three", from: .en, to: .th)              // „two“ fliegt raus
        XCTAssertNil(c.get("two", from: .en, to: .th))
        XCTAssertEqual(c.get("one", from: .en, to: .th)?.text, "a")
        XCTAssertEqual(c.count, 2)
        XCTAssertNil(c.get("one", from: .th, to: .en))                // Richtung zählt
        XCTAssertEqual(c.get("  one ", from: .en, to: .th)?.text, "a")   // Leerraum normalisiert
        c.clear()
        XCTAssertEqual(c.count, 0)
    }

    func testTranslatorServesRepeatsFromCache() async throws {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        StubProtocol.requests = []
        StubProtocol.handler = { _ in (200, Data("[[[\"สวัสดี\"]]]".utf8)) }
        let t = Translator(http: URLSession(configuration: c), isOnline: { true }, useApple: false)
        let a = try await t.translate("hello friend", from: .en, to: .th, allowOnline: true)
        let n = StubProtocol.requests.count
        let b = try await t.translate("hello friend", from: .en, to: .th, allowOnline: true)
        XCTAssertEqual(a.text, b.text)
        XCTAssertEqual(StubProtocol.requests.count, n)   // zweiter Aufruf ohne Netz
        StubProtocol.handler = nil
    }

    func testPassthrough() async throws {
        XCTAssertTrue(TranslationShortcut.isPassthrough("12:30"))
        XCTAssertTrue(TranslationShortcut.isPassthrough(" … "))
        XCTAssertFalse(TranslationShortcut.isPassthrough("12 baht"))
        let t = Translator(isOnline: { false }, useApple: false)
        let r = try await t.translate("12:30", from: .en, to: .th, allowOnline: true)
        XCTAssertEqual(r.text, "12:30")
    }

    // MARK: Namensschutz
    func testNamesDetection() {
        XCTAssertEqual(NameProtector.names(in: "Please tell Somchai that I am in Chiang Mai."), ["Somchai", "Chiang", "Mai"])
        XCTAssertEqual(NameProtector.names(in: "Hello there. How are you?"), [])
        XCTAssertEqual(NameProtector.names(in: "See you on Monday, I think"), [])
        XCTAssertEqual(NameProtector.names(in: "คุณ Somchai อยู่ไหน"), ["Somchai"])
    }

    func testProtectRestoreRoundTrip() {
        let p = NameProtector.protect("Ask Somchai about Pattaya", names: ["Somchai", "Pattaya"])
        XCTAssertFalse(p.text.contains("Somchai"))
        XCTAssertEqual(NameProtector.restore("ถาม " + p.text, map: p.map)?.contains("Somchai"), true)
        // Platzhalter verloren: unbrauchbar
        XCTAssertNil(NameProtector.restore("ถามเขา", map: p.map))
    }

    func testOnlineKeepsNamesThroughStub() async throws {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        StubProtocol.requests = []
        // Der „Übersetzer“ lässt den Platzhalter unberührt.
        StubProtocol.handler = { req in
            let body = String(decoding: req.httpBody ?? Data(), as: UTF8.self)
            XCTAssertFalse(body.contains("Somchai"), "Name darf nicht roh an den Dienst gehen")
            return (200, Data("[[[\"ถาม QX0Z\"]]]".utf8))
        }
        let t = Translator(http: URLSession(configuration: c), isOnline: { true }, useApple: false)
        let r = try await t.translate("Please ask Somchai", from: .en, to: .th, allowOnline: true)
        XCTAssertEqual(r.text, "ถาม Somchai")
        StubProtocol.handler = nil
    }

    // MARK: Brücke über Englisch
    func testPivotRoute() {
        let th = Lang.th, ja = Lang(rawValue: "ja")!
        XCTAssertEqual(PivotPlan.route(from: th, to: ja, installed: { _, _ in true }), .direct)
        XCTAssertEqual(PivotPlan.route(from: th, to: ja, installed: { $0 == .en || $1 == .en }), .viaEnglish)
        XCTAssertEqual(PivotPlan.route(from: th, to: ja, installed: { f, t in f == th && t == .en }), .none)
        XCTAssertEqual(PivotPlan.route(from: .en, to: th, installed: { _, _ in false }), .none)
    }

    // MARK: Konstanten und Lautstärke
    func testModelConstantsKeepOldValues() {
        XCTAssertEqual(ModelTuning.defaultPause, 0.8)
        XCTAssertEqual(ModelTuning.defaultAutoStopMinutes, 10)
        XCTAssertEqual(ModelTuning.defaultHistoryDays, 30)
        XCTAssertEqual(ModelTuning.expectationSeconds, 20)
        XCTAssertEqual(ModelTuning.overrideMaxRetries, 10)
    }

    func testVolumeSteps() {
        XCTAssertEqual(ModelTuning.louder(0.9), 1)
        XCTAssertEqual(ModelTuning.louder(0.5), 0.75)
        XCTAssertEqual(ModelTuning.quieter(0.3), 0.25)
        XCTAssertEqual(ModelTuning.quieter(1), 0.75)
    }

    func testRetryRelease() {
        XCTAssertTrue(ModelTuning.shouldRetryRelease(busy: true, attempt: 9))
        XCTAssertFalse(ModelTuning.shouldRetryRelease(busy: true, attempt: 10))
        XCTAssertFalse(ModelTuning.shouldRetryRelease(busy: false, attempt: 0))
    }

    // MARK: Sprechtext
    func testUnitsForEnglishVoice() {
        XCTAssertEqual(SpeechText.normalize("It is 35°C", lang: .en), "It is 35 degrees Celsius")
        XCTAssertEqual(SpeechText.normalize("80 km/h", lang: .en), "80 kilometres per hour")
    }
}
