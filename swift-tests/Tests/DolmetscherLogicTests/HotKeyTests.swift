import XCTest
@testable import DolmetscherLogic

final class HotKeyTests: XCTestCase {
    func testDefaultsAreUniqueAndKnown() {
        let r = HotKeyLogic.resolve([:])
        XCTAssertEqual(r.count, HotKeyLogic.actions.count)
        XCTAssertEqual(Set(r.values).count, r.count)
        XCTAssertEqual(r[1], "D"); XCTAssertEqual(r[3], "T")
    }

    func testStoredChoiceIsUsed() {
        let r = HotKeyLogic.resolve(["1": "k"])
        XCTAssertEqual(r[1], "K")
    }

    func testDuplicateAndInvalidFallBack() {
        // 2 will dasselbe wie 1 -> fällt auf den eigenen Standard zurück; "9" und "ÄÖ" sind ungültig
        let r = HotKeyLogic.resolve(["1": "M", "2": "M", "4": "9", "5": "ÄÖ"])
        XCTAssertEqual(r[1], "M"); XCTAssertEqual(r[2], "P"); XCTAssertEqual(r[4], "S"); XCTAssertEqual(r[5], "R")
        XCTAssertEqual(Set(r.values).count, r.count)
    }

    func testDefaultTakenByOtherGetsFreeLetter() {
        // Aktion 1 nimmt "P" (Standard von 2): 2 muss ausweichen, bleibt aber eindeutig
        let r = HotKeyLogic.resolve(["1": "P"])
        XCTAssertEqual(r[1], "P")
        XCTAssertNotEqual(r[2], "P")
        XCTAssertEqual(Set(r.values).count, r.count)
    }

    func testAssignRejectsConflicts() {
        let cur = HotKeyLogic.resolve([:])
        XCTAssertNil(HotKeyLogic.assigned("P", to: 1, current: cur))      // gehört Aktion 2
        XCTAssertNil(HotKeyLogic.assigned("1", to: 1, current: cur))      // kein Buchstabe
        XCTAssertNil(HotKeyLogic.assigned("A", to: 99, current: cur))     // unbekannte Aktion
        XCTAssertEqual(HotKeyLogic.assigned("a", to: 1, current: cur)?[1], "A")
        XCTAssertEqual(HotKeyLogic.assigned("D", to: 1, current: cur)?[1], "D")   // eigener Buchstabe bleibt erlaubt
    }

    func testKeyCodesAndDisplay() {
        XCTAssertEqual(HotKeyLogic.keyCode("d"), 2)
        XCTAssertEqual(HotKeyLogic.keyCode("P"), 35)
        XCTAssertNil(HotKeyLogic.keyCode("1"))
        XCTAssertEqual(HotKeyLogic.display("c"), "⌃⌥C")
        XCTAssertEqual(Set(HotKeyLogic.keyCodes.values).count, HotKeyLogic.keyCodes.count)
    }

    func testSerializationRoundTrip() {
        let r = HotKeyLogic.resolve(["1": "K"])
        XCTAssertEqual(HotKeyLogic.resolve(HotKeyLogic.serialized(r)), r)
    }
}
