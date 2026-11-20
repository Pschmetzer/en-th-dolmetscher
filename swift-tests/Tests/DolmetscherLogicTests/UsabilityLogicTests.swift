import XCTest
@testable import DolmetscherLogic

final class UsabilityLogicTests: XCTestCase {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // InputHistory
    func testHistoryPushIgnoresEmptyAndDedupes() {
        var h = InputHistory()
        h.push("  "); h.push("a"); h.push("b"); h.push("a")
        XCTAssertEqual(h.entries, ["b", "a"])
    }
    func testHistoryUpDownKeepsDraft() {
        var h = InputHistory(); h.push("one"); h.push("two")
        XCTAssertEqual(h.up(current: "draft"), "two")
        XCTAssertEqual(h.up(current: "two"), "one")
        XCTAssertNil(h.up(current: "one"))
        XCTAssertEqual(h.down(), "two")
        XCTAssertEqual(h.down(), "draft")
        XCTAssertNil(h.down())
    }
    func testHistoryEmptyUpNil() { var h = InputHistory(); XCTAssertNil(h.up(current: "x")) }
    func testHistoryCapacity() {
        var h = InputHistory(); for i in 0..<80 { h.push("s\(i)") }
        XCTAssertEqual(h.entries.count, InputHistory.capacity); XCTAssertEqual(h.entries.last, "s79")
    }
    func testHistoryPushResetsCursor() {
        var h = InputHistory(); h.push("a"); _ = h.up(current: "x"); h.push("b")
        XCTAssertNil(h.down())
    }

    // TimeDivider
    func testDividerNoneForFirst() { XCTAssertFalse(TimeDivider.needsDivider(previous: nil, current: t0, calendar: cal)) }
    func testDividerGap() {
        XCTAssertFalse(TimeDivider.needsDivider(previous: t0, current: t0.addingTimeInterval(599), calendar: cal))
        XCTAssertTrue(TimeDivider.needsDivider(previous: t0, current: t0.addingTimeInterval(600), calendar: cal))
    }
    func testDividerDayChange() {
        let late = cal.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 59, second: 30))!
        XCTAssertTrue(TimeDivider.needsDivider(previous: late, current: late.addingTimeInterval(60), calendar: cal))
    }
    func testDividerLabelNotEmpty() {
        XCTAssertFalse(TimeDivider.label(t0, now: t0, calendar: cal, locale: Locale(identifier: "de_DE")).isEmpty)
        XCTAssertNotEqual(TimeDivider.label(t0, now: t0, calendar: cal, locale: Locale(identifier: "en_US")),
                          TimeDivider.label(t0, now: t0.addingTimeInterval(86400 * 3), calendar: cal, locale: Locale(identifier: "en_US")))
    }

    // SearchHits
    func testOccurrences() {
        XCTAssertEqual(SearchHits.occurrences(of: "cafe", in: "Café, CAFE und cafe"), 3)
        XCTAssertEqual(SearchHits.occurrences(of: "aa", in: "aaaa"), 2)
        XCTAssertEqual(SearchHits.occurrences(of: " ", in: "abc"), 0)
        XCTAssertEqual(SearchHits.total(of: "x", in: ["x", "xx", "y"]), 3)
    }
    func testStepWraps() {
        XCTAssertNil(SearchHits.step(current: nil, count: 0, forward: true))
        XCTAssertEqual(SearchHits.step(current: nil, count: 3, forward: true), 0)
        XCTAssertEqual(SearchHits.step(current: nil, count: 3, forward: false), 2)
        XCTAssertEqual(SearchHits.step(current: 2, count: 3, forward: true), 0)
        XCTAssertEqual(SearchHits.step(current: 0, count: 3, forward: false), 2)
    }
    func testPositionLabel() {
        XCTAssertEqual(SearchHits.positionLabel(current: 1, count: 7), "2 / 7")
        XCTAssertEqual(SearchHits.positionLabel(current: nil, count: 7), "7")
        XCTAssertEqual(SearchHits.positionLabel(current: 9, count: 7), "7")
        XCTAssertEqual(SearchHits.positionLabel(current: 0, count: 0), "0")
    }

    // BubbleCopy
    func testCopyModes() {
        XCTAssertEqual(BubbleCopy.text(original: "o", translation: "t", mode: .original), "o")
        XCTAssertEqual(BubbleCopy.text(original: "o", translation: "t", mode: .translation), "t")
        XCTAssertEqual(BubbleCopy.text(original: "o", translation: "t", mode: .both), "o\nt")
        XCTAssertEqual(BubbleCopy.text(original: "o", translation: "", mode: .both), "o")
        XCTAssertEqual(BubbleCopy.text(original: "o", translation: "t", mode: .translation, translated: false), "o")
    }
    func testCopyMeta() {
        let d = cal.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 9, minute: 5))!
        XCTAssertEqual(BubbleCopy.withMeta("hi", speaker: "Anna", date: d, calendar: cal), "[09:05] Anna: hi")
        XCTAssertEqual(BubbleCopy.withMeta("hi", speaker: " ", date: d, calendar: cal), "[09:05] hi")
        XCTAssertEqual(A11yBubble.clock(d, calendar: cal), "09:05")
    }

    // QuickPhraseLogic
    func testQuickPhraseNormalize() {
        XCTAssertEqual(QuickPhraseLogic.normalize("  a\n  b  "), "a b")
        XCTAssertNil(QuickPhraseLogic.normalize(" \n "))
        XCTAssertEqual(QuickPhraseLogic.normalize(String(repeating: "x", count: 300))?.count, 200)
    }
    func testQuickPhraseAdd() {
        var (o, s) = QuickPhraseLogic.add("Hello", to: "")
        XCTAssertEqual(o, .added("Hello")); XCTAssertEqual(s, "Hello")
        (o, s) = QuickPhraseLogic.add("hello", to: s); XCTAssertEqual(o, .duplicate); XCTAssertEqual(s, "Hello")
        (o, s) = QuickPhraseLogic.add("Bye", to: s); XCTAssertEqual(s, "Hello\nBye")
        (o, _) = QuickPhraseLogic.add("  ", to: s); XCTAssertEqual(o, .empty)
    }

    // ErrorLog
    func testErrorLogDedupAndOrder() {
        var l = ErrorLog()
        l.record("A", at: t0); l.record("A", at: t0.addingTimeInterval(10)); l.record("B", at: t0.addingTimeInterval(20))
        l.record("A", at: t0.addingTimeInterval(200)); l.record("  ")
        XCTAssertEqual(l.entries.map(\.message), ["A", "B", "A"])
        XCTAssertEqual(l.entries[0].count, 2)
        let lines = l.formatted().split(separator: "\n")
        XCTAssertEqual(lines.count, 3); XCTAssertTrue(lines[0].hasSuffix(" A")); XCTAssertTrue(lines[2].contains("(×2)"))
        l.clear(); XCTAssertEqual(l.formatted(), "")
    }
    func testErrorLogCapacityAndLimit() {
        var l = ErrorLog(); for i in 0..<70 { l.record("e\(i)", at: t0.addingTimeInterval(Double(i) * 100)) }
        XCTAssertEqual(l.entries.count, ErrorLog.capacity)
        XCTAssertEqual(l.formatted(limit: 5).split(separator: "\n").count, 5)
    }

    // RestartBackoff
    func testBackoff() {
        XCTAssertEqual(RestartBackoff.delay(attempt: 1), 1); XCTAssertEqual(RestartBackoff.delay(attempt: 3), 4)
        XCTAssertEqual(RestartBackoff.delay(attempt: 10), 30); XCTAssertEqual(RestartBackoff.delay(attempt: 0), 1)
        XCTAssertEqual(RestartBackoff.delay(attempt: 9999), 30); XCTAssertEqual(RestartBackoff.delay(attempt: -3), 1)
    }

    // WriteFailure
    func testWriteFailure() {
        XCTAssertEqual(WriteFailure.describe(NSError(domain: "NSPOSIXErrorDomain", code: 32)), "NSPOSIXErrorDomain 32")
        XCTAssertNil(WriteFailure.rotationSummary(failedPaths: []))
        XCTAssertEqual(WriteFailure.rotationSummary(failedPaths: ["/a/b/stderr.log.1"]), "stderr.log.1")
        XCTAssertEqual(WriteFailure.rotationSummary(failedPaths: ["/a/x", "/a/y"]), "x +1")
    }

    // GlossaryBackup
    func testGlossaryBackup() {
        let a = Data("a".utf8), b = Data("b".utf8)
        XCTAssertFalse(GlossaryBackup.shouldBackup(existing: nil, new: a))
        XCTAssertFalse(GlossaryBackup.shouldBackup(existing: Data(), new: a))
        XCTAssertFalse(GlossaryBackup.shouldBackup(existing: a, new: a))
        XCTAssertTrue(GlossaryBackup.shouldBackup(existing: a, new: b))
        XCTAssertEqual(GlossaryBackup.backupURL(for: URL(fileURLWithPath: "/x/glossary.txt")).lastPathComponent, "glossary.txt.bak")
    }

    // MicPermission
    func testMicPermission() {
        XCTAssertEqual(MicPermission.from(rawStatus: 3), .allowed); XCTAssertEqual(MicPermission.from(rawStatus: 2), .denied)
        XCTAssertEqual(MicPermission.from(rawStatus: 0), .notAsked); XCTAssertEqual(MicPermission.from(rawStatus: 1), .restricted)
        XCTAssertEqual(MicPermission.from(rawStatus: 9), .unknown)
        XCTAssertNil(MicPermission.allowed.hintKey); XCTAssertEqual(MicPermission.denied.hintKey, "mic_perm_denied")
        XCTAssertTrue(MicPermission.denied.canOpenSettings); XCTAssertFalse(MicPermission.restricted.canOpenSettings)
        XCTAssertEqual(MicPermission.restricted.detail, "restricted")
    }

    // A11y
    func testA11y() {
        XCTAssertEqual(A11yBubble.position(index: 2, total: 12), "3/12")
        XCTAssertNil(A11yBubble.position(index: 12, total: 12)); XCTAssertNil(A11yBubble.position(index: -1, total: 3))
        XCTAssertEqual(A11yBubble.marker(lang: "th", mine: false), "▶ TH"); XCTAssertEqual(A11yBubble.marker(lang: "en", mine: true), "◀ EN")
    }

    // SessionStats / ExportOptions
    func testStats() {
        let rows = [("en", "hello big world", t0), ("th", "สวัสดี", t0.addingTimeInterval(420)), ("en", "ok", t0.addingTimeInterval(60))]
        let s = SessionStats.summarize(rows)
        XCTAssertEqual(s.count, 3); XCTAssertEqual(s.words, 5); XCTAssertEqual(s.seconds, 420); XCTAssertEqual(s.byLang["en"], 2)
        XCTAssertEqual(SessionStats.line(s, utterances: "utt", words: "w"), "3 utt · 5 w · 7 min · EN 2, TH 1")
        XCTAssertEqual(SessionStats.summarize([]).count, 0)
    }
    func testDuration() {
        XCTAssertEqual(SessionStats.duration(30), "< 1 min"); XCTAssertEqual(SessionStats.duration(3900), "1 h 05 min")
        XCTAssertEqual(SessionStats.duration(-5), "< 1 min")
    }
    func testExportOptions() {
        var o = ExportOptions(); XCTAssertTrue(o.keep(lang: "th")); o.onlyLang = "en"
        XCTAssertFalse(o.keep(lang: "th")); XCTAssertTrue(o.keep(lang: "en"))
    }
}
