import XCTest
@testable import DolmetscherLogic

final class ConversationUILogicTests: XCTestCase {
    func testHitNavigatorMapsHitToBubble() {
        let c = HitNavigator.counts(query: "a", texts: [("a b", "x"), ("none", "zzz"), ("aa", "a")])
        XCTAssertEqual(c, [1, 0, 3])
        XCTAssertEqual(HitNavigator.bubbleIndex(forHit: 0, counts: c), 0)
        XCTAssertEqual(HitNavigator.bubbleIndex(forHit: 1, counts: c), 2)
        XCTAssertEqual(HitNavigator.bubbleIndex(forHit: 3, counts: c), 2)
        XCTAssertNil(HitNavigator.bubbleIndex(forHit: 4, counts: c))
        XCTAssertNil(HitNavigator.bubbleIndex(forHit: -1, counts: c))
        XCTAssertNil(HitNavigator.clamp(5, count: 3))
        XCTAssertEqual(HitNavigator.clamp(2, count: 3), 2)
    }

    func testSelectionToggleExtendPrune() {
        var s = BubbleSelection()
        let order = ["a", "b", "c", "d", "e"]
        s.toggle("b"); s.extend(to: "d", in: order)
        XCTAssertEqual(s.ordered(order), ["b", "c", "d"])
        s.toggle("c")
        XCTAssertFalse(s.contains("c"))
        s.prune(keeping: ["a", "b"])
        XCTAssertEqual(s.count, 1)
        s.selectAll(order); XCTAssertEqual(s.count, 5)
        s.clear(); XCTAssertTrue(s.isEmpty)
        s.extend(to: "a", in: order)   // ohne Anker = toggle
        XCTAssertEqual(s.count, 1)
    }

    func testNumberDiff() {
        XCTAssertEqual(NumberWarning.numbers(in: "Room 12, 3.5 hours at 14:30."), ["12", "3.5", "14:30"])
        XCTAssertEqual(NumberWarning.numbers(in: "ราคา ๑๒๐ บาท"), ["120"])
        let d = NumberWarning.diff(original: "I need 12 rooms for 3 nights", translation: "ฉันต้องการ 12 ห้อง 4 คืน")
        XCTAssertEqual(d.missing, ["3"]); XCTAssertEqual(d.extra, ["4"])
        XCTAssertTrue(NumberWarning.diff(original: "5 and 5", translation: "5 และ ๕").isEmpty)
        XCTAssertEqual(NumberWarning.diff(original: "5 and 5", translation: "5").missing, ["5"])
        XCTAssertEqual(NumberWarning.listed(["1", "2", "3", "4", "5"]), "1, 2, 3, 4 …")
    }

    func testAltCycleWraps() {
        XCTAssertEqual(AltCycle.next(0, count: 2), 1)
        XCTAssertEqual(AltCycle.next(2, count: 2), 0)
        XCTAssertEqual(AltCycle.next(0, count: 0), 0)
        XCTAssertEqual(AltCycle.label(index: 1, count: 2), "2 / 3")
    }

    func testSparklineAndTrend() {
        XCTAssertEqual(LatencySpark.line([]), "")
        XCTAssertEqual(LatencySpark.line([0, 4]), "▁█")
        XCTAssertEqual(LatencySpark.line([1, 1, 1, 1, 1], limit: 3).count, 3)
        XCTAssertEqual(LatencySpark.trend([1, 1, 3, 3]), .up)
        XCTAssertEqual(LatencySpark.trend([3, 3, 1, 1]), .down)
        XCTAssertEqual(LatencySpark.trend([2, 2]), .flat)
    }

    func testClippingNeedsSustainedAndHysteresis() {
        var c = ClippingDetector()
        for _ in 0..<5 { XCTAssertFalse(c.feed(0.99)) }
        XCTAssertTrue(c.feed(0.99))
        XCTAssertTrue(c.feed(0.9))      // Hysterese
        XCTAssertFalse(c.feed(0.5))
        c.feed(0.99); XCTAssertFalse(c.feed(0.4))   // Reihe unterbrochen
    }

    func testScriptMismatch() {
        XCTAssertEqual(ScriptMismatch.dominant("สวัสดีครับ"), .thai)
        XCTAssertEqual(ScriptMismatch.dominant("Hello"), .latin)
        XCTAssertNil(ScriptMismatch.dominant("ok"))
        XCTAssertTrue(ScriptMismatch.shouldHint(forced: "en", recent: ["สวัสดีครับ", "hello there", "ขอบคุณมากครับ"]))
        XCTAssertFalse(ScriptMismatch.shouldHint(forced: "en", recent: ["hello there", "good morning"]))
        XCTAssertFalse(ScriptMismatch.shouldHint(forced: "auto", recent: ["สวัสดีครับ", "ขอบคุณมากครับ"]))
        XCTAssertFalse(ScriptMismatch.shouldHint(forced: "ja", recent: ["สวัสดีครับ", "ขอบคุณมากครับ"]))
        XCTAssertTrue(ScriptMismatch.shouldHint(forced: "th", recent: ["where is it", "thank you"]))
    }

    func testEmptyTipStableAndInRange() {
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(EmptyTips.key(on: d), EmptyTips.key(on: d))
        XCTAssertTrue(EmptyTips.keys.contains(EmptyTips.key(on: d.addingTimeInterval(86400 * 3))))
        XCTAssertNotEqual(EmptyTips.key(on: d), EmptyTips.key(on: d.addingTimeInterval(86400)))
    }

    func testPartialThrottle() {
        var t = PartialThrottle()
        XCTAssertEqual(t.decide(id: "u1", text: "a", now: 10), .apply)
        XCTAssertEqual(t.decide(id: "u1", text: "a", now: 10.5), .skip)
        if case .deferFor(let d) = t.decide(id: "u1", text: "ab", now: 10.05) { XCTAssertEqual(d, 0.07, accuracy: 0.001) }
        else { XCTFail("expected deferral") }
        XCTAssertEqual(t.decide(id: "u1", text: "ab", now: 10.2), .apply)
        XCTAssertEqual(t.decide(id: "u2", text: "x", now: 10.2), .apply)   // je id
        t.forget("u1")
        XCTAssertEqual(t.decide(id: "u1", text: "ab", now: 10.21), .apply)
    }

    func testWatchdogVerdicts() {
        var s = WatchdogLogic.State(lastAlive: 100, lastTick: 100)
        func tick(_ now: Double, hung: Bool = false, idle: Bool = true, restarts: Int = 0, pong: Bool = true) -> WatchdogLogic.Verdict {
            WatchdogLogic.tick(&s, now: now, pongSeen: pong, alreadyHung: hung, idle: idle, restartsSoFar: restarts,
                               pingEvery: 15, hungAfter: 45, hungRestartAfter: 90)
        }
        XCTAssertEqual(tick(115), .ok)
        s.lastAlive = 115
        XCTAssertEqual(tick(130), .ok)
        XCTAssertEqual(tick(161), .hung)                    // > 45 s ohne Lebenszeichen
        XCTAssertEqual(tick(176, hung: true), .hung)
        XCTAssertEqual(tick(206, hung: true), .restart)     // > 90 s, ruhig
        XCTAssertEqual(tick(222, hung: true, restarts: 3), .hung)
        XCTAssertEqual(tick(238, hung: true, idle: false), .hung)   // beschäftigt: kein Neustart vor 3 × 90 s
    }

    func testWatchdogSleepGapResets() {
        var s = WatchdogLogic.State(lastAlive: 100, lastTick: 100)
        let v = WatchdogLogic.tick(&s, now: 4000, pongSeen: true, alreadyHung: false, idle: true, restartsSoFar: 0,
                                   pingEvery: 15, hungAfter: 45, hungRestartAfter: 90)
        XCTAssertEqual(v, .ok); XCTAssertEqual(s.lastAlive, 4000)
        let back = WatchdogLogic.tick(&s, now: 3000, pongSeen: true, alreadyHung: false, idle: true, restartsSoFar: 0,
                                      pingEvery: 15, hungAfter: 45, hungRestartAfter: 90)
        XCTAssertEqual(back, .ok)
    }

    func testMonotonicClockAdvances() {
        let a = MonotonicClock.now(); let b = MonotonicClock.now()
        XCTAssertGreaterThanOrEqual(b, a)
    }

    func testInterruptedAndExportSelection() {
        XCTAssertNil(InterruptedMark.keepText(partial: "  "))
        XCTAssertNil(InterruptedMark.keepText(partial: nil))
        XCTAssertEqual(InterruptedMark.keepText(partial: " hi "), "hi")
        var o = ExportOptions(); o.onlyLang = "th"; o.includeTimes = false
        XCTAssertEqual(ExportSelection.filter(["en", "th", "th"], options: o, lang: { $0 }), ["th", "th"])
        XCTAssertEqual(ExportSelection.stamp(Date(), options: o), "")
        o.includeTimes = true
        XCTAssertTrue(ExportSelection.stamp(Date(), options: o).hasPrefix("["))
        XCTAssertEqual(PartnerScript.boost(lang: "th"), 1.18)
        XCTAssertEqual(PartnerScript.boost(lang: "en"), 1.0)
    }
}
