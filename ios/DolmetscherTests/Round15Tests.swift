import XCTest
@testable import Dolmetscher

/// Runde 15: Gesprächsmodus – Schriftgröße, Zustand, Echo, Stille, Zahlen, Layout.
final class Round15Tests: XCTestCase {
    func testFontStepIsClamped() {
        XCTAssertEqual(ConversationLogic.stepped(0, by: -1), 0)
        XCTAssertEqual(ConversationLogic.stepped(4, by: 1), 4)
        XCTAssertEqual(ConversationLogic.clampStep(99), ConversationLogic.fontScales.count - 1)
        XCTAssertEqual(ConversationLogic.scale(step: 1), 1.0)
    }

    func testStatePriority() {
        typealias C = ConversationLogic
        XCTAssertEqual(C.state(expecting: true, listening: true, hearing: true, translating: false, speaking: false), .listening)
        XCTAssertEqual(C.state(expecting: true, listening: true, hearing: false, translating: false, speaking: false), .idle)
        XCTAssertEqual(C.state(expecting: true, listening: true, hearing: true, translating: true, speaking: false), .translating)
        XCTAssertEqual(C.state(expecting: false, listening: true, hearing: true, translating: true, speaking: true), .speaking)
        XCTAssertEqual(C.state(expecting: false, listening: true, hearing: true, translating: false, speaking: false), .idle)
    }

    func testEveryStateHasTextAndIcon() {
        for s in [ConversationLogic.SideState.idle, .listening, .translating, .speaking] {
            XCTAssertFalse(ConversationLogic.icon(s).isEmpty)
            XCTAssertNotNil(L10n.text(ConversationLogic.textKey(s), lang: "de"))
        }
    }

    func testEchoDetection() {
        XCTAssertTrue(ConversationLogic.isEcho("Where is the station?", spoken: ["where is the station"]))
        XCTAssertFalse(ConversationLogic.isEcho("How much is it", spoken: ["Where is the station"]))
        XCTAssertFalse(ConversationLogic.isEcho("ok", spoken: ["ok"]))   // zu kurz
        XCTAssertFalse(ConversationLogic.isEcho("hello there", spoken: []))
    }

    func testEchoWindowAndSilence() {
        let now = Date()
        let r = ConversationLogic.recent([("old", now.addingTimeInterval(-60)), ("new", now.addingTimeInterval(-2))], now: now)
        XCTAssertEqual(r, ["new"])
        XCTAssertTrue(ConversationLogic.isSilent(lastSpeech: now.addingTimeInterval(-5), now: now))
        XCTAssertFalse(ConversationLogic.isSilent(lastSpeech: now.addingTimeInterval(-1), now: now))
        XCTAssertTrue(ConversationLogic.turnLocked(speaking: true))
        XCTAssertFalse(ConversationLogic.turnLocked(speaking: false))
    }

    func testNumberRanges() {
        let t = "Room 12 costs 1,500.50 baht at 14:30"
        let found = ConversationLogic.numberRanges(in: t).map { String(t[$0]) }
        XCTAssertEqual(found, ["12", "1,500.50", "14:30"])
        XCTAssertTrue(ConversationLogic.numberRanges(in: "no digits.").isEmpty)
        XCTAssertEqual(ConversationLogic.numberRanges(in: "ห้อง ๓๐๐").count, 1)
        XCTAssertEqual(ConversationLogic.numberRanges(in: "a 5, b").map { "a 5, b"[$0] }, ["5"])
    }

    func testSideBySideOnlyWhenWideLandscape() {
        XCTAssertTrue(ConversationLogic.sideBySide(width: 1000, height: 700))
        XCTAssertFalse(ConversationLogic.sideBySide(width: 400, height: 800))
        XCTAssertFalse(ConversationLogic.sideBySide(width: 500, height: 390))   // schmales Querformat
    }

    func testLastSpeakableUsesTargetLanguage() {
        let a = Entry(src: .en, dst: .th, text: "hi", translation: "สวัสดี")
        let b = Entry(src: .th, dst: .en, text: "ok", translation: "okay")
        XCTAssertEqual(ConversationLogic.lastSpeakable([a, b], lang: .th)?.id, a.id)
        XCTAssertNil(ConversationLogic.lastSpeakable([Entry(src: .en, dst: .th, text: "x")], lang: .th))
    }
}
