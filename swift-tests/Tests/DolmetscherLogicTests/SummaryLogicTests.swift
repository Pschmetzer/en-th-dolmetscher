import XCTest
@testable import DolmetscherLogic

final class SummaryLogicTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 0)
    func item(_ text: String, out: String = "", lang: String = "en", at: Double = 0) -> ExportItem {
        ExportItem(at: t0.addingTimeInterval(at), lang: lang, to: lang == "en" ? "th" : "en", text: text, out: out, translated: !out.isEmpty,
                   speaker: nil, dur: nil, readyS: nil)
    }

    func testSentencesAndQuestion() {
        XCTAssertEqual(SummaryLogic.sentences("Hello. Where is it? Fine!"), ["Hello.", "Where is it?", "Fine!"])
        XCTAssertTrue(SummaryLogic.isQuestion("Where is it?"))
        XCTAssertTrue(SummaryLogic.isQuestion("ราคาเท่าไร"))
        XCTAssertTrue(SummaryLogic.isQuestion("ไปได้ไหม"))
        XCTAssertFalse(SummaryLogic.isQuestion("I am here."))
    }

    func testTodoDetection() {
        XCTAssertTrue(SummaryLogic.isTodo("Don't forget the passport."))
        XCTAssertTrue(SummaryLogic.isTodo("Ich muss morgen früh los"))
        XCTAssertTrue(SummaryLogic.isTodo("พรุ่งนี้เจอกันนะ"))
        XCTAssertFalse(SummaryLogic.isTodo("Do I need to bring it?"))   // Frage ist kein To-do
        XCTAssertFalse(SummaryLogic.isTodo("Nice weather."))
    }

    func testSummarize() {
        let items = [
            item("Where is the pharmacy?", out: "ร้านขายยาอยู่ที่ไหน", at: 0),
            item("We need to buy water. It costs 40 baht.", out: "ต้องซื้อน้ำ", at: 120),
            item("The room is 1,200 baht, 1200 baht.", out: "ห้อง ฿1,200", at: 240),
            item("I will call you at 14:30.", out: "", at: 300),
        ]
        let s = SummaryLogic.summarize(items)
        XCTAssertEqual(s.turns, 4)
        XCTAssertEqual(s.minutes, 5)
        XCTAssertEqual(s.languages["en"], 4)
        XCTAssertEqual(s.questions, ["Where is the pharmacy?"])
        XCTAssertEqual(s.todos, ["We need to buy water.", "I will call you at 14:30."])
        XCTAssertEqual(s.prices.map(\.amount), [40, 1200])
        XCTAssertTrue(s.numbers.contains("14:30"))
        XCTAssertFalse(s.numbers.contains("1,200"))
    }

    func testUniqueAndLimit() {
        let items = (0..<30).map { item("We need to do task \($0 % 3).", at: Double($0)) }
        let s = SummaryLogic.summarize(items, limit: 2)
        XCTAssertEqual(s.todos.count, 2)
    }

    func testEmpty() {
        let s = SummaryLogic.summarize([])
        XCTAssertEqual(s, ConversationSummary())
    }

    func testMarkdown() {
        var s = ConversationSummary()
        s.turns = 3; s.minutes = 2; s.languages = ["en": 2, "th": 1]
        s.todos = ["Buy *water*"]
        s.prices = [PriceMention(amount: 365, currency: .thb, raw: "365 baht")]
        let md = SummaryLogic.markdown(s, title: "Taxi", labels: ["turns": "Turns", "minutes": "Min", "todos": "To-dos", "prices": "Prices"], rate: 36.5)
        XCTAssertTrue(md.hasPrefix("# Taxi"))
        XCTAssertTrue(md.contains("Turns: 3 · Min: 2 · EN 2, TH 1"))
        XCTAssertTrue(md.contains("- [ ] Buy \\*water\\*"))
        XCTAssertTrue(md.contains("365 ฿ ≈ 10 €"))
        XCTAssertFalse(md.contains("## questions"))
    }

    func testPlain() {
        var s = ConversationSummary()
        s.todos = ["a"]; s.numbers = ["14:30"]
        XCTAssertEqual(SummaryLogic.plain(s, labels: ["todos": "T", "numbers": "N"]), "T:\n• a\n\nN:\n• 14:30")
    }
}
