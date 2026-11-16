import XCTest
@testable import Dolmetscher

/// Runde 3: Gesprächs-Hinweise für die Sprachwahl.
final class TurnTakingTests: XCTestCase {
    private let enth = LangPair.standard

    func testExpectWinsWhenScriptAllows() {
        // Beide Erkenner liefern Lateinisch-taugliches? Nein: en/th – Thai-Erkenner schreibt Thai, en-Erkenner Latein.
        let hyps: [Lang: Hypothesis] = [.en: Hypothesis(text: "sawadee", confidence: 0.9),
                                        .th: Hypothesis(text: "สวัสดี", confidence: 0.3)]
        // Schrift: beide Kandidaten passen zu ihrer Schrift -> ohne Hinweis gewinnt die Konfidenz.
        XCTAssertEqual(LanguagePick.pick(hyps, pair: enth, commands: false), .en)
        XCTAssertEqual(LanguagePick.pick(hyps, pair: enth, commands: false, expect: .th), .th)
    }

    func testExpectDoesNotOverrideClearScript() {
        // Der Thai-Erkenner schreibt Latein: er hat Englisch gehört – auch wenn „Jetzt Sie“ (Thai) getippt wurde.
        let hyps: [Lang: Hypothesis] = [.en: Hypothesis(text: "Where is the station", confidence: 0.4),
                                        .th: Hypothesis(text: "where is", confidence: 0.9)]
        XCTAssertEqual(LanguagePick.pick(hyps, pair: enth, commands: false, expect: .th), .en)
    }

    func testBiasOnlyDecidesCloseCalls() {
        let de = LangPair(mine: .de, partner: .en)   // gleiche Schrift: nur Konfidenz zählt
        let close: [Lang: Hypothesis] = [.de: Hypothesis(text: "Hallo", confidence: 0.50),
                                         .en: Hypothesis(text: "Hello", confidence: 0.55)]
        XCTAssertEqual(LanguagePick.pick(close, pair: de, commands: false), .en)
        XCTAssertEqual(LanguagePick.pick(close, pair: de, commands: false, bias: .de), .de)
        let clear: [Lang: Hypothesis] = [.de: Hypothesis(text: "Hallo", confidence: 0.30),
                                         .en: Hypothesis(text: "Hello", confidence: 0.80)]
        XCTAssertEqual(LanguagePick.pick(clear, pair: de, commands: false, bias: .de), .en)
    }

    func testTurnBias() {
        XCTAssertEqual(LanguagePick.turnBias(lastSpoken: .en, pair: enth), .th)
        XCTAssertEqual(LanguagePick.turnBias(lastSpoken: .th, pair: enth), .en)
        XCTAssertNil(LanguagePick.turnBias(lastSpoken: nil, pair: enth))
        XCTAssertNil(LanguagePick.turnBias(lastSpoken: .ja, pair: enth))
    }
}
