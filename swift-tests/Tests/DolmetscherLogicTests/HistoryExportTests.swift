import XCTest
@testable import DolmetscherLogic

final class HistoryExportTests: XCTestCase {
    private func session() -> HistorySession {
        let rows = [
            HistoryRow(time: Date(timeIntervalSince1970: 0), session: "s", lang: "en", text: "Where *is* it?",
                       translation: "อยู่ที่ไหน", translit: "yu thi nai", confidence: nil, provider: "claude", role: nil, speaker: nil),
            HistoryRow(time: Date(timeIntervalSince1970: 65), session: "s", lang: "th", text: "ok", translation: "",
                       translit: "", confidence: nil, provider: nil, role: nil, speaker: "=cmd"),
        ]
        return HistorySession(id: "s", start: rows[0].time, rows: rows)
    }

    func testMarkdownHasTimestampsAndEscapes() {
        let md = HistoryLogic.markdown(session(), title: "A_B", timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertTrue(md.hasPrefix("# A\\_B\n\n"))
        XCTAssertTrue(md.contains("**00:00:00 · EN**: Where \\*is\\* it?"))
        XCTAssertTrue(md.contains("**00:01:05 · TH**: ok"))
        XCTAssertTrue(md.contains("→ อยู่ที่ไหน"))
        XCTAssertTrue(md.contains("_yu thi nai_"))
    }

    func testCsvNeutralizesFormulasAndHasHeader() {
        let csv = HistoryLogic.csv(session())
        XCTAssertTrue(csv.hasPrefix("time,lang,text,translation,translit,provider,speaker\n"))
        XCTAssertTrue(csv.contains("\"'=cmd\""))
        XCTAssertEqual(csv.split(separator: "\n").count, 3)
    }
}
