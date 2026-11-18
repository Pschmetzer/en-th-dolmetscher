import XCTest
@testable import Dolmetscher

/// Runde 18: Verlauf – Suche, Filter, Tagesgruppen, Auswahl, Aufbewahrungshinweis.
final class Round18Tests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private let now = Date(timeIntervalSince1970: 1_767_268_800) // 2026-01-01 12:00 UTC

    private func entry(_ text: String, _ tr: String? = nil, src: Lang = .en, dst: Lang = .th, daysAgo: Double = 0) -> Entry {
        Entry(date: now.addingTimeInterval(-daysAgo * 86_400), src: src, dst: dst, text: text, translation: tr)
    }

    func testSearchIgnoresCaseAndAccentsInTextAndTranslation() {
        let a = entry("Café please", "กาแฟ"), b = entry("Water", "น้ำ")
        var f = HistoryFilter(); f.query = "cafe"
        XCTAssertEqual(HistoryLogic.apply(f, to: [a, b], isFavorite: { _ in false }, now: now, calendar: cal).map(\.id), [a.id])
        f.query = "น้ำ"
        XCTAssertEqual(HistoryLogic.apply(f, to: [a, b], isFavorite: { _ in false }, now: now, calendar: cal).map(\.id), [b.id])
        f.query = "   "
        XCTAssertEqual(HistoryLogic.apply(f, to: [a, b], isFavorite: { _ in false }, now: now, calendar: cal).count, 2)
    }

    func testPairFilterIgnoresDirection() {
        let a = entry("a", src: .en, dst: .th), b = entry("b", src: .th, dst: .en), c = entry("c", src: .en, dst: .de)
        var f = HistoryFilter(); f.pair = HistoryPair(.th, .en)
        XCTAssertEqual(HistoryLogic.apply(f, to: [a, b, c], isFavorite: { _ in false }, now: now, calendar: cal).count, 2)
        XCTAssertEqual(HistoryLogic.pairs(in: [a, b, c]).first, HistoryPair(.en, .th))
    }

    func testRangeBoundariesAndFavorites() {
        let today = entry("t", daysAgo: 0), week = entry("w", daysAgo: 6), old = entry("o", daysAgo: 7), ancient = entry("x", daysAgo: 40)
        let all = [ancient, old, week, today]
        func ids(_ r: HistoryRange) -> Int {
            var f = HistoryFilter(); f.range = r
            return HistoryLogic.apply(f, to: all, isFavorite: { _ in false }, now: now, calendar: cal).count
        }
        XCTAssertEqual(ids(.all), 4); XCTAssertEqual(ids(.today), 1); XCTAssertEqual(ids(.week), 2); XCTAssertEqual(ids(.month), 3)
        var f = HistoryFilter(); f.favoritesOnly = true
        XCTAssertEqual(HistoryLogic.apply(f, to: all, isFavorite: { $0.id == old.id }, now: now, calendar: cal).map(\.id), [old.id])
        XCTAssertTrue(f.isActive); XCTAssertEqual(f.activeCount, 1)
        XCTAssertFalse(HistoryFilter().isActive)
    }

    func testGroupsNewestDayFirstAndOrderInsideDay() {
        let a = entry("a", daysAgo: 0.1), b = entry("b", daysAgo: 0.2), c = entry("c", daysAgo: 1.2)
        let g = HistoryLogic.groups([a, b, c], calendar: cal)
        XCTAssertEqual(g.count, 2)
        XCTAssertEqual(g[0].entries.map(\.id), [b.id, a.id])
        XCTAssertGreaterThan(g[0].day, g[1].day)
        XCTAssertEqual(HistoryLogic.label(for: g[0].day, now: now, calendar: cal), .today)
        XCTAssertEqual(HistoryLogic.label(for: g[1].day, now: now, calendar: cal), .yesterday)
        XCTAssertEqual(HistoryLogic.label(for: now.addingTimeInterval(-5 * 86_400), now: now, calendar: cal), .date(now.addingTimeInterval(-5 * 86_400)))
        XCTAssertTrue(HistoryLogic.groups([], calendar: cal).isEmpty)
    }

    func testEmptyStates() {
        XCTAssertEqual(HistoryLogic.empty(total: 0, shown: 0), .nothingSaved)
        XCTAssertEqual(HistoryLogic.empty(total: 3, shown: 0), .noMatches)
        XCTAssertEqual(HistoryLogic.empty(total: 3, shown: 2), .none)
    }

    func testRetentionNote() {
        XCTAssertEqual(HistoryLogic.retention(days: 0).key, "hs_keep_none")
        XCTAssertEqual(HistoryLogic.retention(days: 1).key, "hs_keep_1")
        XCTAssertEqual(HistoryLogic.retention(days: -1).key, "hs_keep_forever")
        XCTAssertEqual(HistoryLogic.retention(days: 30).count, 30)
    }

    func testSelectionKeepsOrderDropsUnknownAndToggleAll() {
        let a = entry("a"), b = entry("b"), c = entry("c")
        XCTAssertEqual(HistoryLogic.selected([a, b, c], ids: [c.id, a.id, UUID()]).map(\.id), [a.id, c.id])
        let all = HistoryLogic.toggleAll(visible: [a, b], selection: [c.id])
        XCTAssertEqual(all, [a.id, b.id, c.id])
        XCTAssertEqual(HistoryLogic.toggleAll(visible: [a, b], selection: all), [c.id])
        XCTAssertTrue(HistoryLogic.toggleAll(visible: [], selection: []).isEmpty)
    }

    func testTextsCompleteInAllLanguages() {
        let langs = ["de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id"]
        XCTAssertFalse(L10n.round18.isEmpty)
        for (key, row) in L10n.round18 {
            XCTAssertEqual(Set(row.keys), Set(langs), key)
            XCTAssertTrue(row.values.allSatisfy { !$0.isEmpty }, key)
            XCTAssertTrue(row.values.allSatisfy { $0.components(separatedBy: "%@").count == (row["en"] ?? "").components(separatedBy: "%@").count }, key)
        }
        for r in HistoryRange.allCases { XCTAssertNotNil(L10n.round18[r.textKey], r.textKey) }
    }
}
