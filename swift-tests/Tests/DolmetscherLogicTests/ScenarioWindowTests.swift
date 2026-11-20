import XCTest
import CoreGraphics
@testable import DolmetscherLogic

final class ScenarioDetectTests: XCTestCase {
    let cands = [
        ScenarioCandidate(id: "taxi", keywords: ["taxi", "meter", "airport", "driver", "ตรงไป"]),
        ScenarioCandidate(id: "doctor", keywords: ["pain", "fever", "pharmacy", "doctor"]),
    ]

    func testKeywordBoundaries() {
        XCTAssertTrue(ScenarioDetect.contains("take a taxi now", keyword: "taxi"))
        XCTAssertTrue(ScenarioDetect.contains("two taxis", keyword: "taxi"))
        XCTAssertFalse(ScenarioDetect.contains("taxidermy", keyword: "taxi"))
        XCTAssertFalse(ScenarioDetect.contains("it", keyword: "it"))      // zu kurz
        XCTAssertTrue(ScenarioDetect.contains("เลี้ยวซ้ายแล้วตรงไปเลย", keyword: "ตรงไป"))
    }

    func testSuggestNeedsTwoDistinct() {
        XCTAssertNil(ScenarioDetect.suggest(recent: ["taxi taxi taxi"], candidates: cands))
        let s = ScenarioDetect.suggest(recent: ["Is there a taxi?", "Please use the meter"], candidates: cands)
        XCTAssertEqual(s?.id, "taxi")
        XCTAssertEqual(s?.matched, ["meter", "taxi"])
    }

    func testExcludeAndWindow() {
        let r = ["taxi to the airport"]
        XCTAssertEqual(ScenarioDetect.suggest(recent: r, candidates: cands)?.id, "taxi")
        XCTAssertNil(ScenarioDetect.suggest(recent: r, candidates: cands, exclude: ["taxi"]))
        let old = ["taxi to the airport"] + Array(repeating: "nothing", count: ScenarioDetect.window)
        XCTAssertNil(ScenarioDetect.suggest(recent: old, candidates: cands))
    }

    func testTieBreakAndStable() {
        let c = [ScenarioCandidate(id: "b", keywords: ["alpha", "beta"]), ScenarioCandidate(id: "a", keywords: ["alpha", "beta"])]
        let s = ScenarioDetect.suggest(recent: ["alpha beta"], candidates: c)
        XCTAssertEqual(s?.id, "a")
        XCTAssertNil(ScenarioDetect.stable(previous: nil, current: s))
        XCTAssertEqual(ScenarioDetect.stable(previous: "a", current: s)?.id, "a")
        XCTAssertNil(ScenarioDetect.stable(previous: "b", current: s))
    }
}

final class WindowLogicTests: XCTestCase {
    let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let ext = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    func testCodec() {
        let f = WindowFrame(x: 10, y: 20, w: 300, h: 200)
        XCTAssertEqual(WindowRestore.decode(WindowRestore.encode(f)), f)
        XCTAssertNil(WindowRestore.decode("nonsense"))
        XCTAssertNil(WindowRestore.decode("{\"x\":1}"))
    }

    func testFitKeepsVisibleFrame() {
        let f = WindowFrame(x: 100, y: 100, w: 500, h: 400)
        XCTAssertEqual(WindowRestore.fit(f, screens: [main]), f)
    }

    func testFitMovesOffscreenWindow() {
        // Zweiter Bildschirm abgesteckt: Fenster lag bei x = 2000
        let r = WindowRestore.fit(WindowFrame(x: 2000, y: 100, w: 500, h: 400), screens: [main])!
        XCTAssertTrue(main.contains(r.rect))
    }

    func testFitShrinksAndPicksBestScreen() {
        let r = WindowRestore.fit(WindowFrame(x: 1400, y: 0, w: 5000, h: 5000), screens: [main, ext])!
        XCTAssertLessThanOrEqual(r.w, 1920)
        XCTAssertTrue(main.union(ext).contains(r.rect))
        let small = WindowRestore.fit(WindowFrame(x: 0, y: 0, w: 10, h: 10), screens: [main])!
        XCTAssertEqual(small.w, WindowRestore.minSize.width)
        XCTAssertNil(WindowRestore.fit(WindowFrame(x: 0, y: 0, w: 300, h: 300), screens: []))
    }

    func testStyleClampAndAnchorCycle() {
        var s = CaptionStyle(); s.fontSize = 500; s.opacity = 0
        let c = s.clamped()
        XCTAssertEqual(c.fontSize, 80); XCTAssertEqual(c.opacity, 0.3)
        XCTAssertEqual(CaptionOverlay.next(.bottom), .top)
        XCTAssertEqual(CaptionOverlay.next(.top), .free)
        XCTAssertEqual(CaptionOverlay.next(.free), .bottom)
    }

    func testOverlayFrame() {
        let bottom = CaptionOverlay.frame(anchor: .bottom, screen: main, fontSize: 28, lines: 1, current: nil)
        let top = CaptionOverlay.frame(anchor: .top, screen: main, fontSize: 28, lines: 1, current: nil)
        XCTAssertLessThan(bottom.minY, top.minY)
        XCTAssertEqual(bottom.width, 1008, accuracy: 0.01)
        let cur = CGRect(x: 5, y: 5, width: 50, height: 50)
        XCTAssertEqual(CaptionOverlay.frame(anchor: .free, screen: main, fontSize: 28, lines: 1, current: cur), cur)
        let tall = CaptionOverlay.frame(anchor: .bottom, screen: main, fontSize: 28, lines: 99, current: nil)
        XCTAssertEqual(tall.height, 28 * 1.5 * 4 + 36, accuracy: 0.01)
    }
}
