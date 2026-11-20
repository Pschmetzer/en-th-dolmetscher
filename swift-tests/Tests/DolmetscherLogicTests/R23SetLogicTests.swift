import XCTest
@testable import DolmetscherLogic

final class R23SetLogicTests: XCTestCase {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    private func row(_ t: Double, lang: String = "en", text: String = "hello", tr: String = "สวัสดี", translit: String = "",
                     conf: Double? = nil, role: String? = nil, speaker: String? = nil) -> HistoryRow {
        HistoryRow(time: Date(timeIntervalSince1970: t), session: "s", lang: lang, text: text, translation: tr,
                   translit: translit, confidence: conf, provider: nil, role: role, speaker: speaker)
    }
    private func sess(_ id: String, _ rows: [HistoryRow]) -> HistorySession {
        HistorySession(id: id, start: rows.first?.time ?? Date(timeIntervalSince1970: 0), rows: rows)
    }

    // Einstellungen
    func testResetValuesPerGroupKeepsUILang() {
        let d = R23Settings.resetValues(group: .display)
        XCTAssertEqual(d["fontScale"], .number(1))
        XCTAssertNil(d["uiLang"])
        XCTAssertNil(d["speak"])
        let g = R23Settings.resetValues(group: .general)
        for k in ["mineLang", "partnerLang", "model", "uiLang"] { XCTAssertNil(g[k], k) }
        XCTAssertEqual(g["privateMode"], .bool(false))
        XCTAssertNil(R23Settings.resetValues(group: .general, sensitiveActive: true)["privateMode"])
        XCTAssertEqual(R23Settings.resetValues(group: .voice)["speak"], .bool(true))
    }

    func testChangedKeys() {
        var cur = SettingsStore_snapshotLike()
        XCTAssertEqual(R23Settings.changedKeys(group: .voice, current: cur), [])
        cur["rate"] = .number(10)
        XCTAssertEqual(R23Settings.changedKeys(group: .voice, current: cur), ["rate"])
    }

    private func SettingsStore_snapshotLike() -> [String: SettingValue] {
        Dictionary(uniqueKeysWithValues: SettingsLogic.specs.map { ($0.key, $0.fallback) })
    }

    func testPreviewMasksSecretsAndShowsProfileOnlyAsCount() {
        var v = SettingsStore_snapshotLike()
        v["llmModel"] = .text("sk-ant-api03-abcdefghijklmnop1234567890")
        let lines = R23Settings.previewLines(values: v, profile: SettingsProfile(quickPhrases: "a\nb\n\n", glossary: "x"))
        XCTAssertTrue(lines.contains("llmModel = •••"))
        XCTAssertTrue(lines.contains("profile.quickPhrases = 2"))
        XCTAssertFalse(lines.joined().contains("sk-ant"))
    }

    func testExportNeverContainsSecret() {
        let data = SettingsLogic.export(values: SettingsStore_snapshotLike(), profile: SettingsProfile(quickPhrases: "Hallo", glossary: nil),
                                        exportedAt: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(R23Settings.containsSecret(data))
        let bad = Data(#"{"settings":{"x":"sk-ant-api03-zzzzzzzzzzzzzzzzzzzzzzzz"}}"#.utf8)
        XCTAssertTrue(R23Settings.containsSecret(bad))
    }

    func testSecretLike() {
        XCTAssertTrue(R23Settings.secretLike("Bearer abc"))
        XCTAssertTrue(R23Settings.secretLike("a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6q7"))
        XCTAssertFalse(R23Settings.secretLike("claude-haiku-5-5"))
        XCTAssertFalse(R23Settings.secretLike("normal text with spaces and more than thirty two chars"))
    }

    func testSearchRankFoldsAccentsAndRanksLabels() {
        let e = [(key: "a", label: "Lautstärke", help: "Wie laut"), (key: "b", label: "Sprache", help: "Lautstärke der Stimme"),
                 (key: "c", label: "Mikrofon", help: "")]
        XCTAssertEqual(R23Settings.rank(query: "lautstarke", entries: e), ["a", "b"])
        XCTAssertEqual(R23Settings.rank(query: "MIKRO fon", entries: e), ["c"])
        XCTAssertEqual(R23Settings.rank(query: "  ", entries: e), [])
        XCTAssertEqual(R23Settings.rank(query: "stimme laut", entries: e), ["b"])
    }

    // Verlauf
    func testFacetSpeakerLangAndDate() {
        let day: Double = 86_400
        let now = Date(timeIntervalSince1970: 10 * day + 3600)
        let s = [sess("old", [row(0, role: "me")]),
                 sess("new", [row(10 * day, lang: "th", speaker: "Anna"), row(10 * day + 10, lang: "en", role: "other")])]
        var f = R23HistoryFacet()
        XCTAssertEqual(R23History.apply(s, facet: f, now: now, calendar: utc).count, 2)
        f.datePreset = .today
        XCTAssertEqual(R23History.apply(s, facet: f, now: now, calendar: utc).map { $0.id }, ["new"])
        f = R23HistoryFacet(speaker: "Anna")
        XCTAssertEqual(R23History.apply(s, facet: f, now: now, calendar: utc).first?.rows.count, 1)
        f = R23HistoryFacet(lang: "en")
        XCTAssertEqual(R23History.apply(s, facet: f, now: now, calendar: utc).map { $0.rows.count }, [1, 1])
        XCTAssertEqual(R23History.speakers(in: s), ["Anna", "me", "other"])
        XCTAssertEqual(R23History.languages(in: s), ["en", "th"])
    }

    func testCustomRangeIncludesWholeEndDay() {
        let day: Double = 86_400
        let s = [sess("a", [row(5 * day + 80_000)])]
        var f = R23HistoryFacet()
        f.customFrom = Date(timeIntervalSince1970: 5 * day); f.customTo = Date(timeIntervalSince1970: 5 * day + 100)
        XCTAssertEqual(R23History.apply(s, facet: f, now: Date(), calendar: utc).count, 1)
        f.customTo = Date(timeIntervalSince1970: 4 * day)
        XCTAssertEqual(R23History.apply(s, facet: f, now: Date(), calendar: utc).count, 0)
    }

    func testSelectionToggleAndRange() {
        XCTAssertEqual(R23History.toggled(["a"], "b"), ["a", "b"])
        XCTAssertEqual(R23History.toggled(["a", "b"], "a"), ["b"])
        let order = ["a", "b", "c", "d"]
        XCTAssertEqual(R23History.range(order, anchor: "d", to: "b"), ["b", "c", "d"])
        XCTAssertEqual(R23History.range(order, anchor: nil, to: "c"), ["c"])
        XCTAssertEqual(R23History.range(order, anchor: "zz", to: "c"), ["c"])
    }

    func testAnkiCSV() {
        let s = [sess("a", [row(0, text: "Where is \"it\"?", tr: "อยู่ที่ไหน", translit: "yu thi nai"),
                            row(1, text: "where is \"it\"?", tr: "dup"),
                            row(2, text: "no translation", tr: ""),
                            row(3, text: "line1\nline2", tr: "x", )])]
        let csv = R23History.ankiCSV(s)
        XCTAssertTrue(csv.hasPrefix("#separator:comma\n#html:true\n#columns:Front,Back,Tags\n#tags column:3\n"))
        XCTAssertTrue(csv.contains("\"Where is \"\"it\"\"?\",\"อยู่ที่ไหน<br>yu thi nai\",\"dolmetscher en\""))
        XCTAssertTrue(csv.contains("\"line1<br>line2\""))
        XCTAssertFalse(csv.contains("dup"))
        XCTAssertFalse(csv.contains("no translation"))
        XCTAssertEqual(R23History.ankiCSV(s, frontLang: "th").split(separator: "\n").count, 4)
    }

    func testMergedSubtitlesCompressGaps() {
        let s1 = sess("a", [row(0, text: "one", tr: "หนึ่ง")])
        let s2 = sess("b", [row(7200, text: "two", tr: "สอง")])
        let srt = R23History.subtitles([s2, s1], vtt: false)
        XCTAssertTrue(srt.hasPrefix("1\n00:00:00,000 --> 00:00:07,000\nหนึ่ง\none\n\n2\n00:00:08,000 --> 00:00:12,000\nสอง\ntwo\n"), srt)
        let vtt = R23History.subtitles([s1, s2], vtt: true)
        XCTAssertTrue(vtt.hasPrefix("WEBVTT\n\n00:00:00.000 --> 00:00:07.000\n"))
        XCTAssertEqual(R23History.subtitles([], vtt: false), "")
    }

    func testMergedMarkdown() {
        let md = R23History.markdown([sess("a", [row(0)]), sess("b", [row(100)])], title: "T", timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertTrue(md.hasPrefix("# T\n\n## "))
        XCTAssertEqual(md.components(separatedBy: "## ").count, 3)
    }

    func testStats() {
        // 1970-01-05 ist ein Montag
        let mon: Double = 4 * 86_400
        let s = [sess("a", [row(mon + 9 * 3600, conf: 0.9, role: "me"), row(mon + 9 * 3600 + 5, lang: "th", conf: 0.4, role: "other")]),
                 sess("b", [row(mon + 6 * 86_400 + 23 * 3600, speaker: "Anna")])]
        let st = R23StatsLogic.compute(s, calendar: utc)
        XCTAssertEqual(st.total, 3)
        XCTAssertEqual(st.perHour[9], 2); XCTAssertEqual(st.perHour[23], 1)
        XCTAssertEqual(st.perWeekday[0], 2); XCTAssertEqual(st.perWeekday[6], 1)
        XCTAssertEqual(st.perLang.first?.label, "en")
        XCTAssertEqual(st.lowConfidence, 1)
        XCTAssertEqual(st.avgConfidence ?? 0, 0.65, accuracy: 0.001)
        XCTAssertEqual(st.longestSession, 2)
        XCTAssertEqual(st.perSpeaker.count, 3)
        XCTAssertEqual(R23StatsLogic.compute([], calendar: utc).avgConfidence, nil)
    }

    // Sensible Sitzung
    func testSensitiveForcesAllThreeFlagsAndRestoresPrevious() {
        let before = R23SensitiveFlags(privateMode: false, history: true, logText: true)
        let a = R23Sensitive.enter(R23SensitiveState(), current: before)
        XCTAssertTrue(a.state.active)
        XCTAssertEqual(a.set, R23SensitiveFlags(privateMode: true, history: false, logText: false))
        let again = R23Sensitive.enter(a.state, current: a.set)            // schon aktiv: Merker bleibt der alte
        XCTAssertEqual(again.state.previous, before)
        let out = R23Sensitive.leave(a.state)
        XCTAssertEqual(out.restore, before)
        XCTAssertFalse(out.state.active)
        XCTAssertNil(R23Sensitive.leave(R23SensitiveState()).restore)
    }

    func testSensitiveEnforcesAgainstResets() {
        let a = R23Sensitive.enter(R23SensitiveState(), current: R23SensitiveFlags(privateMode: false, history: true, logText: false))
        XCTAssertNil(R23Sensitive.enforce(a.state, current: a.set))
        // „Alles zurücksetzen“ oder Import schaltet den privaten Modus aus
        XCTAssertEqual(R23Sensitive.enforce(a.state, current: R23SensitiveFlags(privateMode: false, history: false, logText: false)),
                       R23Sensitive.flags)
        // Verlauf wieder eingeschaltet
        XCTAssertEqual(R23Sensitive.enforce(a.state, current: R23SensitiveFlags(privateMode: true, history: true, logText: false)),
                       R23Sensitive.flags)
        XCTAssertNil(R23Sensitive.enforce(R23SensitiveState(), current: R23SensitiveFlags()))   // nicht aktiv: nichts erzwingen
    }

    func testSensitiveStateIsCodable() throws {
        let s = R23SensitiveState(active: true, previous: R23SensitiveFlags(privateMode: true, history: true, logText: false))
        let back = try JSONDecoder().decode(R23SensitiveState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    // Mikro, Kopfhörer, Schlüssel
    func testMicVerdictAndMeter() {
        XCTAssertEqual(R23Mic.verdict(peakDB: -80), .silent)
        XCTAssertEqual(R23Mic.verdict(peakDB: -40), .tooQuiet)
        XCTAssertEqual(R23Mic.verdict(peakDB: -12), .good)
        XCTAssertEqual(R23Mic.verdict(peakDB: -1), .tooLoud)
        XCTAssertEqual(R23Mic.db(rms: 0), -120, accuracy: 0.01)
        XCTAssertEqual(R23Mic.meter(db: -30), 0.5, accuracy: 0.001)
        XCTAssertEqual(R23Mic.meter(db: 5), 1)
    }

    func testHeadphoneClassifyAndHint() {
        XCTAssertEqual(R23Headphones.classify("Peters AirPods Pro"), .headphones)
        XCTAssertEqual(R23Headphones.classify("MacBook Pro Lautsprecher"), .speaker)
        XCTAssertEqual(R23Headphones.classify("Kopfhörer"), .headphones)
        XCTAssertEqual(R23Headphones.classify("USB Audio"), .unknown)
        XCTAssertTrue(R23Headphones.hintNeeded(output: .speaker, speakEnabled: true))
        XCTAssertFalse(R23Headphones.hintNeeded(output: .headphones, speakEnabled: true))
        XCTAssertFalse(R23Headphones.hintNeeded(output: .speaker, speakEnabled: false))
    }

    func testKeyFormatAndResult() {
        XCTAssertEqual(R23Key.format("  "), .empty)
        XCTAssertEqual(R23Key.format("abc"), .badPrefix)
        XCTAssertEqual(R23Key.format("sk-ant-x"), .tooShort)
        XCTAssertEqual(R23Key.format("\nsk-ant-api03-abcdefghijklmnop \n"), .ok)
        XCTAssertEqual(R23Key.result(status: 200), .valid)
        XCTAssertEqual(R23Key.result(status: 401), .rejected)
        XCTAssertEqual(R23Key.result(status: 429), .rateLimited)
        XCTAssertEqual(R23Key.result(status: 503), .serverError)
        XCTAssertEqual(R23Key.result(status: nil), .offline)
        XCTAssertEqual(R23Key.result(status: 404), .unexpected(404))
    }

    // Einrichtung
    func testPreflight() {
        let gb: Int64 = 1_073_741_824
        XCTAssertEqual(R23Preflight.evaluate(freeBytes: 2 * gb, requiredGB: 5, network: .online, needsDownload: true),
                       [.lowSpace(neededGB: 5, freeGB: 2)])
        XCTAssertEqual(R23Preflight.evaluate(freeBytes: 50 * gb, requiredGB: 5, network: .offline, needsDownload: true), [.noNetwork])
        XCTAssertEqual(R23Preflight.evaluate(freeBytes: 50 * gb, requiredGB: 5, network: .offline, needsDownload: false), [])
        XCTAssertEqual(R23Preflight.evaluate(freeBytes: nil, requiredGB: 5, network: .unknown, needsDownload: true), [])
    }

    func testETA() {
        var e = R23ETA()
        XCTAssertNil(e.remaining(total: 100))
        e.add(done: 0, at: 0); e.add(done: 10, at: 10)
        XCTAssertEqual(e.remaining(total: 100) ?? 0, 90, accuracy: 0.01)
        e.add(done: 10, at: 5)                                  // zurückspringende Zeit wird ignoriert
        XCTAssertEqual(e.samples.count, 2)
        e.add(done: 100, at: 20)
        XCTAssertEqual(e.remaining(total: 100), 0)
        var stuck = R23ETA(); stuck.add(done: 5, at: 0); stuck.add(done: 5, at: 10)
        XCTAssertNil(stuck.remaining(total: 100))
        XCTAssertEqual(R23ETA.format(20), "< 1 min")
        XCTAssertEqual(R23ETA.format(125), "3 min")
        XCTAssertEqual(R23ETA.format(3 * 3600 + 120), "3 h 02 min")
    }

    // Menü
    func testHotKeyConflicts() {
        let cfg: [Int: Character] = HotKeyLogic.resolve([:])
        let c = R23HotKeys.conflicts(failures: [(id: 1, status: -9878), (id: 2, status: -9879), (id: 4, status: 7)],
                                     configured: cfg, voiceOver: false)
        XCTAssertEqual(c.map { $0.reason }, [.takenByOtherApp, .invalid, .unknown(7)])
        XCTAssertEqual(c.map { $0.letter }, ["D", "P", "S"])
        let sug = c.compactMap { $0.suggestion }
        XCTAssertEqual(sug.count, 3)
        XCTAssertEqual(Set(sug).count, 3)
        XCTAssertTrue(sug.allSatisfy { !cfg.values.contains($0) })
        let vo = R23HotKeys.conflicts(failures: [], configured: cfg, voiceOver: true)
        XCTAssertEqual(vo.map { $0.reason }, [.voiceOver])
    }

    func testLockPause() {
        var s = R23LockPause()
        XCTAssertFalse(s.locked(active: false, paused: false, enabled: true))
        XCTAssertFalse(s.locked(active: true, paused: false, enabled: false))
        XCTAssertFalse(s.locked(active: true, paused: true, enabled: true))
        XCTAssertTrue(s.locked(active: true, paused: false, enabled: true))
        XCTAssertTrue(s.unlocked(paused: true))                 // wir haben pausiert: fortsetzen
        XCTAssertFalse(s.unlocked(paused: true))                // zweites Entsperren: nichts
        XCTAssertTrue(s.locked(active: true, paused: false, enabled: true))
        XCTAssertFalse(s.unlocked(paused: false))               // Nutzer hat selbst fortgesetzt
    }

    func testReportURLHasNoPersonalData() {
        let u = R23Report.url(version: "1.2", build: "9", macOS: "14.5", chip: "Apple M2", uiLang: "de")
        let s = u?.absoluteString ?? ""
        XCTAssertTrue(s.hasPrefix("https://github.com/Pschmetzer/en-th-dolmetscher/issues/new?"))
        XCTAssertTrue(s.contains("Apple%20M2"))
        XCTAssertFalse(s.contains("/Users/"))
    }

    func testMenuTitle() {
        XCTAssertNil(R23Menu.title(nil))
        XCTAssertNil(R23Menu.title("  \n "))
        XCTAssertEqual(R23Menu.title(" a \n b "), "a b")
        let long = String(repeating: "สวัสดี", count: 20)
        let t = R23Menu.title(long, limit: 10) ?? ""
        XCTAssertTrue(t.hasSuffix("…"))
        XCTAssertLessThanOrEqual(t.count, 10)
    }
}
