import XCTest
@testable import DolmetscherLogic

final class R24ExtraTests: XCTestCase {
    func testCanonicalThousands() {
        XCTAssertEqual(NumberWarning.canonical("1,200"), "1200")
        XCTAssertEqual(NumberWarning.canonical("1,200,000"), "1200000")
        XCTAssertEqual(NumberWarning.canonical("3,5"), "3,5")
        XCTAssertEqual(NumberWarning.canonical("1,2000"), "1,2000")
        XCTAssertEqual(NumberWarning.canonical("14:30"), "14:30")
        XCTAssertEqual(NumberWarning.canonical("1,200.5"), "1,200.5")
        XCTAssertEqual(NumberWarning.canonical("12"), "12")
    }

    func testDiffIgnoresThousandsFormat() {
        XCTAssertTrue(NumberWarning.diff(original: "It costs 1,200 baht", translation: "ราคา 1200 บาท").isEmpty)
        XCTAssertTrue(NumberWarning.diff(original: "It costs 1200 baht", translation: "ราคา 1,200 บาท").isEmpty)
        XCTAssertEqual(NumberWarning.diff(original: "1,200 baht", translation: "1,300 บาท").missing, ["1,200"])
    }

    func testDeriveCandidates() {
        let packs: [(id: String, phrases: [String])] = [
            (id: "taxi", phrases: ["Please use the meter", "Take me to the airport", "Where is the toilet please"]),
            (id: "doctor", phrases: ["I have a fever", "Where is the pharmacy", "Where is the toilet please"]),
            (id: "bank", phrases: ["Where is the toilet please", "Where is the exchange"]),
            (id: "hotel", phrases: ["Where is the toilet please"]),
            (id: "shop", phrases: ["Where is the toilet please"]),
        ]
        let c = ScenarioDetect.deriveCandidates(packs: packs, maxPacks: 3)
        let taxi = c.first { $0.id == "taxi" }!
        XCTAssertTrue(taxi.keywords.contains("airport"))
        XCTAssertTrue(taxi.keywords.contains("meter"))
        XCTAssertFalse(taxi.keywords.contains("toilet"))   // kommt in 5 Paketen vor
        XCTAssertFalse(taxi.keywords.contains("where"))
        XCTAssertTrue(c.first { $0.id == "doctor" }!.keywords.contains("pharmacy"))
        XCTAssertEqual(ScenarioDetect.deriveCandidates(packs: [], maxPacks: 3), [])
    }

    func testDerivedKeywordsDriveSuggestion() {
        let packs: [(id: String, phrases: [String])] = [
            (id: "taxi", phrases: ["Please use the meter", "Take me to the airport"]),
            (id: "doctor", phrases: ["I have a fever", "Where is the pharmacy"]),
        ]
        let c = ScenarioDetect.deriveCandidates(packs: packs)
        XCTAssertEqual(ScenarioDetect.suggest(recent: ["is the meter on", "to the airport please"], candidates: c)?.id, "taxi")
    }
}
