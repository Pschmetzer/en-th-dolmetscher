import XCTest
@testable import DolmetscherLogic

final class HistoryStatsTests: XCTestCase {
    func testStats() {
        func row(_ t: Double, _ x: String) -> HistoryRow {
            HistoryRow(time: Date(timeIntervalSince1970: t), session: "s", lang: "en", text: x, translation: "", translit: "",
                       confidence: nil, provider: nil, role: nil, speaker: nil)
        }
        let rows = [row(0, "Hello there"), row(10, "hello  there"), row(86400 * 2, "Thanks")]
        let st = HistoryLogic.stats([HistorySession(id: "s", start: rows[0].time, rows: rows)], timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(st.utterances, 3)
        XCTAssertEqual(st.sessions, 1)
        XCTAssertEqual(st.words, 5)
        XCTAssertEqual(st.perDay.map { $0.1 }, [2, 1])
        XCTAssertEqual(st.top.first?.1, 2)
    }
}
