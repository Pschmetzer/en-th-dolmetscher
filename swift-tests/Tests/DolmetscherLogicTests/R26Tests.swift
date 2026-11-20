import XCTest
@testable import DolmetscherLogic

final class R26Tests: XCTestCase {
    // MARK: Gruppenmodus
    func testGroupNumberOnlyWithoutProfile() {
        XCTAssertEqual(GroupSpeakerLogic.groupNumber(speaker: "Sprecher 3", group: 3), 3)
        XCTAssertEqual(GroupSpeakerLogic.groupNumber(speaker: nil, group: 2), 2)
        XCTAssertEqual(GroupSpeakerLogic.groupNumber(speaker: "", group: 2), 2)
        XCTAssertNil(GroupSpeakerLogic.groupNumber(speaker: "Anna", group: 2))     // Profil gewinnt
        XCTAssertNil(GroupSpeakerLogic.groupNumber(speaker: "Sprecher 3", group: 2)) // fremder Name
        XCTAssertNil(GroupSpeakerLogic.groupNumber(speaker: nil, group: 0))
        XCTAssertNil(GroupSpeakerLogic.groupNumber(speaker: nil, group: nil))
    }

    func testColorIndexCyclesAndIsStable() {
        XCTAssertEqual(GroupSpeakerLogic.colorIndex(1), 0)
        XCTAssertEqual(GroupSpeakerLogic.colorIndex(8), 7)
        XCTAssertEqual(GroupSpeakerLogic.colorIndex(9), 0)
        XCTAssertEqual(GroupSpeakerLogic.colorIndex(0), 0)
        XCTAssertEqual(GroupSpeakerLogic.colorIndex(-5), 0)
    }

    func testSanitizeRename() {
        XCTAssertEqual(GroupSpeakerLogic.sanitize("  Anna \n Lopez "), "Anna Lopez")
        XCTAssertNil(GroupSpeakerLogic.sanitize("  \n\t "))
        XCTAssertEqual(GroupSpeakerLogic.sanitize(String(repeating: "x", count: 80))?.count, 24)
        XCTAssertEqual(GroupSpeakerLogic.sanitize("สมชาย"), "สมชาย")
    }

    func testDisplayNamePriority() {
        let r = [2: "Chef"]
        XCTAssertEqual(GroupSpeakerLogic.displayName(speaker: "Sprecher 2", group: 2, renames: r), "Chef")
        XCTAssertEqual(GroupSpeakerLogic.displayName(speaker: "Sprecher 1", group: 1, renames: r,
                                                     defaultLabel: { "Speaker \($0)" }), "Speaker 1")
        XCTAssertEqual(GroupSpeakerLogic.displayName(speaker: "Anna", group: 2, renames: r), "Anna")
        XCTAssertNil(GroupSpeakerLogic.displayName(speaker: nil, group: nil, renames: r))
    }

    func testNumbersSortedUnique() {
        XCTAssertEqual(GroupSpeakerLogic.numbers(from: [3, nil, 1, 3, 0, 2]), [1, 2, 3])
    }

    // MARK: Quelle
    func testAudioSource() {
        XCTAssertEqual(AudioSourceLogic.normalize("system"), "system")
        XCTAssertEqual(AudioSourceLogic.normalize("foo"), "mic")
        XCTAssertEqual(AudioSourceLogic.normalize(nil), "mic")
        XCTAssertEqual(AudioSourceLogic.launchArgs("system"), ["--source", "system"])
        XCTAssertEqual(AudioSourceLogic.launchArgs("mic"), [])
    }

    // MARK: Schalter / Fähigkeiten
    func testCapsParsing() {
        let caps = ExperimentalLogic.parseCaps(["control:llm_stream", "feature:system_audio", 3, "", "control:llm_stream"])
        XCTAssertEqual(caps, ["control:llm_stream", "feature:system_audio"])
        XCTAssertEqual(ExperimentalLogic.parseCaps(nil), [])
        XCTAssertTrue(ExperimentalLogic.supported("llm_stream", caps: caps))
        XCTAssertFalse(ExperimentalLogic.supported("defer", caps: caps))
        XCTAssertTrue(ExperimentalLogic.feature("system_audio", caps: caps))
    }

    func testControlsAfterReadyOnlyEnabledAndSupported() {
        let caps = ["control:llm_stream", "control:defer"]
        let sent = ExperimentalLogic.controlsAfterReady(
            enabled: ["llm_stream": true, "defer": false, "llm_router": true, "bogus": true], caps: caps)
        XCTAssertEqual(sent, ["llm_stream": true])
        XCTAssertEqual(ExperimentalLogic.controlsAfterReady(enabled: ["llm_stream": true], caps: []), [:])
    }

    func testParseSwitchesIgnoresUnknownAndNonBool() {
        let s = ExperimentalLogic.parseSwitches(["llm_stream": true, "defer": "yes", "x": true, "speak_numbers": false])
        XCTAssertEqual(s, ["llm_stream": true, "speak_numbers": false])
        XCTAssertEqual(ExperimentalLogic.activeCount(s), 1)
    }

    // MARK: Latenz-Verteilung
    func testLatencyHistParse() {
        let raw: [String: Any] = [
            "stt": ["n": 12, "p50": 0.6, "p95": 1.4],
            "tr": ["n": 0, "p50": 0.2, "p95": 0.3],          // n = 0: weg
            "sound": ["n": 5, "p50": 2.0, "p95": 1.0],       // p95 < p50: ungültig
        ]
        let rows = LatencyHistLogic.parse(raw)
        XCTAssertEqual(rows, [LatencyHistLogic.Row(kind: "stt", n: 12, p50: 0.6, p95: 1.4)])
        XCTAssertEqual(LatencyHistLogic.parse("x"), [])
        XCTAssertEqual(LatencyHistLogic.fraction(0.7, rows: rows), 0.5, accuracy: 0.001)
        XCTAssertEqual(LatencyHistLogic.fraction(1, rows: []), 0)
        XCTAssertEqual(LatencyHistLogic.seconds(1.44), "1.4 s")
    }

    // MARK: mic_gap
    func testMicGapTrackerWindow() {
        var t = MicGapTracker()
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(t.visible(t0))
        t.register(t0); t.register(t0.addingTimeInterval(5))
        XCTAssertEqual(t.count, 2)
        XCTAssertTrue(t.visible(t0.addingTimeInterval(60)))
        XCTAssertFalse(t.visible(t0.addingTimeInterval(200)))
        XCTAssertFalse(t.visible(t0.addingTimeInterval(-10)))   // Uhr zurückgestellt
        t.reset()
        XCTAssertEqual(t.count, 0)
    }

    // MARK: Verlauf-Passwort
    func testHistoryPasswordRules() {
        XCTAssertTrue(HistoryPasswordLogic.isValid("geheim pass"))
        XCTAssertFalse(HistoryPasswordLogic.isValid(""))
        XCTAssertFalse(HistoryPasswordLogic.isValid("a\nb"))
        XCTAssertFalse(HistoryPasswordLogic.isValid(String(repeating: "a", count: 257)))
        XCTAssertNil(HistoryPasswordLogic.envValue(enabled: false, password: "pw"))
        XCTAssertNil(HistoryPasswordLogic.envValue(enabled: true, password: nil))
        XCTAssertEqual(HistoryPasswordLogic.envValue(enabled: true, password: "pw"), "pw")
        XCTAssertEqual(HistoryPasswordLogic.controlValue(enabled: false, password: "pw"), "")
        XCTAssertEqual(HistoryPasswordLogic.controlValue(enabled: true, password: "pw"), "pw")
    }

    func testHistoryPasswordEnvAndCLI() {
        XCTAssertTrue(HistoryPasswordLogic.needsEnv(args: ["--history-export", "json"]))
        XCTAssertTrue(HistoryPasswordLogic.needsEnv(args: ["--history-clear"]))
        XCTAssertFalse(HistoryPasswordLogic.needsEnv(args: ["--list-profiles"]))
        var env = [HistoryPasswordLogic.envName: "stale", "PATH": "/usr/bin"]
        HistoryPasswordLogic.apply(to: &env, enabled: false, password: "pw")
        XCTAssertNil(env[HistoryPasswordLogic.envName])          // altes Passwort wird nie durchgereicht
        HistoryPasswordLogic.apply(to: &env, enabled: true, password: "pw")
        XCTAssertEqual(env[HistoryPasswordLogic.envName], "pw")
        XCTAssertEqual(env["PATH"], "/usr/bin")
    }

    // MARK: msg_en
    func testErrorFallbackUsesEnglishText() {
        XCTAssertEqual(ErrorTextLogic.fallback(msg: "Fehler", msgEn: "Error", german: false), "Error")
        XCTAssertEqual(ErrorTextLogic.fallback(msg: "Fehler", msgEn: "Error", german: true), "Fehler")
        XCTAssertEqual(ErrorTextLogic.fallback(msg: "Fehler", msgEn: nil, german: false), "Fehler")
        XCTAssertEqual(ErrorTextLogic.fallback(msg: "Fehler", msgEn: "", german: false), "Fehler")
        XCTAssertNil(ErrorTextLogic.fallback(msg: nil, msgEn: nil, german: false))
    }

    // MARK: Review-Fund: riesige Beträge
    func testHugeAmountIsRejectedInsteadOfCrashing() {
        XCTAssertNil(PriceLogic.parseAmount(String(repeating: "9", count: 40)))
        XCTAssertNil(PriceLogic.parseAmount("1" + String(repeating: "0", count: 13)))
        XCTAssertEqual(PriceLogic.parseAmount("1.200"), 1200)
    }
}
