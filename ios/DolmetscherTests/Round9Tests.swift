import XCTest
@testable import Dolmetscher

/// Runde 9: CSV-Schutz, Satzbuch-Suche, Live-Aktivität, Unterbrechungen.
final class Round9Tests: XCTestCase {
    func testCSVCellNeutralizesFormulas() {
        XCTAssertEqual(CSVSafe.cell("=1+1"), "'=1+1")
        XCTAssertEqual(CSVSafe.cell("+66"), "'+66")
        XCTAssertEqual(CSVSafe.cell("-x"), "'-x")
        XCTAssertEqual(CSVSafe.cell("@SUM(A1)"), "'@SUM(A1)")
        XCTAssertEqual(CSVSafe.cell("Hello = world"), "Hello = world")
        XCTAssertEqual(CSVSafe.cell(""), "")
        XCTAssertEqual(CSVSafe.cell("สวัสดี"), "สวัสดี")
    }

    func testCSVFileNameCarriesTheDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d = cal.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
        XCTAssertEqual(CSVSafe.fileName(now: d, calendar: cal), "Dolmetscher-2026-03-09.csv")
    }

    func testSearchIgnoresCaseAccentsAndOrder() {
        let fields = ["Where is the café?", "ร้านกาแฟอยู่ที่ไหน", "Wo ist das Café?", "ran kafae yu thi nai"]
        XCTAssertTrue(PhraseSearch.matches(query: "CAFE", fields: fields))
        XCTAssertTrue(PhraseSearch.matches(query: "is where", fields: fields))
        XCTAssertTrue(PhraseSearch.matches(query: "kafae wo", fields: fields))
        XCTAssertTrue(PhraseSearch.matches(query: "ร้านกาแฟ", fields: fields))
        XCTAssertTrue(PhraseSearch.matches(query: "   ", fields: fields))
        XCTAssertFalse(PhraseSearch.matches(query: "taxi", fields: fields))
        XCTAssertFalse(PhraseSearch.matches(query: "cafe taxi", fields: fields))
    }

    @MainActor func testLiveActivityGoesStaleAfterTheWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(LiveActivityController.staleDate(now: now).timeIntervalSince(now), TimeInterval(LiveActivityController.staleMinutes * 60))
    }

    func testInterruptedStatusHasASymbol() {
        XCTAssertFalse(ListeningActivityAttributes.Status.interrupted.symbol.isEmpty)
        XCTAssertEqual(WidgetTexts.table["w_stale"]?.count, WidgetTexts.languages.count)
    }

    func testRound9TextsAreCompleteAndNew() {
        for (key, row) in L10n.round9 {
            XCTAssertNil(L10n.round8[key]); XCTAssertNil(L10n.round7[key]); XCTAssertNil(L10n.table[key])
            for lang in L10n.languages { XCTAssertFalse((row[lang] ?? "").isEmpty, "\(lang): \(key)") }
        }
        XCTAssertNotNil(L10n.round9["interrupt_paused"]); XCTAssertNotNil(L10n.round9["route_lost"])
    }

    func testSpeechRateSlowAndClear() {
        XCTAssertEqual(SpeechRate.effective(rate: 0.5, slow: false, clear: false), 0.5)
        XCTAssertEqual(SpeechRate.effective(rate: 0.8, slow: true, clear: false), 0.8 * SpeechRate.slowFactor, accuracy: 0.0001)
        XCTAssertEqual(SpeechRate.effective(rate: 0.4, slow: true, clear: true), SpeechRate.slowFloor)
        XCTAssertEqual(SpeechRate.effective(rate: 0.9, slow: false, clear: true), SpeechRate.clearCeiling)
    }

    func testHelpGuideTextsExist() {
        for s in HelpGuide.steps { XCTAssertNotNil(L10n.round9[s.title]); XCTAssertNotNil(L10n.round9[s.body]) }
        XCTAssertNotNil(L10n.round9["help_title"])
    }
}
