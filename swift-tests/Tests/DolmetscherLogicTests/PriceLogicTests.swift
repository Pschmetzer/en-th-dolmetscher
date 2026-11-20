import XCTest
@testable import DolmetscherLogic

final class PriceLogicTests: XCTestCase {
    func testParseAmountSeparators() {
        XCTAssertEqual(PriceLogic.parseAmount("1,200"), 1200)
        XCTAssertEqual(PriceLogic.parseAmount("1.200,50"), 1200.5)
        XCTAssertEqual(PriceLogic.parseAmount("1,200.50"), 1200.5)
        XCTAssertEqual(PriceLogic.parseAmount("12,50"), 12.5)
        XCTAssertEqual(PriceLogic.parseAmount("12.5"), 12.5)
        XCTAssertEqual(PriceLogic.parseAmount("1 200"), 1200)
        XCTAssertEqual(PriceLogic.parseAmount("๑๒๐"), 120)
        XCTAssertEqual(PriceLogic.parseAmount("1,200,000"), 1_200_000)
        XCTAssertNil(PriceLogic.parseAmount("abc"))
        XCTAssertNil(PriceLogic.parseAmount(""))
        XCTAssertNil(PriceLogic.parseAmount(",,"))
    }

    func testParseRate() {
        XCTAssertEqual(PriceLogic.parseRate(" 36,5 "), 36.5)
        XCTAssertNil(PriceLogic.parseRate("0"))
        XCTAssertNil(PriceLogic.parseRate("5000"))
        XCTAssertNil(PriceLogic.parseRate("x"))
    }

    func testMentionsWithCurrency() {
        let m = PriceLogic.mentions(in: "That is 1,200 baht, or 35 EUR. Maybe ฿500 too, and บาท 80.")
        XCTAssertEqual(m.map(\.amount), [1200, 35, 500, 80])
        XCTAssertEqual(m.map(\.currency), [.thb, .eur, .thb, .thb])
    }

    func testMentionThaiWord() {
        let m = PriceLogic.mentions(in: "ราคา 300 บาท ครับ")
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m[0].amount, 300)
        XCTAssertEqual(m[0].currency, .thb)
    }

    func testNoOverlapDuplicate() {
        // "฿500" und "500 baht" dürfen dieselbe Zahl nicht zweimal liefern
        XCTAssertEqual(PriceLogic.mentions(in: "฿500 baht").count, 1)
    }

    func testBareNumbersOptIn() {
        XCTAssertTrue(PriceLogic.mentions(in: "the room is 800").isEmpty)
        let m = PriceLogic.mentions(in: "the room is 800 and 5 people", includeBare: true)
        XCTAssertEqual(m.map(\.amount), [800])
        XCTAssertNil(m[0].currency)
    }

    func testWordBoundaryNotEuropean() {
        XCTAssertTrue(PriceLogic.mentions(in: "I like 3 eurozone things").isEmpty)
    }

    func testConvertAndFormat() {
        XCTAssertEqual(PriceLogic.convert(3650, from: .thb, rate: 36.5), 100, accuracy: 0.0001)
        XCTAssertEqual(PriceLogic.convert(10, from: .eur, rate: 36.5), 365, accuracy: 0.0001)
        XCTAssertEqual(PriceLogic.convert(10, from: .eur, rate: 0), 10)
        XCTAssertEqual(PriceLogic.format(1200, .thb), "1.200 ฿")
        XCTAssertEqual(PriceLogic.format(1200, .thb, comma: false), "1,200 ฿")
        XCTAssertEqual(PriceLogic.format(12.5, .eur), "12,50 €")
        XCTAssertEqual(PriceLogic.format(12, .eur), "12 €")
        XCTAssertEqual(PriceLogic.format(1234567, .thb), "1.234.567 ฿")
        XCTAssertEqual(PriceLogic.format(999.6, .thb), "1.000 ฿")
    }

    func testConversionLine() {
        let m = PriceMention(amount: 365, currency: .thb, raw: "365 baht")
        XCTAssertEqual(PriceLogic.conversionLine(m, rate: 36.5), "365 ฿ ≈ 10 €")
        XCTAssertNil(PriceLogic.conversionLine(m, rate: nil))
        XCTAssertNil(PriceLogic.conversionLine(PriceMention(amount: 5, currency: nil, raw: "5"), rate: 36))
    }

    func testCounterOffers() {
        let o = PriceLogic.counterOffers(asking: 1000)
        XCTAssertEqual(o.map(\.amount), [700, 800, 900])
        XCTAssertEqual(o.map(\.percent), [70, 80, 90])
        XCTAssertEqual(PriceLogic.counterOffers(asking: 130).map(\.amount), [90, 105, 115])
        XCTAssertTrue(PriceLogic.counterOffers(asking: 0).isEmpty)
        XCTAssertEqual(PriceLogic.counterOffers(asking: 100, percents: [0, 100, 50]).map(\.percent), [50])
    }

    func testNextBid() {
        XCTAssertEqual(PriceLogic.nextBid(mine: 500, theirs: 1000), 700)
        XCTAssertEqual(PriceLogic.nextBid(mine: 500, theirs: 1000, maxBudget: 600), 600)
        XCTAssertNil(PriceLogic.nextBid(mine: 1000, theirs: 900))
        XCTAssertNil(PriceLogic.nextBid(mine: 100, theirs: 101))
        XCTAssertNil(PriceLogic.nextBid(mine: 0, theirs: 100))
    }
}
