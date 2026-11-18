import XCTest
@testable import Dolmetscher

/// Runde 17: Kurzbefehle – Paar tauschen, letzte Übersetzung, Satz per Stichwort.
final class Round17Tests: XCTestCase {
    private func phrase(_ en: String, de: String? = nil) -> Phrase {
        Phrase(en: en, th: "x", roman: "x", category: "basics", de: de)
    }

    func testSwapExchangesLanguagesAndIsItsOwnInverse() {
        let p = LangPair(mine: .en, partner: .th)
        XCTAssertEqual(PairSwitch.swapped(p), LangPair(mine: .th, partner: .en))
        XCTAssertEqual(PairSwitch.swapped(PairSwitch.swapped(p)), p)
    }

    func testLastSpeechSkipsEntriesWithoutTranslation() {
        let a = Entry(src: .en, dst: .th, text: "a", translation: "ก")
        let b = Entry(src: .en, dst: .th, text: "b", translation: "  ")
        let c = Entry(src: .en, dst: .th, text: "c", translation: nil)
        XCTAssertEqual(LastSpeech.pick([a, b, c])?.id, a.id)
        XCTAssertNil(LastSpeech.pick([b, c]))
        XCTAssertNil(LastSpeech.pick([]))
    }

    func testNormalizeIgnoresCaseAccentsAndPunctuation() {
        XCTAssertEqual(PhraseMatcher.normalize("  How MUCH is this?! "), "how much is this")
        XCTAssertEqual(PhraseMatcher.normalize("Café"), "cafe")
    }

    func testBestPrefersExactThenPrefixThenContains() {
        let list = [phrase("Thank you very much"), phrase("Thank you"), phrase("I said thank you")]
        XCTAssertEqual(PhraseMatcher.best("thank you", in: list)?.en, "Thank you")
        XCTAssertEqual(PhraseMatcher.best("thank", in: list)?.en, "Thank you")
        XCTAssertEqual(PhraseMatcher.best("said", in: list)?.en, "I said thank you")
    }

    func testBestMatchesGermanGlossAndRejectsNoise() {
        let list = [phrase("Hello", de: "Hallo"), phrase("Thank you", de: "Danke")]
        XCTAssertEqual(PhraseMatcher.best("danke", in: list)?.en, "Thank you")
        XCTAssertNil(PhraseMatcher.best("zebra", in: list))
        XCTAssertNil(PhraseMatcher.best("   ", in: list))
    }

    func testTextsCompleteInAllLanguagesWithSamePlaceholders() {
        let langs = ["de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id"]
        XCTAssertEqual(L10n.round17.count, 4)
        for (key, row) in L10n.round17 {
            XCTAssertEqual(Set(row.keys), Set(langs), key)
            let ph = row["en"]!.components(separatedBy: "%@").count
            for (l, v) in row { XCTAssertFalse(v.isEmpty, "\(key) \(l)"); XCTAssertEqual(v.components(separatedBy: "%@").count, ph, "\(key) \(l)") }
        }
        for l in WidgetTexts.languages {
            for k in ["w_swap", "w_swap_d", "w_speak_last", "w_speak_last_d"] { XCTAssertNotNil(WidgetTexts.table[k]?[l], "\(k) \(l)") }
        }
    }
}
