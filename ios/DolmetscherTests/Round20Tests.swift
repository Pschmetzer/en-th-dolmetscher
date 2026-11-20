// Round20Tests.swift – echte Verhaltenstests (kein Quelltext-Regex) für Runde 20.
import XCTest
@testable import Dolmetscher

@MainActor
final class Round20Tests: XCTestCase {
    func testStaleDateIsTwentyMinutesAhead() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(LiveActivityController.staleDate(now: now).timeIntervalSince(now), 20 * 60, accuracy: 0.001)
    }

    func testBackgroundGraceEndIsIdempotent() {
        let g = BackgroundGrace(name: "test")
        g.end()
        g.end()   // darf nicht abstürzen oder doppelt beenden
    }
}
