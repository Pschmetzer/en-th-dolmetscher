import XCTest
@testable import DolmetscherLogic

final class UtteranceLogicTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1000)
    func key(_ uid: String?, pending: Bool = false, text: String = "", sp: String? = nil, at: Date? = nil) -> BubbleKey {
        BubbleKey(uid: uid, pending: pending, speaker: sp, text: text, out: "", date: at ?? t0)
    }

    func testPendingPlaceholderReplaced() {
        let items = [key("u1", pending: true)]
        XCTAssertEqual(UtteranceLogic.place(in: items, uid: "u1", replaces: nil, text: "hi there", out: "", speaker: nil, now: t0), .replace(0))
    }
    func testSameUidIsIdempotent() {
        let items = [key("u1", text: "hello world")]
        XCTAssertEqual(UtteranceLogic.place(in: items, uid: "u1", replaces: nil, text: "hello world!", out: "", speaker: nil, now: t0.addingTimeInterval(30)), .replace(0))
    }
    func testReplacesWins() {
        let items = [key("u1", text: "a b c"), key("u2", text: "x y z")]
        XCTAssertEqual(UtteranceLogic.place(in: items, uid: "u3", replaces: "u1", text: "new", out: "", speaker: nil, now: t0), .replace(0))
    }
    func testContentDedupWithinWindow() {
        let items = [key("u1", text: "Where is the station?", sp: "me")]
        XCTAssertEqual(UtteranceLogic.place(in: items, uid: nil, replaces: nil, text: "where is the station", out: "", speaker: "me", now: t0.addingTimeInterval(3)), .replace(0))
    }
    func testNoDedupAfterWindowOrOtherSpeaker() {
        let items = [key("u1", text: "Where is the station?", sp: "me")]
        XCTAssertEqual(UtteranceLogic.place(in: items, uid: "u2", replaces: nil, text: "Where is the station?", out: "", speaker: "me", now: t0.addingTimeInterval(5)), .append)
        XCTAssertEqual(UtteranceLogic.place(in: items, uid: nil, replaces: nil, text: "Where is the station?", out: "", speaker: "other", now: t0.addingTimeInterval(1)), .append)
    }
    func testShortTextNotDeduped() {
        let items = [key("u1", text: "ok")]
        XCTAssertEqual(UtteranceLogic.place(in: items, uid: nil, replaces: nil, text: "ok", out: "", speaker: nil, now: t0), .append)
    }
    func testLatePlaceholderlessAppends() {
        XCTAssertEqual(UtteranceLogic.place(in: [], uid: "u9", replaces: nil, text: "hello there", out: "", speaker: nil, now: t0), .append)
    }
    func testPlaceholderExpiry() {
        XCTAssertFalse(UtteranceLogic.shouldExpirePlaceholder(heard: true, inRecognition: false, secondsSinceVoice: 5))
        XCTAssertFalse(UtteranceLogic.shouldExpirePlaceholder(heard: false, inRecognition: true, secondsSinceVoice: 5))
        XCTAssertFalse(UtteranceLogic.shouldExpirePlaceholder(heard: false, inRecognition: false, secondsSinceVoice: 0.2))
        XCTAssertTrue(UtteranceLogic.shouldExpirePlaceholder(heard: false, inRecognition: false, secondsSinceVoice: 2))
    }
    func testJumpCounter() {
        var c = JumpCounter()
        c.newItem(atBottom: false); c.newItem(atBottom: false)
        XCTAssertEqual(c.unseen, 2)
        c.reachedBottom(); XCTAssertEqual(c.unseen, 0)
        for _ in 0..<150 { c.newItem(atBottom: false) }
        XCTAssertEqual(c.label, "99+")
    }
    func testStatusLine() {
        XCTAssertEqual(StatusLine.compose(error: "⚠️ x", errorAge: 5, base: "Bereit", latency: 1.2), "⚠️ x")
        XCTAssertEqual(StatusLine.compose(error: "⚠️ x", errorAge: 60, base: "Bereit", latency: 1.2), "Bereit · 1.2 s")
        XCTAssertEqual(StatusLine.compose(error: nil, errorAge: 0, base: "Bereit", latency: nil), "Bereit")
    }
}

final class StatusLineTests: XCTestCase {
    func testErrorWinsWhileFresh() {
        XCTAssertEqual(StatusLine.compose(error: "boom", errorAge: 5, base: "ok", latency: 1), "boom")
    }
    func testErrorExpires() {
        XCTAssertEqual(StatusLine.compose(error: "boom", errorAge: 31, base: "ok", latency: nil), "ok")
    }
    func testLatencyAppended() {
        XCTAssertEqual(StatusLine.compose(error: nil, errorAge: 0, base: "ok", latency: 1.25), "ok · 1.2 s".replacingOccurrences(of: "1.2", with: String(format: "%.1f", 1.25)))
        XCTAssertEqual(StatusLine.compose(error: nil, errorAge: 0, base: "", latency: 1), "")
    }
    func testJumpCounter() {
        var j = JumpCounter(); j.newItem(atBottom: false); j.newItem(atBottom: false)
        XCTAssertEqual(j.label, "2"); j.reachedBottom(); XCTAssertEqual(j.unseen, 0)
        for _ in 0..<120 { j.newItem(atBottom: false) }
        XCTAssertEqual(j.label, "99+"); j.newItem(atBottom: true); XCTAssertEqual(j.unseen, 0)
    }
}
