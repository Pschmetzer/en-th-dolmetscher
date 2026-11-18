import XCTest
@testable import Dolmetscher

/// Runde 11: Widgets – Auswahl, Rotation, Zeitleiste, Datenschutz, Texte.
final class Round11Tests: XCTestCase {
    func testDefaultSelectionWhenNothingChosen() {
        let e = QuickPhrasesEntry.make(ids: [], female: false)
        XCTAssertEqual(e.items.map(\.id), QuickPhrasesEntry.defaultIDs)
    }

    func testStaleIdsFallBackToDefaults() {
        XCTAssertEqual(QuickPhrasesEntry.make(ids: ["gone"], female: false).items.count, QuickPhrasesEntry.defaultIDs.count)
    }

    func testCategoryOnlyShowsThatCategoryAndRotates() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let a = QuickPhrasesEntry.make(ids: [], category: "food", female: false, date: t0)
        let b = QuickPhrasesEntry.make(ids: [], category: "food", female: false, date: t0.addingTimeInterval(3600))
        let food = Set(PhraseData.all.filter { $0.category == "food" }.map(\.en))
        XCTAssertTrue(a.items.allSatisfy { food.contains($0.id) })
        XCTAssertEqual(a.items.count, QuickPhrasesEntry.maxItems)
        XCTAssertNotEqual(a.items.map(\.id), b.items.map(\.id))
    }

    func testTimelineIsStaticForChosenAndHourlyForCategory() {
        let fixed = QuickPhrasesEntry.timeline(ids: [], category: nil, female: false)
        XCTAssertEqual(fixed.entries.count, 1)
        let rotating = QuickPhrasesEntry.timeline(ids: [], category: "basics", female: false)
        XCTAssertEqual(rotating.entries.count, 6)
        XCTAssertEqual(rotating.entries[1].date.timeIntervalSince(rotating.entries[0].date), 3600)
    }

    func testFemaleFormIsApplied() {
        let m = QuickPhrasesEntry.make(ids: ["Thank you"], female: false).items[0].thai
        let f = QuickPhrasesEntry.make(ids: ["Thank you"], female: true).items[0].thai
        XCTAssertNotEqual(m, f)
    }

    func testEveryWidgetTextExistsInAllLanguages() {
        for (key, row) in WidgetTexts.table {
            XCTAssertEqual(Set(row.keys), Set(WidgetTexts.languages), key)
            XCTAssertTrue(row.values.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, key)
        }
    }
}
