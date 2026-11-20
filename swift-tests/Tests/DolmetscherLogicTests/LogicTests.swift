import XCTest
@testable import DolmetscherLogic

final class EnvLogicTests: XCTestCase {
    func testStampNormalizationIgnoresLineEndingsAndBlankLines() {
        XCTAssertEqual(EnvLogic.normalized(" a \r\n\r\n b\n"), "a\nb")
        XCTAssertNil(EnvLogic.normalized("  \n "))
        XCTAssertNil(EnvLogic.normalized(nil))
    }

    func testStampMatchesNeedsBothSides() {
        XCTAssertTrue(EnvLogic.stampMatches(expected: "x\ny", actual: "x\r\ny\r\n"))
        XCTAssertFalse(EnvLogic.stampMatches(expected: "x", actual: nil))
        XCTAssertFalse(EnvLogic.stampMatches(expected: nil, actual: "x"))
        XCTAssertFalse(EnvLogic.stampMatches(expected: "x", actual: "y"))
    }

    func testStepFractionPackagesInterpolates() {
        XCTAssertEqual(EnvLogic.stepFraction("packages", progress: 0), 0.15, accuracy: 1e-9)
        XCTAssertEqual(EnvLogic.stepFraction("packages", progress: 100), 0.85, accuracy: 1e-9)
        XCTAssertEqual(EnvLogic.stepFraction("packages", progress: 500), 0.85, accuracy: 1e-9)   // geklemmt
        XCTAssertEqual(EnvLogic.stepFraction("unknown"), 0)
    }

    func testSpaceCheck() {
        XCTAssertTrue(EnvLogic.enoughSpace(freeBytes: nil, requiredGB: 99))   // unbekannt blockiert nicht
        XCTAssertFalse(EnvLogic.enoughSpace(freeBytes: 1_000_000_000, requiredGB: 2))
        XCTAssertEqual(EnvLogic.requiredGB(envMissing: false, modelsGB: -3), 0)
    }

    func testDownloadFraction() {
        XCTAssertNil(EnvLogic.downloadFraction(done: 5, total: nil))
        XCTAssertNil(EnvLogic.downloadFraction(done: 5, total: 0))
        XCTAssertEqual(EnvLogic.downloadFraction(done: 50, total: 100), 0.5)
        XCTAssertEqual(EnvLogic.downloadFraction(done: 500, total: 100), 1)
    }
}

final class DiagnosticsLogicTests: XCTestCase {
    func testRedactsHomeUserAndSecrets() {
        let out = DiagnosticsLogic.redact("open /Users/alice/x sk-abcdefghijkl alice", home: "/Users/alice", user: "alice")
        XCTAssertFalse(out.contains("alice"))
        XCTAssertFalse(out.contains("sk-abcdefghijkl"))
        XCTAssertTrue(out.contains("~"))
    }

    func testRedactsLongTokens() {
        let token = String(repeating: "A", count: 45)
        XCTAssertFalse(DiagnosticsLogic.redact("key=" + token, home: "/h", user: "u").contains(token))
    }
}

final class MenuBarLogicTests: XCTestCase {
    func testSwapAndPreview() {
        let s = MenuBarLogic.swapped(mine: "en", partner: "th")
        XCTAssertEqual(s.mine, "th"); XCTAssertEqual(s.partner, "en")
        XCTAssertEqual(MenuBarLogic.preview("a\nb"), "a b")
        let long = String(repeating: "x", count: 100)
        XCTAssertEqual(MenuBarLogic.preview(long).count, 60)
        XCTAssertTrue(MenuBarLogic.preview(long).hasSuffix("…"))
    }
}

final class OnboardingLogicTests: XCTestCase {
    func testReminder() {
        let until = OnboardingLogic.remindUntil(now: 1000)
        XCTAssertGreaterThan(until, 1000)
        XCTAssertFalse(OnboardingLogic.remindDue(until: until, now: 1000))
        XCTAssertTrue(OnboardingLogic.remindDue(until: until, now: until))
    }
}

final class PartnerLogicTests: XCTestCase {
    func testSegmentsReassembleOriginalText() {
        for text in ["Das kostet 250 Baht", "ab 10:30 Uhr, 3,5 kg", "ohne Zahl", "42", ""] {
            let joined = PartnerLogic.segments(text).map(\.text).joined()
            XCTAssertEqual(joined, text)
        }
    }

    func testNumbersAreFlagged() {
        let segs = PartnerLogic.segments("Preis 250 Baht")
        XCTAssertTrue(segs.contains { $0.isNumber && $0.text.contains("250") })
    }

    func testFontSizeShrinksWithLength() {
        let short = PartnerLogic.fontSize(length: 10, width: 800, height: 600)
        let long = PartnerLogic.fontSize(length: 400, width: 800, height: 600)
        XCTAssertGreaterThan(short, long)
    }
}

final class HistoryLogicTests: XCTestCase {
    func testParseIgnoresGarbage() {
        XCTAssertTrue(HistoryLogic.parse(Data("kein json".utf8)).isEmpty)
    }
}
