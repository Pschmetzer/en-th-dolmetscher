import XCTest
@testable import Dolmetscher

/// Runde 19: Entscheidungen der Audio-Sitzung (Route, Unterbrechung, Leerlauf).
final class Round19Tests: XCTestCase {
    func testOutputOnlyDeviceNeverRebuildsTheMicrophone() {
        let mic = ["BuiltInMic"]
        XCTAssertEqual(AudioSessionPolicy.routeAction(reason: .newDeviceAvailable, inputsBefore: mic, inputsAfter: mic), .ignore)
        XCTAssertEqual(AudioSessionPolicy.routeAction(reason: .oldDeviceUnavailable, inputsBefore: mic, inputsAfter: mic), .outputLost)
    }

    func testChangedInputRebuildsOrReportsLoss() {
        XCTAssertEqual(AudioSessionPolicy.routeAction(reason: .newDeviceAvailable, inputsBefore: ["BuiltInMic"], inputsAfter: ["AirPods"]), .rebuild)
        XCTAssertEqual(AudioSessionPolicy.routeAction(reason: .oldDeviceUnavailable, inputsBefore: ["AirPods"], inputsAfter: ["BuiltInMic"]), .inputLost)
    }

    func testOtherReasonsAreIgnoredAndOrderOfInputsDoesNotMatter() {
        XCTAssertEqual(AudioSessionPolicy.routeAction(reason: .other, inputsBefore: ["a"], inputsAfter: ["b"]), .ignore)
        XCTAssertEqual(AudioSessionPolicy.routeAction(reason: .newDeviceAvailable, inputsBefore: ["a", "b"], inputsAfter: ["b", "a"]), .ignore)
    }

    func testNoRebuildWhileInterrupted() {
        XCTAssertFalse(AudioSessionPolicy.mayRebuild(interrupted: true))
        XCTAssertTrue(AudioSessionPolicy.mayRebuild(interrupted: false))
    }

    func testIdleDoesNotRunDuringInterruption() {
        XCTAssertEqual(AudioSessionPolicy.effectiveIdle(900, interrupted: true), 0)
        XCTAssertEqual(AudioSessionPolicy.effectiveIdle(900, interrupted: false), 900)
        XCTAssertEqual(IdlePolicy.state(idle: AudioSessionPolicy.effectiveIdle(900, interrupted: true), limit: 300), .ok)
    }

    func testNewTextsExistInAllLanguages() {
        for key in ["interrupt_resumed", "route_output_lost"] {
            for lang in ["de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id"] {
                XCTAssertFalse((L10n.text(key, lang: lang) ?? "").isEmpty, "\(key) \(lang)")
            }
        }
    }
}
