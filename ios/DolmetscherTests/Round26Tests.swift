import XCTest
@testable import Dolmetscher

final class HitCounter: @unchecked Sendable {
    private let l = NSLock(); private var n = 0
    func bump() { l.lock(); n += 1; l.unlock() }
    var value: Int { l.lock(); defer { l.unlock() }; return n }
}

@MainActor
final class Round26Tests: XCTestCase {
    func testNetStatusDeliversToAllSubscribers() {
        let a = HitCounter(), b = HitCounter(), r1 = HitCounter(), r2 = HitCounter()
        let net = NetStatus.shared
        net.onChange { _ in a.bump() }
        net.onChange { _ in b.bump() }
        net.onReconnect { r1.bump() }
        net.onReconnect { r2.bump() }
        net.deliver(was: true, now: false)
        net.deliver(was: false, now: true)
        XCTAssertEqual(a.value, 2); XCTAssertEqual(b.value, 2)
        XCTAssertEqual(r1.value, 1); XCTAssertEqual(r2.value, 1)
    }

    func testLearnCardSurvivesPolitenessChange() {
        let p = Phrase(en: "Thank you", th: "ขอบคุณ{p}", roman: "khop khun", category: "basics")
        var deck = LeitnerDeck()
        deck.sync([.from(p, politeness: .male)])
        XCTAssertEqual(deck.cards.count, 1)
        deck.answer(deck.cards[0].id, knew: true)
        let box = deck.cards[0].box
        deck.sync([.from(p, politeness: .female)])
        XCTAssertEqual(deck.cards.count, 1, "kein Duplikat nach Wechsel ครับ -> ค่ะ")
        XCTAssertEqual(deck.cards[0].box, box)
        XCTAssertTrue(deck.cards[0].back.hasSuffix("ค่ะ"), deck.cards[0].back)
    }

    func testLegacyCardIsMigratedToStableID() {
        let p = Phrase(en: "Thank you", th: "ขอบคุณ{p}", roman: "khop khun", category: "basics")
        let src = LeitnerDeck.Source.from(p, politeness: .male)
        var deck = LeitnerDeck()
        deck.cards = [.init(id: src.legacyID, front: src.front, back: src.back, lang: src.lang, roman: nil, box: 3, due: Date())]
        deck.dismissed = ["th|alte karte"]
        XCTAssertEqual(deck.sync([src]), 0, "alte Karte wird übernommen, nicht neu angelegt")
        XCTAssertEqual(deck.cards.count, 1)
        XCTAssertEqual(deck.cards[0].id, src.id)
        XCTAssertEqual(deck.cards[0].box, 3)
        XCTAssertNotEqual(src.id, src.legacyID)
    }

    func testLegacyDismissedCardStaysDismissed() {
        let p = Phrase(en: "Hello", th: "สวัสดี{p}", roman: "", category: "basics")
        let src = LeitnerDeck.Source.from(p, politeness: .male)
        var deck = LeitnerDeck()
        deck.dismissed = [src.legacyID]
        XCTAssertEqual(deck.sync([src]), 0)
        XCTAssertTrue(deck.cards.isEmpty)
        XCTAssertTrue(deck.dismissed?.contains(src.id) ?? false)
    }

    func testNeutralStripsThaiParticlesOnly() {
        XCTAssertEqual(LeitnerDeck.Source.neutral("ขอบคุณครับ", lang: .th), "ขอบคุณ")
        XCTAssertEqual(LeitnerDeck.Source.neutral("ขอบคุณค่ะ", lang: .th), "ขอบคุณ")
        XCTAssertEqual(LeitnerDeck.Source.neutral("Thanks ครับ", lang: .en), "Thanks ครับ")
    }

    func testOpenFavoriteFiltersPhrasebook() {
        let dir = FileManager.default.temporaryDirectory.appending(path: "r26-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let m = InterpreterModel(files: JSONStore(dir: dir))
        let p = Phrase(en: "Where is the pier?", th: "ท่าเรืออยู่ที่ไหน{q}", roman: "", category: "basics")
        m.favorites = [p]
        m.openFavorite(key: p.favoriteKey)
        XCTAssertEqual(m.sheet, .phrasebook)
        XCTAssertEqual(m.phrasebookQuery, "Where is the pier?")
        m.openFavorite(key: "gibt-es-nicht")
        XCTAssertNil(m.phrasebookQuery)
    }
}

final class Round27Tests: XCTestCase {
    func testSuggestedPacksExistAndAreStableForEveryHour() {
        let packs = Phrasebook.packs
        XCTAssertFalse(packs.isEmpty)
        for h in 0..<24 {
            let ids = ScenarioSuggest.packIDs(hour: h)
            XCTAssertEqual(ids.count, 3, "h=\(h)")
            XCTAssertEqual(ScenarioSuggest.packs(hour: h, available: packs).map(\.id), ids, "unbekanntes Paket bei h=\(h)")
        }
        XCTAssertEqual(ScenarioSuggest.packs(hour: 12, available: []).count, 0)
    }

    func testPhraseOfDayIsDeterministicAndRotates() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let d1 = cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))!
        let d2 = cal.date(byAdding: .day, value: 1, to: d1)!
        let a = PhraseOfDay.phrase(for: d1, calendar: cal), b = PhraseOfDay.phrase(for: d2, calendar: cal)
        XCTAssertEqual(a?.en, PhraseOfDay.phrase(for: d1, calendar: cal)?.en)
        XCTAssertNotEqual(a?.en, b?.en)
        let n = Phrasebook.builtIn.count
        XCTAssertEqual((PhraseOfDay.index(for: d2, count: n, calendar: cal) - PhraseOfDay.index(for: d1, count: n, calendar: cal) + n) % n, 1)
        XCTAssertNil(PhraseOfDay.phrase(for: d1, in: [], calendar: cal))
    }

    func testFireDatesAreFutureAndAtNine() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 10))!   // 9 Uhr heute ist schon vorbei
        let dates = PhraseOfDay.fireDates(from: now, calendar: cal)
        XCTAssertEqual(dates.count, PhraseOfDay.days - 1)
        XCTAssertTrue(dates.allSatisfy { $0 > now && cal.component(.hour, from: $0) == 9 })
        let morning = cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 7))!
        XCTAssertEqual(PhraseOfDay.fireDates(from: morning, calendar: cal).count, PhraseOfDay.days)
        XCTAssertEqual(PhraseOfDay.identifier(for: now, calendar: cal), "phrase-of-day-20261120")
    }

    func testTextsPresent() {
        for k in ["pod_title", "pod_toggle", "pod_denied", "sc_now"] { XCTAssertEqual(L10n.round25[k]?.count, 10, k) }
    }
}
