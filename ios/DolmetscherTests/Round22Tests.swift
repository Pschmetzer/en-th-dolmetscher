import XCTest
@testable import Dolmetscher

final class Round22Tests: XCTestCase {
    func testBargainOffers() {
        let o = Bargain.offers(asking: 300)
        XCTAssertEqual(o.map(\.amount), [150, 180, 210, 240])
        XCTAssertEqual(o.first?.words, "หนึ่งร้อยห้าสิบบาท")
        // unter 100 ฿ in Fünferschritten, doppelte Beträge entfallen
        XCTAssertEqual(Bargain.offers(asking: 40).map(\.amount), [20, 25, 30])
        XCTAssertTrue(Bargain.offers(asking: 5).isEmpty)
        XCTAssertTrue(Bargain.offers(asking: .nan).isEmpty)
        XCTAssertTrue(Bargain.offers(asking: 5_000_000).isEmpty)
        for a in [20.0, 55, 99, 100, 123, 999, 12_345] {
            for off in Bargain.offers(asking: a) { XCTAssertLessThan(off.amount, Int(a), "\(a)") }
        }
    }

    func testTaxiMeter() {
        XCTAssertEqual(TaxiFare.meter(km: 0.5), 35)
        XCTAssertEqual(TaxiFare.meter(km: 1), 35)
        XCTAssertEqual(TaxiFare.meter(km: 10), 94)        // 35 + 9 × 6,5 = 93,5
        XCTAssertEqual(TaxiFare.meter(km: 25), 204)       // + 10 × 7 + 5 × 8 = 203,5
        XCTAssertEqual(TaxiFare.meter(km: 10, waitingMinutes: 10), 124)
        XCTAssertNil(TaxiFare.meter(km: 0))
        XCTAssertNil(TaxiFare.meter(km: -3))
        XCTAssertNil(TaxiFare.meter(km: .infinity))
        XCTAssertNil(TaxiFare.meter(km: 9999))
        XCTAssertNil(TaxiFare.meter(km: 5, waitingMinutes: -1))
        let r = TaxiFare.range(km: 10)
        XCTAssertEqual(r, 94...118)
        var last = 0
        for km in stride(from: 1.0, through: 120, by: 1) {   // wächst nie rückwärts
            let f = TaxiFare.meter(km: km) ?? -1
            XCTAssertGreaterThanOrEqual(f, last); last = f
        }
    }

    func testThaiDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d = cal.date(from: DateComponents(year: 2026, month: 11, day: 20))!
        XCTAssertEqual(ThaiDate.text(d, calendar: cal), "วันศุกร์ที่ 20 พฤศจิกายน พ.ศ. 2569")
        XCTAssertEqual(ThaiDate.text(d, calendar: cal, spoken: true), "วันศุกร์ที่ ยี่สิบ พฤศจิกายน พ.ศ. สองพันห้าร้อยหกสิบเก้า")
        let sun = cal.date(from: DateComponents(year: 2026, month: 11, day: 22))!
        XCTAssertTrue(ThaiDate.text(sun, calendar: cal).hasPrefix("วันอาทิตย์ที่ 22"))
    }

    func testNewTextsPresent() {
        for k in ["trv_bargain", "trv_asking", "trv_taxi", "trv_km", "trv_wait_min", "trv_taxi_note", "trv_date"] {
            XCTAssertEqual(L10n.round21[k]?.count, 10, k)
        }
    }
}
