import XCTest
@testable import DolmetscherLogic

final class HistoryTests: XCTestCase {
    private func row(_ t: TimeInterval, _ session: String, text: String = "hi", tr: String = "", lang: String = "en",
                     provider: String? = nil, role: String? = nil) -> HistoryRow {
        HistoryRow(time: Date(timeIntervalSince1970: t), session: session, lang: lang, text: text, translation: tr,
                   translit: "", confidence: nil, provider: provider, role: role, speaker: nil)
    }

    func testParseSkipsInvalidAndNormalizesRole() {
        let json = """
        [{"time":"2026-01-02T03:04:05Z","session":"a","text":"x","role":"me"},
         {"time":"kaputt","session":"a"},
         {"session":"a"},
         {"time":"2026-01-02T03:04:06.250Z","session":"a","role":"boss"}]
        """
        let rows = HistoryLogic.parse(Data(json.utf8))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].role, "me")
        XCTAssertNil(rows[1].role)
    }

    func testSessionsNewestFirstRowsChronological() {
        let s = HistoryLogic.sessions([row(10, "old"), row(30, "new"), row(20, "new")])
        XCTAssertEqual(s.map(\.id), ["new", "old"])
        XCTAssertEqual(s[0].rows.map { $0.time.timeIntervalSince1970 }, [20, 30])
    }

    func testNumberWarning() {
        XCTAssertTrue(HistoryLogic.hasNumberWarning(row(0, "a", text: "Preis 250", tr: "price 520")))
        XCTAssertFalse(HistoryLogic.hasNumberWarning(row(0, "a", text: "Preis 250", tr: "price 250")))
        XCTAssertFalse(HistoryLogic.hasNumberWarning(row(0, "a", text: "250", tr: "")))   // ohne Übersetzung keine Warnung
    }

    func testFilterIsDiacriticAndCaseInsensitive() {
        var f = HistoryFilter(); f.query = "CAFE"
        XCTAssertTrue(HistoryLogic.matches(row(0, "a", text: "ein Café"), f))
        f.query = "tee"
        XCTAssertFalse(HistoryLogic.matches(row(0, "a", text: "ein Café"), f))
    }

    func testFilterByLangRoleAndWeak() {
        var f = HistoryFilter(); f.lang = "th"
        XCTAssertFalse(HistoryLogic.matches(row(0, "a", lang: "en"), f))
        f = HistoryFilter(); f.weakTranslation = true
        XCTAssertTrue(HistoryLogic.matches(row(0, "a", provider: "mymemory"), f))
        XCTAssertFalse(HistoryLogic.matches(row(0, "a", provider: "claude"), f))
        XCTAssertTrue(HistoryFilter(query: "x").isActive)
        XCTAssertFalse(HistoryFilter().isActive)
    }

    func testMetaManagement() {
        var m = HistoryMeta()
        m = HistoryLogic.renamed(m, id: "a", to: "  Arzt  ")
        XCTAssertEqual(m.names["a"], "Arzt")
        m = HistoryLogic.renamed(m, id: "a", to: " ")
        XCTAssertNil(m.names["a"])
        m = HistoryLogic.toggledFavorite(m, id: "a")
        m = HistoryLogic.hiding(m, id: "b")
        XCTAssertEqual(HistoryLogic.pruned(m, keeping: ["b"]).favorites, [])
        XCTAssertEqual(HistoryLogic.pruned(m, keeping: ["b"]).hidden, ["b"])
        XCTAssertTrue(HistoryLogic.restoring(m, id: "b").hidden.isEmpty)
    }

    func testNavigationHelpers() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(HistoryLogic.moved(ids, from: nil, by: 1), "a")
        XCTAssertEqual(HistoryLogic.moved(ids, from: nil, by: -1), "c")
        XCTAssertEqual(HistoryLogic.moved(ids, from: "c", by: 1), "c")
        XCTAssertEqual(HistoryLogic.neighbor(ids, of: "b"), "c")
        XCTAssertEqual(HistoryLogic.neighbor(ids, of: "c"), "b")
        XCTAssertNil(HistoryLogic.neighbor(["a"], of: "a"))
    }

    func testPreviewTruncates() {
        let s = HistorySession(id: "a", start: Date(), rows: [row(0, "a", text: String(repeating: "y", count: 200))])
        XCTAssertEqual(HistoryLogic.preview(s, limit: 10), String(repeating: "y", count: 10) + "…")
    }
}
