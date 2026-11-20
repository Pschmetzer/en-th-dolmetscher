import XCTest
@testable import DolmetscherLogic

/// Runde 25: Fehler der Runde 24 (Satzgrenzen in Zahlen, Lücke in Teilwörtern, Cent-Rundung, SRT-Überlappung, Suche) und neue Logik.
final class R25Tests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    func row(_ off: Double, lang: String = "en", text: String, tr: String = "", translit: String = "") -> HistoryRow {
        HistoryRow(time: t0.addingTimeInterval(off), session: "s", lang: lang, text: text, translation: tr, translit: translit,
                   confidence: nil, provider: nil, role: nil, speaker: nil)
    }
    func session(_ rows: [HistoryRow]) -> HistorySession { HistorySession(id: "s", start: rows[0].time, rows: rows) }

    // MARK: Fehlerbehebungen

    func testSentencesKeepDecimalAndTime() {
        XCTAssertEqual(SummaryLogic.sentences("Meet at 10.30. Bring 3.5 kg."), ["Meet at 10.30.", "Bring 3.5 kg."])
        XCTAssertEqual(SummaryLogic.sentences("It costs ฿1.200 today. Ok."), ["It costs ฿1.200 today.", "Ok."])
        XCTAssertEqual(SummaryLogic.sentences("Wait. 5 minutes."), ["Wait.", "5 minutes."])   // Punkt vor Leerzeichen trennt weiter
    }

    func testSentencesCjkPunctuation() {
        XCTAssertEqual(SummaryLogic.sentences("好。你好吗？"), ["好。", "你好吗？"])
    }

    func testTodoWithTimeIsOneSentence() {
        let s = SummaryLogic.summarize([ExportItem(at: t0, lang: "en", to: "th", text: "Meet at 10.30 at the pier.", out: "", translated: false,
                                                   speaker: nil, dur: nil, readyS: nil)])
        XCTAssertEqual(s.todos, ["Meet at 10.30 at the pier."])
    }

    func testClozeDoesNotHitSubstringOfOtherWord() {
        // „a“ steckt in „banana“: die Lücke muss das Wort „a“ treffen, nicht den Buchstaben in „banana“
        let c = LearnLogic.cloze("banana a pear", hiding: 1)
        XCTAssertEqual(c?.answer, "a")
        XCTAssertEqual(c?.prompt, "banana ___ pear")
    }

    func testClozeHidesRightWordWhenShorterWordPrecedes() {
        let c = LearnLogic.cloze("I think this is it", hiding: 4)
        XCTAssertEqual(c?.answer, "it")
        XCTAssertEqual(c?.prompt, "I think this is ___")
    }

    func testWordRangesMatchWords() {
        let t = "Where is the station?"
        XCTAssertEqual(LearnLogic.wordRanges(t).map { String(t[$0]) }, LearnLogic.words(t))
    }

    func testFormatEuroRoundsToCentsFirst() {
        XCTAssertEqual(PriceLogic.format(12.995, .eur, comma: false), "13 €")
        XCTAssertEqual(PriceLogic.format(12.994, .eur, comma: false), "12.99 €")
        XCTAssertEqual(PriceLogic.format(0.999, .eur), "1 €")
        XCTAssertEqual(PriceLogic.format(1234.5, .eur), "1.234,50 €")
    }

    func testSrtNeverOverlapsNextCue() {
        let s = session([row(0, text: "one"), row(1, text: "two"), row(10, text: "three")])
        let srt = HistoryLogic.srt(s)
        XCTAssertTrue(srt.contains("00:00:00,000 --> 00:00:00,950"), srt)   // Lücke 1 s: Ende vor dem nächsten Beginn
        XCTAssertTrue(srt.contains("00:00:01,000 --> 00:00:07,000"), srt)   // lange Lücke: höchstens 6 s
    }

    func testSearchIgnoresEdgeSpacesAndFindsRomanization() {
        let r = row(0, lang: "th", text: "สวัสดีครับ", tr: "Hello", translit: "sawasdee khrap")
        var f = HistoryFilter(); f.query = "hello "
        XCTAssertTrue(HistoryLogic.matches(r, f))
        f.query = "sawasdee"
        XCTAssertTrue(HistoryLogic.matches(r, f))
        f.query = "   "
        XCTAssertTrue(HistoryLogic.matches(r, f))   // nur Leerzeichen = keine Suche
        f.query = "taxi"
        XCTAssertFalse(HistoryLogic.matches(r, f))
    }

    func testHandoffLanguageCodeIsAsciiOnly() {
        XCTAssertNotNil(HandoffPayload.make(text: "a", out: "b", from: "en", to: "th"))
        XCTAssertNotNil(HandoffPayload.make(text: "a", out: "b", from: "zh-hans", to: "th"))
        XCTAssertNil(HandoffPayload.make(text: "a", out: "b", from: "ä", to: "th"))   // „ä“ lag im Zeichenbereich a…z
        XCTAssertNil(HandoffPayload.make(text: "a", out: "b", from: "EN", to: "th"))
        XCTAssertNil(HandoffPayload.make(text: "a", out: "b", from: "e", to: "th"))
    }

    // MARK: Handoff

    func testHandoffAdvertiseRules() {
        XCTAssertFalse(HandoffPayload.shouldAdvertise(enabled: false, sensitive: false, text: "a", out: "b"))
        XCTAssertFalse(HandoffPayload.shouldAdvertise(enabled: true, sensitive: true, text: "a", out: "b"))
        XCTAssertFalse(HandoffPayload.shouldAdvertise(enabled: true, sensitive: false, text: "", out: ""))
        XCTAssertTrue(HandoffPayload.shouldAdvertise(enabled: true, sensitive: false, text: "a", out: ""))
    }

    func testHandoffCardText() {
        XCTAssertEqual(HandoffPayload.make(text: "hello", out: "สวัสดี", from: "en", to: "th")?.cardText, "สวัสดี")
        XCTAssertEqual(HandoffPayload.make(text: "hello", out: "", from: "en", to: "th")?.cardText, "hello")
    }

    // MARK: Fehler-Schritte

    func testAdviceKnownAndUnknownCodes() {
        XCTAssertEqual(ErrorAdviceLogic.advice(for: "mic_denied")?.steps, [.micSettings])
        XCTAssertEqual(ErrorAdviceLogic.advice(for: "model_offline")?.steps, [.retryAfterNetwork, .networkSettings])
        XCTAssertEqual(ErrorAdviceLogic.advice(for: "disk_full")?.steps.first, .storageSettings)
        XCTAssertNil(ErrorAdviceLogic.advice(for: "something_new"))
        XCTAssertNil(ErrorAdviceLogic.advice(for: nil))
    }

    func testAdviceEveryStepIsActionable() {
        let codes = ["mic_denied", "mic_failed", "model_offline", "offline_mt_missing", "llm_billing", "translate_failed",
                     "output_invalid", "python_env_broken", "ffmpeg_missing", "disk_full", "history_failed", "langs_invalid"]
        for c in codes {
            let a = ErrorAdviceLogic.advice(for: c)
            XCTAssertNotNil(a, c)
            XCTAssertFalse(a?.steps.isEmpty ?? true, c)
            XCTAssertEqual(Set(a?.steps ?? []).count, a?.steps.count, "keine doppelten Knöpfe: \(c)")
            XCTAssertLessThanOrEqual(a?.steps.count ?? 0, 2, "höchstens zwei Knöpfe: \(c)")
        }
    }

    func testAdviceUrlsAndRestart() {
        XCTAssertNotNil(ErrorAdviceLogic.url(for: .networkSettings))
        XCTAssertNotNil(ErrorAdviceLogic.url(for: .help))
        XCTAssertNil(ErrorAdviceLogic.url(for: .restart))
        XCTAssertTrue(ErrorAdviceLogic.restartsEngine(.retryAfterNetwork))
        XCTAssertFalse(ErrorAdviceLogic.restartsEngine(.log))
    }

    // MARK: Ausgabe je Richtung

    func testAudioRouteFallbackAndPick() {
        let r = AudioRoute(mine: "A", partner: "")
        XCTAssertEqual(AudioRouteLogic.uid(for: "me", route: r, fallback: "D"), "A")
        XCTAssertEqual(AudioRouteLogic.uid(for: "other", route: r, fallback: "D"), "D")
        XCTAssertEqual(AudioRouteLogic.uid(for: nil, route: r, fallback: "D"), "D")
        XCTAssertFalse(AudioRouteLogic.isActive(AudioRoute()))
        XCTAssertTrue(AudioRouteLogic.isActive(r))
    }

    func testAudioRouteResolveReportsMissingDevice() {
        let res = AudioRouteLogic.resolve(AudioRoute(mine: "A", partner: "B"), fallback: "D", available: ["A", "D"])
        XCTAssertEqual(res, AudioRouteLogic.Resolution(mine: "A", partner: "D", missing: ["B"]))
        XCTAssertEqual(AudioRouteLogic.resolve(AudioRoute(), fallback: "", available: []).missing, [])
    }

    func testAudioRouteProtocolFieldsAreAdditive() {
        XCTAssertEqual(AudioRouteLogic.protocolFields(AudioRoute()), [:])
        XCTAssertEqual(AudioRouteLogic.protocolFields(AudioRoute(mine: "A", partner: "B")), ["output_device_me": "A", "output_device_other": "B"])
        XCTAssertTrue(AudioRouteLogic.sameDevice(AudioRoute(mine: "A", partner: "A")))
        XCTAssertFalse(AudioRouteLogic.sameDevice(AudioRoute()))
    }

    // MARK: Zweispaltiger Export

    func testThaiScriptDetection() {
        XCTAssertTrue(HistoryLogic.isThaiScript("สวัสดีครับ"))
        XCTAssertTrue(HistoryLogic.isThaiScript("OK ไปกัน"))
        XCTAssertFalse(HistoryLogic.isThaiScript("Hello 123"))
        XCTAssertFalse(HistoryLogic.isThaiScript("12:30 ?"))
    }

    func testBilingualRowsPutThaiLeft() {
        let s = session([row(0, lang: "en", text: "Hello", tr: "สวัสดี"), row(5, lang: "th", text: "ขอบคุณ", tr: "Thank you"),
                         row(9, lang: "en", text: "Hi", tr: "Hallo"), row(12, text: "  ")])
        let b = HistoryLogic.bilingualRows(s)
        XCTAssertEqual(b.count, 3)
        XCTAssertEqual(b[0].thai, "สวัสดี"); XCTAssertEqual(b[0].latin, "Hello")
        XCTAssertEqual(b[1].thai, "ขอบคุณ"); XCTAssertEqual(b[1].latin, "Thank you")
        XCTAssertEqual(b[2].thai, "Hi"); XCTAssertEqual(b[2].latin, "Hallo")   // ohne Thai: Original | Übersetzung
    }

    func testMarkdownTableShapeAndEscaping() {
        let s = session([row(0, text: "a|b", tr: "สวัสดี\nสอง", translit: "")])
        let md = HistoryLogic.markdownTable(s, title: "Trip *1*", timeZone: TimeZone(identifier: "UTC")!)
        let lines = md.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[0], "# Trip \\*1\\*")
        XCTAssertEqual(lines[1], "| Time | ไทย | Latin |")
        XCTAssertEqual(lines[2], "| --- | --- | --- |")
        XCTAssertTrue(lines[3].contains("สวัสดี<br>สอง"), lines[3])
        XCTAssertTrue(lines[3].contains("a\\|b"), lines[3])   // | in der Zelle darf die Tabelle nicht brechen
        XCTAssertEqual(lines.count, 4)
    }

    func testMarkdownTableRomanizationColumnOnlyWhenPresent() {
        let with = HistoryLogic.markdownTable(session([row(0, lang: "th", text: "ขอบคุณ", tr: "Thanks", translit: "khop khun")]), title: "T")
        XCTAssertTrue(with.contains("| Romanization |"))
        XCTAssertTrue(with.contains("khop khun"))
        let without = HistoryLogic.markdownTable(session([row(0, text: "x", tr: "y")]), title: "T")
        XCTAssertFalse(without.contains("Romanization"))
    }

    func testHtmlTableEscapes() {
        let s = session([row(0, text: "<b>&", tr: "สวัสดี")])
        let h = HistoryLogic.htmlTable(s, title: "A & B")
        XCTAssertTrue(h.contains("<title>A &amp; B</title>"))
        XCTAssertTrue(h.contains("&lt;b&gt;&amp;"))
        XCTAssertFalse(h.contains("<b>&"))
        XCTAssertTrue(h.hasPrefix("<!DOCTYPE html>"))
    }

    // MARK: Menüleiste, Fenster, Suche

    func testMenuBarLiveMedianAndGuards() {
        XCTAssertEqual(MenuBarLogic.live(done: 3, pending: 1, latencies: [1, 9, 2]).latency, 2)
        XCTAssertEqual(MenuBarLogic.live(done: 3, pending: 0, latencies: [1, 2, 3, 4]).latency, 2.5)
        XCTAssertNil(MenuBarLogic.live(done: 1, pending: 0, latencies: []).latency)
        XCTAssertNil(MenuBarLogic.live(done: 1, pending: 0, latencies: [-1, .nan, .infinity]).latency)
        XCTAssertEqual(MenuBarLogic.live(done: -2, pending: -1, latencies: []), MenuBarLive(done: 0, pending: 0, latency: nil))
        // nur die letzten fünf zählen
        XCTAssertEqual(MenuBarLogic.live(done: 9, pending: 0, latencies: [50, 50, 1, 1, 1, 1, 1]).latency, 1)
        XCTAssertFalse(MenuBarLogic.hasLive(MenuBarLive(done: 0, pending: 0, latency: nil)))
        XCTAssertTrue(MenuBarLogic.hasLive(MenuBarLive(done: 0, pending: 1, latency: nil)))
    }

    func testWindowCatalog() {
        XCTAssertFalse(WindowCatalog.hasDuplicates)
        XCTAssertTrue(WindowCatalog.ids.contains("main"))
        XCTAssertEqual(WindowCatalog.ids.count, 12)
    }

    @MainActor
    func testDebouncerRunsOnlyLastAction() async throws {
        let d = Debouncer()
        var seen: [Int] = []
        d.schedule(after: 0.05) { seen.append(1) }
        d.schedule(after: 0.05) { seen.append(2) }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(seen, [2])
        XCTAssertEqual(d.runs, 1)
    }

    @MainActor
    func testDebouncerCancel() async throws {
        let d = Debouncer()
        var hit = false
        d.schedule(after: 0.05) { hit = true }
        d.cancel()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(hit)
        XCTAssertTrue(SearchDebounce.isImmediate(""))
        XCTAssertFalse(SearchDebounce.isImmediate("a"))
    }
}
