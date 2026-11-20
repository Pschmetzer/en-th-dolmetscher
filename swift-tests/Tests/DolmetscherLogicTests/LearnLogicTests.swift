import XCTest
@testable import DolmetscherLogic

final class LearnLogicTests: XCTestCase {
    func item(_ text: String, _ out: String, lang: String = "en", to: String = "th", translated: Bool = true) -> ExportItem {
        ExportItem(at: Date(timeIntervalSince1970: 0), lang: lang, to: to, text: text, out: out, translated: translated,
                   speaker: nil, dur: nil, readyS: nil)
    }

    func testWordsLatin() {
        XCTAssertEqual(LearnLogic.words("Where is the station?"), ["Where", "is", "the", "station"])
        XCTAssertEqual(LearnLogic.tokens("a b").map(\.index), [0, 1])
        XCTAssertTrue(LearnLogic.words("  ?! ").isEmpty)
    }

    func testWordsThaiSplits() {
        let w = LearnLogic.words("ผมอยากไปสถานีรถไฟ")
        XCTAssertGreaterThan(w.count, 1)
        XCTAssertEqual(w.joined(), "ผมอยากไปสถานีรถไฟ")
    }

    func testCloze() {
        let c = LearnLogic.cloze("Where is the station?", hiding: 3)
        XCTAssertEqual(c?.answer, "station")
        XCTAssertEqual(c?.prompt, "Where is the _______?")
        XCTAssertNil(LearnLogic.cloze("Hello", hiding: 0))
        XCTAssertNil(LearnLogic.cloze("a b c", hiding: 9))
    }

    func testClozeRepeatedWordHitsRightOccurrence() {
        let c = LearnLogic.cloze("go go home", hiding: 1)
        XCTAssertEqual(c?.prompt, "go ___ home")
    }

    func testDefaultClozeIndex() {
        XCTAssertEqual(LearnLogic.defaultClozeIndex("I need water now"), 2)
        XCTAssertNil(LearnLogic.defaultClozeIndex("Hi"))
    }

    func testCards() {
        let items = [item("Hello", "สวัสดี"), item("Hello", "สวัสดีครับ"), item("พรุ่งนี้", "tomorrow", lang: "th", to: "en"),
                     item("raw", "", translated: false), item("", "x")]
        XCTAssertEqual(LearnLogic.cards(items, frontLang: nil).map(\.front), ["Hello", "พรุ่งนี้"])
        let th = LearnLogic.cards(items, frontLang: "th")
        XCTAssertEqual(th.map(\.front), ["สวัสดี", "สวัสดีครับ", "พรุ่งนี้"])
        XCTAssertEqual(th[0].back, "Hello")
        XCTAssertEqual(th[0].tag, "dolmetscher th")
        XCTAssertTrue(LearnLogic.cards(items, frontLang: "de").isEmpty)
    }

    func testAnkiCSV() {
        let csv = LearnLogic.ankiCSV([.init(front: "A \"q\"", back: "x\ny", tag: "dolmetscher en")])
        XCTAssertTrue(csv.hasPrefix("#separator:comma\n"))
        XCTAssertTrue(csv.hasSuffix("\"A \"\"q\"\"\",\"x<br>y\",\"dolmetscher en\"\n"))
    }
}
