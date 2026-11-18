import XCTest
@testable import Dolmetscher

/// Runde 8: Netzwechsel, Lernstatistik, zuletzt gesagte Sätze.
final class Round8Tests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 3, day: d, hour: hour))!
    }

    // MARK: Lernstatistik

    func testStudyLogCountsPerDay() {
        var log = StudyLog()
        log.record(now: day(10), calendar: cal)
        log.record(now: day(10, hour: 20), calendar: cal)
        log.record(now: day(11), calendar: cal)
        XCTAssertEqual(log.today(now: day(10), calendar: cal), 2)
        XCTAssertEqual(log.today(now: day(11), calendar: cal), 1)
        XCTAssertEqual(log.today(now: day(12), calendar: cal), 0)
    }

    func testStreakCountsConsecutiveDaysAndSurvivesAnEmptyToday() {
        var log = StudyLog()
        for d in [7, 9, 10, 11] { log.record(now: day(d), calendar: cal) }
        XCTAssertEqual(log.streak(now: day(11), calendar: cal), 3)
        // Heute noch nichts: die Serie bis gestern gilt noch.
        XCTAssertEqual(log.streak(now: day(12), calendar: cal), 3)
        // Einen Tag ausgelassen: Serie weg.
        XCTAssertEqual(log.streak(now: day(13), calendar: cal), 0)
        XCTAssertEqual(StudyLog().streak(now: day(1), calendar: cal), 0)
    }

    func testStudyLogForgetsOldDays() {
        var log = StudyLog()
        log.record(now: day(1), calendar: cal)
        let later = cal.date(byAdding: .day, value: StudyLog.keepDays + 5, to: day(1))!
        log.record(now: later, calendar: cal)
        XCTAssertEqual(log.days.count, 1)
    }

    func testAnswerRecordsAndOldDeckStillDecodes() throws {
        var deck = LeitnerDeck()
        deck.sync([.init(front: "a", back: "b", lang: .th)], now: day(10))
        deck.answer(deck.cards[0].id, knew: true, now: day(10), calendar: cal)
        XCTAssertEqual(deck.log?.today(now: day(10), calendar: cal), 1)
        let back = try JSONDecoder().decode(LeitnerDeck.self, from: JSONEncoder().encode(deck))
        XCTAssertEqual(back, deck)
        // learn.json aus Runde 5–7 kennt das Feld `log` nicht.
        let old = try JSONDecoder().decode(LeitnerDeck.self, from: Data(#"{"cards":[]}"#.utf8))
        XCTAssertNil(old.log)
    }

    // MARK: Netzwechsel

    func testReconnectOnlyAfterOffline() {
        XCTAssertTrue(ReconnectRetry.cameBack(was: false, now: true))
        XCTAssertFalse(ReconnectRetry.cameBack(was: nil, now: true))
        XCTAssertFalse(ReconnectRetry.cameBack(was: true, now: true))
        XCTAssertFalse(ReconnectRetry.cameBack(was: false, now: false))
    }

    func testPendingPicksRecentFailedUntranslatedEntries() {
        let now = day(10)
        func entry(_ text: String, ago: TimeInterval, error: String? = "x", translation: String? = nil, photo: Bool? = nil) -> Entry {
            Entry(date: now.addingTimeInterval(-ago), src: .en, dst: .th, text: text, translation: translation, error: error, photo: photo)
        }
        let old = entry("old", ago: ReconnectRetry.window + 60)
        let ok = entry("ok", ago: 30, error: nil, translation: "สวัสดี")
        let failed = entry("failed", ago: 20)
        let photo = entry("menu", ago: 10, photo: true)
        let ids = ReconnectRetry.pending([old, ok, failed, photo], now: now)
        XCTAssertEqual(ids, [failed.id])
    }

    func testPendingKeepsOnlyNewestFiveInOrder() {
        let now = day(10)
        let list = (0..<8).map { i in
            Entry(date: now.addingTimeInterval(-Double(100 - i)), src: .en, dst: .th, text: "s\(i)", error: "x")
        }
        let ids = ReconnectRetry.pending(list, now: now)
        XCTAssertEqual(ids, list.suffix(ReconnectRetry.maxCount).map(\.id))
    }

    // MARK: Zuletzt gesagt

    private func spoken(_ p: Phrase, at t: TimeInterval) -> Entry {
        Entry(date: Date(timeIntervalSince1970: t), src: .en, dst: .th, text: p.en, translation: p.th, provider: "phrasebook")
    }

    func testRecentIsNewestFirstWithoutDuplicates() {
        let a = Phrase(en: "Hello", th: "สวัสดี", roman: "", category: "basics")
        let b = Phrase(en: "Thanks", th: "ขอบคุณ", roman: "", category: "basics")
        let c = Phrase(en: "Water", th: "น้ำ", roman: "", category: "basics")
        let entries = [spoken(a, at: 1), spoken(b, at: 2), spoken(a, at: 3),
                       Entry(date: Date(timeIntervalSince1970: 4), src: .en, dst: .th, text: "Water", translation: "x", provider: "google")]
        let r = Phrasebook.recent(entries: entries, in: [a, b, c])
        XCTAssertEqual(r.map(\.en), ["Hello", "Thanks"])   // „Water“ kam nicht aus dem Satzbuch
        XCTAssertEqual(Phrasebook.recent(entries: [spoken(a, at: 1), spoken(b, at: 2)], in: [a, b], limit: 1).map(\.en), ["Thanks"])
    }

    // MARK: Zwischenablage, Fehler, Sichtschutz

    func testSecureCopyIsLocalOnlyAndExpires() {
        let now = Date()
        let o = SecureCopy.options(expiring: true, now: now)
        XCTAssertEqual(o[.localOnly] as? Bool, true)
        XCTAssertEqual(o[.expirationDate] as? Date, now.addingTimeInterval(SecureCopy.lifetime))
        XCTAssertNil(SecureCopy.options(expiring: false)[.expirationDate])
    }

    func testErrorAdviceWorksInEveryUILanguage() {
        for lang in L10n.languages {
            XCTAssertEqual(ErrorAdvice.action(for: L10n.text("err_offline_missing", lang: lang)!), .appSettings, lang)
            XCTAssertEqual(ErrorAdvice.action(for: L10n.text("err_denied", lang: lang)!), .systemSettings, lang)
            XCTAssertEqual(ErrorAdvice.action(for: L10n.text("err_no_mic", lang: lang)!), .systemSettings, lang)
        }
        XCTAssertEqual(ErrorAdvice.action(for: "irgendwas"), .none)
    }

    func testShieldPolicy() {
        XCTAssertTrue(ShieldPolicy.show(shield: true, active: false, hideOnCapture: false, captured: false))
        XCTAssertFalse(ShieldPolicy.show(shield: true, active: true, hideOnCapture: false, captured: true))
        XCTAssertTrue(ShieldPolicy.show(shield: false, active: true, hideOnCapture: true, captured: true))
        XCTAssertFalse(ShieldPolicy.show(shield: false, active: true, hideOnCapture: true, captured: false))
    }

    // MARK: Satzbuch, Lernen

    func testShareTextListsPhrases() {
        let p = Phrase(en: "Hello", th: "สวัสดี{p}", roman: "sawatdee", category: "basics")
        let text = Phrasebook.shareText([p, p], politeness: Politeness.male)
        XCTAssertEqual(text.split(separator: "\n").count, 2)
        XCTAssertTrue(text.hasPrefix("Hello – สวัสดี"))
        XCTAssertFalse(text.contains("{p}"))
    }

    func testPracticeIncludesFutureCardsAndResetClearsBoxes() {
        var deck = LeitnerDeck()
        let now = day(10)
        deck.sync([.init(front: "a", back: "b", lang: .th), .init(front: "c", back: "d", lang: .th)], now: now)
        deck.answer(deck.cards[0].id, knew: true, now: now, calendar: cal)
        deck.answer(deck.cards[0].id, knew: true, now: now, calendar: cal)
        XCTAssertEqual(deck.due(now: now).count, 1)
        XCTAssertEqual(deck.practice().count, 2)
        XCTAssertEqual(deck.practice().first?.box, 1)   // niedrige Fächer zuerst
        deck.resetProgress(now: now)
        XCTAssertEqual(deck.due(now: now).count, 2)
        XCTAssertTrue(deck.cards.allSatisfy { $0.box == 1 })
        XCTAssertEqual(deck.log?.today(now: now, calendar: cal), 2)   // Statistik bleibt
    }
}
