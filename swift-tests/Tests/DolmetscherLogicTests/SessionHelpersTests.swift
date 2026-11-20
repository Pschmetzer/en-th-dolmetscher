import XCTest
@testable import DolmetscherLogic

final class SessionHelpersTests: XCTestCase {
    func testNameSuggest() {
        let r = NameSuggest.candidates(texts: ["Hello. I met Somchai at Siam Square.", "Then Somchai left. Thanks, Anna's here"],
                                       known: ["anna"])
        XCTAssertEqual(r.first, "Somchai")
        XCTAssertTrue(r.contains("Siam"))
        XCTAssertFalse(r.contains("Hello"))
        XCTAssertFalse(r.contains("Then"))
        XCTAssertFalse(r.contains("Anna's"))
    }

    func testPhraseSearch() {
        let src = [PhraseSource(id: "a", name: "Hotel", phrases: [("Where is the room?", "ห้องอยู่ไหน", false),
                                                                 ("Call a doctor", "เรียกหมอ", true)])]
        XCTAssertEqual(PhraseSearch.search(src, query: "  ").count, 0)
        XCTAssertEqual(PhraseSearch.search(src, query: "hotel").first?.critical, true)
        XCTAssertEqual(PhraseSearch.search(src, query: "ROOM").count, 1)
        XCTAssertEqual(PhraseSearch.search(src, query: "หมอ").count, 1)
    }

    func testScenario() {
        XCTAssertEqual(ScenarioSuggest.suggest(hour: 8, available: ["taxi", "hotel"]), ["hotel", "taxi"])
        XCTAssertEqual(ScenarioSuggest.suggest(hour: 3, available: []), [])
    }
}
