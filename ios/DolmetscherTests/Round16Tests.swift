import XCTest
@testable import Dolmetscher

/// Runde 16: Randfälle der reinen Logik (Export, Suche, Lernkasten, Widget-Auswahl, Datenschutz-Schalter, Sprachpaare).
final class Round16Tests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ d: Int, hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 3, day: d, hour: hour))!
    }

    // MARK: Export (CSV)

    func testCSVEmptyListHasOnlyHeader() {
        XCTAssertEqual(TranscriptCSV.csv([]), "\u{FEFF}date,from,to,text,translation\r\n")
    }

    func testCSVNeutralisesFormulaStartsInTextAndTranslation() {
        for start in ["=1+1", "+49", "-5", "@SUM(A1)", "\tx", "\rx"] {
            let e = Entry(src: .en, dst: .th, text: start, translation: start)
            let csv = TranscriptCSV.csv([e])
            XCTAssertTrue(csv.contains("\"'\(start)\",\"'\(start)\""), start.debugDescription)
        }
    }

    func testCSVKeepsNewlinesThaiEmojiAndMissingTranslation() {
        let e = Entry(src: .th, dst: .en, text: "สวัสดี\nครับ 🙏", translation: nil)
        let csv = TranscriptCSV.csv([e])
        XCTAssertTrue(csv.contains("\"สวัสดี\nครับ 🙏\",\"\"\r\n"))
        XCTAssertEqual(csv.components(separatedBy: "\r\n").count, 3) // Kopf, eine Zeile, Rest nach dem letzten Umbruch
    }

    func testCSVVeryLongTextIsNotTruncated() {
        let long = String(repeating: "ก", count: 100_000)
        let csv = TranscriptCSV.csv([Entry(src: .th, dst: .en, text: long, translation: "x")])
        XCTAssertTrue(csv.contains(long))
    }

    func testCSVSafeCellBoundaries() {
        XCTAssertEqual(CSVSafe.cell(""), "")
        XCTAssertEqual(CSVSafe.cell("'=x"), "'=x")        // schon Text
        XCTAssertEqual(CSVSafe.cell("a=b"), "a=b")        // nur der Anfang zählt
        XCTAssertEqual(CSVSafe.cell("ก=1"), "ก=1")
    }

    func testCSVFileNameUsesTheCalendarDay() {
        XCTAssertEqual(CSVSafe.fileName(now: date(10), calendar: utc), "Dolmetscher-2026-03-10.csv")
        // 23:30 UTC ist in Bangkok schon der nächste Tag.
        var bkk = Calendar(identifier: .gregorian)
        bkk.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        XCTAssertEqual(CSVSafe.fileName(now: date(10, hour: 23), calendar: bkk), "Dolmetscher-2026-03-11.csv")
    }

    // MARK: Satzbuch-Suche

    func testSearchEmptyAndWhitespaceQueryMatchesEverything() {
        XCTAssertTrue(PhraseSearch.matches(query: "", fields: ["x"]))
        XCTAssertTrue(PhraseSearch.matches(query: " \t\n ", fields: []))
    }

    func testSearchFoldsCaseAccentsAndWidth() {
        XCTAssertTrue(PhraseSearch.matches(query: "CAFE", fields: ["Café au lait"]))
        XCTAssertTrue(PhraseSearch.matches(query: "ＡＢＣ", fields: ["abc"]))
        XCTAssertTrue(PhraseSearch.matches(query: "abc", fields: ["ＡＢＣ"]))
    }

    func testSearchNeedsAllTokensAcrossFields() {
        XCTAssertTrue(PhraseSearch.matches(query: "water sawatdee", fields: ["Water", "sawatdee krap"]))
        XCTAssertTrue(PhraseSearch.matches(query: "krap\twater", fields: ["Water", "sawatdee krap"]))
        XCTAssertFalse(PhraseSearch.matches(query: "water tea", fields: ["Water", "sawatdee krap"]))
        XCTAssertFalse(PhraseSearch.matches(query: "x", fields: []))
    }

    func testSearchFindsThaiAndSpecialCharacters() {
        XCTAssertTrue(PhraseSearch.matches(query: "น้ำ", fields: ["ขอน้ำหน่อย"]))
        XCTAssertTrue(PhraseSearch.matches(query: "?", fields: ["How much is this?"]))
        XCTAssertTrue(PhraseSearch.matches(query: "50%", fields: ["Discount 50% today"]))
        XCTAssertFalse(PhraseSearch.matches(query: "น้ำ", fields: ["water"]))
    }

    func testSearchWithHugeQueryAndHaystack() {
        let hay = String(repeating: "abc ", count: 50_000)
        XCTAssertTrue(PhraseSearch.matches(query: String(repeating: "abc ", count: 1_000), fields: [hay]))
        XCTAssertFalse(PhraseSearch.matches(query: "zzz", fields: [hay]))
    }

    // MARK: Sprechtempo

    func testSpeechRateSlowHasAFloorAndBeatsClear() {
        XCTAssertEqual(SpeechRate.effective(rate: 1.0, slow: true, clear: false), 0.65, accuracy: 1e-9)
        XCTAssertEqual(SpeechRate.effective(rate: 0.5, slow: true, clear: false), SpeechRate.slowFloor, accuracy: 1e-9)
        XCTAssertEqual(SpeechRate.effective(rate: 1.0, slow: true, clear: true), 0.65, accuracy: 1e-9)
    }

    func testSpeechRateClearOnlyCapsAndNeverRaises() {
        XCTAssertEqual(SpeechRate.effective(rate: 1.0, slow: false, clear: true), SpeechRate.clearCeiling)
        XCTAssertEqual(SpeechRate.effective(rate: 0.3, slow: false, clear: true), 0.3)
        XCTAssertEqual(SpeechRate.effective(rate: 0.9, slow: false, clear: false), 0.9)
    }

    // MARK: Verlauf-Aufbewahrung

    func testRetentionCapExtremes() {
        XCTAssertEqual(Retention.cap(days: Int.min), 2000)
        XCTAssertEqual(Retention.cap(days: Int.max), 2000)
        XCTAssertEqual(Retention.cap(days: 2), 2000)
    }

    func testUndoBufferBoundaryAndReplace() {
        var u = UndoBuffer<[Int]>()
        let t = date(1)
        u.keep([1], now: t, seconds: 8)
        XCTAssertTrue(u.available(at: t.addingTimeInterval(7.99)))
        XCTAssertFalse(u.available(at: t.addingTimeInterval(8)))
        u.keep([2], now: t, seconds: 8)                       // zweites Leeren ersetzt das erste
        XCTAssertEqual(u.take(at: t), [2])
        XCTAssertNil(u.take(at: t))                           // nur einmal zurückholbar
        u.keep([3], now: t); u.drop()
        XCTAssertNil(u.take(at: t))
        u.keep([4], now: t)
        XCTAssertNil(u.take(at: t.addingTimeInterval(60)))    // abgelaufen
        XCTAssertFalse(u.available(at: t))                    // und dabei geleert
    }

    func testLossyDecodingDropsOnlyTheBrokenItem() throws {
        let data = Data(#"[1, "x", 3, null, {"a":1}]"#.utf8)
        let list = try JSONDecoder().decode([Lossy<Int>].self, from: data)
        XCTAssertEqual(list.map(\.value), [1, nil, 3, nil, nil])
    }

    // MARK: Datenschutz-Schalter

    func testSecureCopyAlwaysLocalOnly() {
        for expiring in [true, false] {
            let o = SecureCopy.options(expiring: expiring)
            XCTAssertEqual(o[.localOnly] as? Bool, true)
            XCTAssertEqual(o.count, expiring ? 2 : 1)
        }
        XCTAssertEqual(SecureCopy.lifetime, 120)
    }

    func testShieldPolicyTruthTable() {
        // (shield, active, hideOnCapture, captured) -> sichtbar
        let cases: [(Bool, Bool, Bool, Bool, Bool)] = [
            (false, false, false, false, false), (true, false, false, false, true), (true, true, false, false, false),
            (false, false, true, true, true), (false, false, true, false, false), (true, true, true, true, true),
            (false, true, false, true, false),   // Aufnahme ohne den Schalter verdeckt nichts
        ]
        for (s, a, h, c, expected) in cases {
            XCTAssertEqual(ShieldPolicy.show(shield: s, active: a, hideOnCapture: h, captured: c), expected, "\(s) \(a) \(h) \(c)")
        }
    }

    func testErrorAdviceNeedsAnExactMatch() {
        XCTAssertEqual(ErrorAdvice.action(for: ""), .none)
        let denied = L10n.text("err_denied", lang: "en")!
        XCTAssertEqual(ErrorAdvice.action(for: denied), .systemSettings)
        XCTAssertEqual(ErrorAdvice.action(for: denied + " "), .none)
        XCTAssertEqual(ErrorAdvice.action(for: denied.lowercased() == denied ? denied.uppercased() : denied.lowercased()), .none)
        XCTAssertEqual(ErrorAdvice.action(for: String(repeating: "x", count: 100_000)), .none)
    }

    // MARK: Lernplan / Leitner

    private func source(_ front: String, _ back: String, talk: Bool = false) -> LeitnerDeck.Source {
        .init(front: front, back: back, lang: .th, roman: nil, talk: talk)
    }

    func testLeitnerSyncSkipsEmptySidesAndDuplicatesWithinOneBatch() {
        var d = LeitnerDeck()
        let n = d.sync([source("a", "ก"), source("a2", "ก"), source("", "ข"), source("c", ""), source("d", "ค")], now: date(1))
        XCTAssertEqual(n, 2)
        XCTAssertEqual(d.cards.map(\.front), ["a", "d"])
    }

    func testLeitnerIDIgnoresPunctuationAndCaseOfBack() {
        XCTAssertEqual(source("x", "Thank you!").id, source("y", "thank  YOU").id)
    }

    func testLeitnerBoxIsCappedAndWrongAnswerFallsToBoxOne() {
        var d = LeitnerDeck()
        d.sync([source("a", "ก")], now: date(1))
        let id = d.cards[0].id
        for _ in 0..<9 { d.answer(id, knew: true, now: date(1), calendar: utc) }
        XCTAssertEqual(d.cards[0].box, LeitnerDeck.boxes)
        d.answer(id, knew: false, now: date(1), calendar: utc)
        XCTAssertEqual(d.cards[0].box, 1)
        XCTAssertEqual(d.cards[0].due, date(1))               // Fach 1: gleich wieder dran
    }

    func testLeitnerUnknownIDChangesNothingAndLogsNothing() {
        var d = LeitnerDeck()
        d.sync([source("a", "ก")], now: date(1))
        let before = d
        d.answer("gibt-es-nicht", knew: true, now: date(1), calendar: utc)
        XCTAssertEqual(d, before)
    }

    func testLeitnerDueDateClampsBoxAndUsesStartOfDay() {
        XCTAssertEqual(LeitnerDeck.dueDate(box: 0, from: date(1), calendar: utc), date(1))
        XCTAssertEqual(LeitnerDeck.dueDate(box: -5, from: date(1), calendar: utc), date(1))
        let midnight = date(1, hour: 0)
        XCTAssertEqual(LeitnerDeck.dueDate(box: 2, from: date(1, hour: 23), calendar: utc), utc.date(byAdding: .day, value: 1, to: midnight))
        XCTAssertEqual(LeitnerDeck.dueDate(box: 99, from: date(1), calendar: utc), utc.date(byAdding: .day, value: 14, to: midnight))
    }

    func testLeitnerDueOrdersByBoxThenAge() {
        var d = LeitnerDeck()
        d.sync([source("a", "ก"), source("b", "ข"), source("c", "ค")], now: date(1))
        d.cards[0].box = 3; d.cards[1].box = 1; d.cards[2].box = 1
        d.cards[1].due = date(5); d.cards[2].due = date(2)
        XCTAssertEqual(d.due(now: date(9)).map(\.front), ["c", "b", "a"])
        XCTAssertTrue(d.due(now: date(0)).isEmpty)
        XCTAssertNil(LeitnerDeck().nextDue(after: date(1)))
        XCTAssertEqual(d.nextDue(after: date(3)), date(5))
    }

    func testLeitnerDismissedCardStaysGoneAndIsNotListedTwice() {
        var d = LeitnerDeck()
        let s = source("a", "ก")
        d.sync([s], now: date(1))
        d.dismiss(s.id); d.dismiss(s.id)
        XCTAssertEqual(d.dismissed, [s.id])
        XCTAssertEqual(d.sync([s], now: date(2)), 0)
        XCTAssertTrue(d.cards.isEmpty)
    }

    func testLeitnerPruneKeepsFavoritesAndDropsTalkCardsWithoutDate() {
        var d = LeitnerDeck()
        d.sync([source("fav", "ก"), source("talk", "ข", talk: true)], now: date(1))
        d.cards.append(.init(id: "old", front: "o", back: "o", lang: .th, due: date(1), talk: true, created: nil))
        XCTAssertEqual(d.pruneTalk(olderThan: date(20)), 2)
        XCTAssertEqual(d.cards.map(\.front), ["fav"])
    }

    func testLeitnerDeckFromOldFileWithoutOptionalFieldsDecodes() throws {
        let json = #"{"cards":[{"id":"th|x","front":"a","back":"ก","lang":"th","box":2,"due":0}]}"#
        let d = try JSONDecoder().decode(LeitnerDeck.self, from: Data(json.utf8))
        XCTAssertEqual(d.cards.count, 1)
        XCTAssertNil(d.dismissed); XCTAssertNil(d.log); XCTAssertNil(d.cards[0].talk)
        XCTAssertEqual(d.counts, [0, 1, 0, 0, 0])
    }

    func testLearnSourceFromEntryLimitsAndDirections() {
        let pair = LangPair.standard
        func entry(_ text: String, _ tr: String?, from: Lang = .en, to: Lang = .th) -> Entry {
            Entry(src: from, dst: to, text: text, translation: tr)
        }
        XCTAssertNotNil(LeitnerDeck.Source.from(entry(String(repeating: "a", count: 160), "ก"), pair: pair))
        XCTAssertNil(LeitnerDeck.Source.from(entry(String(repeating: "a", count: 161), "ก"), pair: pair))
        XCTAssertNil(LeitnerDeck.Source.from(entry("hi", ""), pair: pair))
        XCTAssertNil(LeitnerDeck.Source.from(entry("hi", nil), pair: pair))
        XCTAssertNil(LeitnerDeck.Source.from(entry("hi", "x", from: .de, to: .th), pair: pair))
        var failed = entry("hi", "ก"); failed.error = "offline"
        XCTAssertNil(LeitnerDeck.Source.from(failed, pair: pair))
        let rev = LeitnerDeck.Source.from(entry("สวัสดี", "hello", from: .th, to: .en), pair: pair)
        XCTAssertEqual(rev?.front, "hello"); XCTAssertEqual(rev?.back, "สวัสดี"); XCTAssertEqual(rev?.lang, .th)
        XCTAssertEqual(rev?.talk, true)
    }

    // MARK: Sprachpaar-Wechsel

    func testLangPairLoadWithTwoInvalidValuesGivesStandard() {
        XCTAssertEqual(LangPair.load(mine: "xx", partner: "yy"), .standard)
        XCTAssertEqual(LangPair.load(mine: "", partner: ""), .standard)
        XCTAssertEqual(LangPair.load(mine: "th", partner: nil), LangPair(mine: .th, partner: .en))
        XCTAssertEqual(LangPair.load(mine: "en", partner: "en"), LangPair(mine: .en, partner: .th))
    }

    func testLangPairOtherAndFeatures() {
        let p = LangPair(mine: .de, partner: .th)
        XCTAssertEqual(p.other(.de), .th)
        XCTAssertEqual(p.other(.th), .de)
        XCTAssertTrue(p.features.thaiExtras)
        XCTAssertFalse(p.features.voiceCommands)
        XCTAssertTrue(LangPair(mine: .en, partner: .de).features.voiceCommands)
        XCTAssertFalse(LangPair(mine: .en, partner: .de).distinguishable)
        XCTAssertTrue(LangPair.standard.distinguishable)
    }

    func testListenOverrideOnlyForOtherSideAndKnownLanguages() {
        let p = LangPair.standard
        XCTAssertNil(ListenOverride.needed(for: .de, mode: .mine, pair: p))        // nicht im Paar
        XCTAssertNil(ListenOverride.needed(for: .en, mode: .mine, pair: p))        // hört schon
        XCTAssertEqual(ListenOverride.needed(for: .th, mode: .mine, pair: p), .partner)
        XCTAssertEqual(ListenOverride.needed(for: .en, mode: .partner, pair: p), .mine)
    }

    func testRecentPairsDropInvalidAndCapAtLimit() {
        let d = UserDefaults(suiteName: "round16-recent")!
        d.removePersistentDomain(forName: "round16-recent")
        d.set(["en>en", "xx>th", "en>th>de", "garbage", "", "de>th"], forKey: RecentPairs.key)
        XCTAssertEqual(RecentPairs.load(from: d), [LangPair(mine: .de, partner: .th)])
        let langs: [Lang] = [.de, .es, .fr, .ja, .ko, .zh, .vi]
        for l in langs { RecentPairs.remember(.standard, current: LangPair(mine: .en, partner: l), in: d) }
        let list = RecentPairs.load(from: d)
        XCTAssertEqual(list.count, RecentPairs.limit)
        XCTAssertEqual(list.first, .standard)                  // das verlassene Paar steht vorn
        XCTAssertEqual(list[1], LangPair(mine: .en, partner: .vi))
        d.removePersistentDomain(forName: "round16-recent")
    }

    // MARK: Schnellsatz-Widget

    func testWidgetKeepsKnownIDsAndIgnoresStaleOnes() {
        let e = QuickPhrasesEntry.make(ids: ["gone", "Thank you", "also gone"], female: false)
        XCTAssertEqual(e.items.map(\.id), ["Thank you"])
    }

    func testWidgetUnknownCategoryFallsBackToChosenIDs() {
        let e = QuickPhrasesEntry.make(ids: ["Hello"], category: "no-such-category", female: false)
        XCTAssertEqual(e.items.map(\.id), ["Hello"])
    }

    func testWidgetRotationWrapsAroundAndStaysWithinLimit() {
        let hours = (0..<200).map { Date(timeIntervalSince1970: 1_800_000_000 + Double($0) * QuickPhrasesEntry.rotationSeconds) }
        for h in hours {
            let e = QuickPhrasesEntry.make(ids: [], category: "basics", female: true, date: h)
            XCTAssertLessThanOrEqual(e.items.count, QuickPhrasesEntry.maxItems)
            XCTAssertEqual(Set(e.items.map(\.id)).count, e.items.count, "keine Doppelten innerhalb eines Ausschnitts")
        }
    }

    func testWidgetTimelineStartsAtTheHourAndStepsHourly() {
        let now = Date(timeIntervalSince1970: 1_800_000_000 + 1234)
        let t = QuickPhrasesEntry.timeline(ids: [], category: "food", female: false, now: now)
        XCTAssertEqual(t.entries.count, 6)
        let start = (now.timeIntervalSince1970 / 3600).rounded(.down) * 3600
        XCTAssertEqual(t.entries.first?.date.timeIntervalSince1970, start)
        XCTAssertEqual(t.entries.last?.date.timeIntervalSince1970, start + 5 * 3600)
    }

    func testWidgetPairLabelIsEnglishToThai() {
        XCTAssertTrue(WidgetPair.flags.contains("\u{2192}"))
        XCTAssertFalse(WidgetPair.flags.isEmpty)
    }

    // MARK: Zahlen, Rückübersetzung, Bewertungsbitte

    func testThaiNumberWordsEdges() {
        XCTAssertNil(ThaiNumber.words(-1))
        XCTAssertNil(ThaiNumber.words(1_000_000_000))
        XCTAssertEqual(ThaiNumber.words(0), "ศูนย์")
        XCTAssertEqual(ThaiNumber.words(11), "สิบเอ็ด")
        XCTAssertEqual(ThaiNumber.words(20), "ยี่สิบ")
        XCTAssertEqual(ThaiNumber.words(21), "ยี่สิบเอ็ด")
        XCTAssertEqual(ThaiNumber.words(101), "หนึ่งร้อยเอ็ด")
        XCTAssertEqual(ThaiNumber.words(1_000_000), "หนึ่งล้าน")
        XCTAssertEqual(ThaiNumber.words(1_000_001), "หนึ่งล้านเอ็ด")
        XCTAssertNotNil(ThaiNumber.words(999_999_999))
    }

    func testNumberCardRejectsGarbageAndLimitsLength() {
        XCTAssertEqual(NumberCard.append("a", to: "12"), "12")
        XCTAssertEqual(NumberCard.append("5", to: "0"), "5")
        XCTAssertEqual(NumberCard.append(".", to: ""), "0.")
        XCTAssertEqual(NumberCard.append(".", to: "1.5"), "1.5")
        XCTAssertEqual(NumberCard.append("3", to: "1.55"), "1.55")
        XCTAssertEqual(NumberCard.append("9", to: "123456789"), "123456789")
        XCTAssertEqual(NumberCard.append(".", to: "123456789"), "123456789")
    }

    func testBackCheckEmptyAndSymbolOnlyTexts() {
        XCTAssertEqual(BackCheck.similarity("", "!!!"), 1)
        XCTAssertFalse(BackCheck.deviates(original: "", back: "anything"))
        XCTAssertFalse(BackCheck.deviates(original: "🙏🙏🙏🙏🙏🙏🙏🙏🙏", back: "x"))   // keine Buchstaben -> nie warnen
        XCTAssertTrue(BackCheck.deviates(original: "Where is the nearest pharmacy please", back: "Banana elephant window"))
        XCTAssertFalse(BackCheck.deviates(original: "Where is the nearest pharmacy please", back: "WHERE is the nearest pharmacy, please!"))
    }

    func testBackCheckVeryLongTextsFinish() {
        let a = String(repeating: "hello world ", count: 5_000)
        XCTAssertEqual(BackCheck.similarity(a, a), 1)
        XCTAssertFalse(BackCheck.deviates(original: a, back: a))
    }

    func testReviewGateBusyAndVersionRules() {
        var g = ReviewGate()
        g.conversationEnded(translations: 1)
        XCTAssertEqual(g.conversations, 0)                    // zu kurz
        for _ in 0..<ReviewGate.neededConversations { g.conversationEnded(translations: 2) }
        XCTAssertFalse(g.shouldAsk(version: "1", busy: true))
        XCTAssertTrue(g.shouldAsk(version: "1", busy: false))
        g.asked(version: "1")
        for _ in 0..<ReviewGate.neededConversations { g.conversationEnded(translations: 5) }
        XCTAssertFalse(g.shouldAsk(version: "1", busy: false), "höchstens einmal je Version")
        XCTAssertTrue(g.shouldAsk(version: "2", busy: false))
    }

    // MARK: Sprachwahl nach Schrift

    func testTypedLanguagePicksByScriptAndFallsBackOnSymbols() {
        XCTAssertEqual(LanguagePick.ofTyped("สวัสดีครับ"), .th)
        XCTAssertEqual(LanguagePick.ofTyped("hello"), .en)
        XCTAssertEqual(LanguagePick.ofTyped("12345 !!!"), .en)       // nur Zahlen: Standard = meine Sprache
        XCTAssertEqual(LanguagePick.ofTyped(""), .en)
        XCTAssertEqual(LanguagePick.ofTyped("OK ขอบคุณมากครับ Grab"), .th)
        XCTAssertEqual(LanguagePick.ofTyped("hello", pair: LangPair(mine: .de, partner: .en), fallback: .en), .en)
    }
}
