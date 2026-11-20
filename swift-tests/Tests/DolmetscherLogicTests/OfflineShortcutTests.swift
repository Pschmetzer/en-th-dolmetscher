import XCTest
@testable import DolmetscherLogic

final class OfflineFallbackTests: XCTestCase {
    let book = [
        BookPhrase(en: "Where is the toilet?", th: "ห้องน้ำอยู่ที่ไหน"),
        BookPhrase(en: "How much is this?", th: "อันนี้ราคาเท่าไร"),
        BookPhrase(en: "I am allergic to peanuts", th: "ฉันแพ้ถั่วลิสง", critical: true),
    ]

    func testDiceBasics() {
        XCTAssertEqual(OfflineFallback.dice("hello", "Hello!"), 1, accuracy: 0.0001)
        XCTAssertEqual(OfflineFallback.dice("", "x"), 0)
        XCTAssertLessThan(OfflineFallback.dice("abcd", "wxyz"), 0.1)
    }

    func testIsThai() {
        XCTAssertTrue(OfflineFallback.isThai("ห้องน้ำ"))
        XCTAssertFalse(OfflineFallback.isThai("toilet"))
        XCTAssertFalse(OfflineFallback.isThai("123"))
    }

    func testEnglishInputGivesThai() {
        let m = OfflineFallback.match("where is the toilet", in: book)
        XCTAssertEqual(m?.answer, "ห้องน้ำอยู่ที่ไหน")
        XCTAssertFalse(m!.inputIsThai)
    }

    func testThaiInputGivesEnglish() {
        let m = OfflineFallback.match("อันนี้ราคาเท่าไหร่", in: book)
        XCTAssertEqual(m?.answer, "How much is this?")
    }

    func testBelowThresholdIsNil() {
        XCTAssertNil(OfflineFallback.match("the weather is nice today", in: book))
        XCTAssertNil(OfflineFallback.match("x", in: book))
        XCTAssertNil(OfflineFallback.match("anything", in: []))
    }

    func testSuggestionsSortedAndLimited() {
        let s = OfflineFallback.suggestions("where is toilet", in: book, limit: 2, threshold: 0.2)
        XCTAssertEqual(s.first?.phrase.en, "Where is the toilet?")
        XCTAssertLessThanOrEqual(s.count, 2)
        XCTAssertTrue(OfflineFallback.suggestions("zz", in: book).isEmpty)
    }

    func testCriticalWinsTie() {
        let b = [BookPhrase(en: "help me now", th: "ก"), BookPhrase(en: "help me now", th: "ข", critical: true)]
        XCTAssertEqual(OfflineFallback.match("help me now", in: b)?.phrase.th, "ข")
    }
}

final class ShortcutCatalogTests: XCTestCase {
    func testNoDuplicateKeys() {
        XCTAssertEqual(ShortcutCatalog.duplicates(ShortcutCatalog.all), [])
        XCTAssertEqual(ShortcutCatalog.duplicates([.init(keys: "⌘A", labelKey: "a", group: "view"), .init(keys: "⌘A", labelKey: "b", group: "view")]), ["⌘A"])
    }

    func testFilter() {
        let labels = ["pause": "Pause", "find": "Find in conversation"]
        let all = [ShortcutEntry(keys: "⌘P", labelKey: "pause", group: "conversation"), ShortcutEntry(keys: "⌘F", labelKey: "find", group: "view")]
        XCTAssertEqual(ShortcutCatalog.filter(all, query: "", label: { labels[$0] ?? $0 }).count, 2)
        XCTAssertEqual(ShortcutCatalog.filter(all, query: "find", label: { labels[$0] ?? $0 }).map(\.keys), ["⌘F"])
        XCTAssertEqual(ShortcutCatalog.filter(all, query: "⌘p", label: { labels[$0] ?? $0 }).map(\.keys), ["⌘P"])
    }

    func testGroupedOrderAndEmptyDropped() {
        let g = ShortcutCatalog.grouped(ShortcutCatalog.all)
        XCTAssertEqual(g.map(\.group), ["conversation", "view", "window"])
    }

    func testNoticeActions() {
        XCTAssertEqual(NoticeLogic.actions(for: .engineStopped).map(\.id), ["restart"])
        XCTAssertEqual(NoticeLogic.actions(for: .summaryReady).map(\.id), ["copy-summary", "open-summary"])
        XCTAssertEqual(NoticeLogic.actions(for: .scenarioSuggested("taxi")).count, 2)
    }

    func testNoticeThrottle() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(NoticeLogic.shouldDeliver(appActive: true, lastDelivered: nil, now: now))
        XCTAssertTrue(NoticeLogic.shouldDeliver(appActive: false, lastDelivered: nil, now: now))
        XCTAssertFalse(NoticeLogic.shouldDeliver(appActive: false, lastDelivered: now.addingTimeInterval(-10), now: now))
        XCTAssertTrue(NoticeLogic.shouldDeliver(appActive: false, lastDelivered: now.addingTimeInterval(-400), now: now))
    }

    func testHandoffRoundTrip() {
        let p = HandoffPayload(lastText: "hi", lastOut: "สวัสดี", from: "en", to: "th")
        XCTAssertEqual(HandoffPayload.parse(p.userInfo), p)
        XCTAssertNil(HandoffPayload.parse(["from": "EN", "to": "th"]))
        XCTAssertNil(HandoffPayload.parse(["from": "en"]))
        XCTAssertNil(HandoffPayload.parse(nil))
        XCTAssertEqual(HandoffPayload.parse(["from": "en", "to": "th", "text": String(repeating: "a", count: 5000)])?.lastText.count, 1000)
    }

    func testSayURL() {
        let u = HandoffPayload.sayURL(text: "Wo ist das Klo?", lang: "de")
        XCTAssertEqual(u?.scheme, "dolmetscher")
        XCTAssertEqual(u?.host, "say")
        let items = URLComponents(url: u!, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first(where: { $0.name == "text" })?.value, "Wo ist das Klo?")
        XCTAssertEqual(items?.first(where: { $0.name == "lang" })?.value, "de")
        XCTAssertNil(HandoffPayload.sayURL(text: "  ", lang: nil))
        XCTAssertNil(HandoffPayload.sayURL(text: String(repeating: "x", count: 1001), lang: nil))
        XCTAssertNil(URLComponents(url: HandoffPayload.sayURL(text: "a", lang: "DE!")!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "lang" })
    }
}
