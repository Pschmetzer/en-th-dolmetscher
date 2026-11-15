import XCTest
@testable import Dolmetscher

final class LogicTests: XCTestCase {
    func testCommandsWithWakeWord() {
        XCTAssertEqual(Commands.detect("Translator, pause."), .pause)
        XCTAssertEqual(Commands.detect("Hey translator resume"), .resume)
        XCTAssertEqual(Commands.detect("Translator, repeat"), .repeat)
        XCTAssertEqual(Commands.detect("OK Translator, slower please"), .slower)
        XCTAssertEqual(Commands.detect("Translator louder"), .louder)
        XCTAssertEqual(Commands.detect("Translator, quieter"), .quieter)
        XCTAssertEqual(Commands.detect("Translator."), .wake)
    }

    func testFuzzyWakeNeedsCommand() {
        XCTAssertEqual(Commands.detect("Translate or pause"), .pause)
        XCTAssertNil(Commands.detect("Translate this for me"))
    }

    func testNoWakeWordMeansTranslate() {
        XCTAssertNil(Commands.detect("Please pause the music"))
        XCTAssertNil(Commands.detect("Where is the toilet?"))
        XCTAssertNil(Commands.detect("The translator is a nice person"))
    }

    func testAwakeWindowAcceptsBareCommand() {
        XCTAssertEqual(Commands.detect("pause", awake: true), .pause)
        XCTAssertNil(Commands.detect("Where is the toilet?", awake: true))
    }

    func testThaiShareAndTyped() {
        XCTAssertEqual(LanguagePick.thaiShare("ห้องน้ำอยู่ที่ไหน"), 1, accuracy: 0.001)
        XCTAssertEqual(LanguagePick.thaiShare("Where is it?"), 0, accuracy: 0.001)
        XCTAssertEqual(LanguagePick.ofTyped("ขอบคุณครับ"), .th)
        XCTAssertEqual(LanguagePick.ofTyped("Thank you 123"), .en)
    }

    func testPickLanguage() {
        let h = { (t: String, c: Double) in Hypothesis(text: t, confidence: c) }
        XCTAssertNil(LanguagePick.pick(en: nil, th: nil))
        XCTAssertEqual(LanguagePick.pick(en: h("Hello", 0.4), th: nil), .en)
        XCTAssertEqual(LanguagePick.pick(en: nil, th: h("สวัสดี", 0.4)), .th)
        // Thai-Erkenner schreibt lateinisch -> es war Englisch
        XCTAssertEqual(LanguagePick.pick(en: h("Where is the toilet", 0.5), th: h("Where is the toilet", 0.9)), .en)
        // Weckwort gewinnt immer
        XCTAssertEqual(LanguagePick.pick(en: h("Translator, pause", 0.3), th: h("ทรานสเลเตอร์ พอส", 0.9)), .en)
        // sonst entscheidet die Konfidenz
        XCTAssertEqual(LanguagePick.pick(en: h("Chan non crap", 0.3), th: h("ฉันง่วงนอนครับ", 0.8)), .th)
        XCTAssertEqual(LanguagePick.pick(en: h("I am very tired", 0.9), th: h("ไอแอมเวรี่ไทร์", 0.4)), .en)
    }
}

final class PolitenessTests: XCTestCase {
    func testMaleReplacesFemaleParticles() {
        XCTAssertEqual(Politeness.male.adjust("ขอโทษค่ะ สถานีรถไฟอยู่ที่ไหนคะ?"), "ขอโทษครับ สถานีรถไฟอยู่ที่ไหนครับ?")
    }

    func testFemaleUsesQuestionForm() {
        XCTAssertEqual(Politeness.female.adjust("ราคาเท่าไหร่ครับ?"), "ราคาเท่าไหร่คะ?")
        XCTAssertEqual(Politeness.female.adjust("ขอบคุณครับ"), "ขอบคุณค่ะ")
    }

    func testOffAndMissingParticle() {
        XCTAssertEqual(Politeness.off.adjust("ขอบคุณค่ะ"), "ขอบคุณค่ะ")
        XCTAssertEqual(Politeness.off.adjust("ราคาเท่าไหร่?"), "ราคาเท่าไหร่?")
        XCTAssertEqual(Politeness.male.adjust("ห้องน้ำอยู่ที่ไหน?"), "ห้องน้ำอยู่ที่ไหนครับ?")
        XCTAssertEqual(Politeness.female.adjust("ราคาเท่าไหร่?"), "ราคาเท่าไหร่คะ?")
        XCTAssertEqual(Politeness.female.adjust("ฉันหิว"), "ฉันหิวค่ะ")
        XCTAssertEqual(Politeness.male.adjust("ไปกันนะ"), "ไปกันนะ")
        XCTAssertEqual(Politeness.male.adjust("Pad Thai 80"), "Pad Thai 80")
    }

    func testParticleInsideWordUntouched() {
        // „ครับผม“ ist eine feste Wendung; mitten im Wort nichts ersetzen.
        XCTAssertEqual(Politeness.female.adjust("ครับผม"), "ครับผม")
    }

    func testFill() {
        XCTAssertEqual(Politeness.female.fill("{i}ไม่เข้าใจ{p} พูดได้ไหม{q}"), "ฉันไม่เข้าใจค่ะ พูดได้ไหมคะ")
        XCTAssertEqual(Politeness.male.fillRoman("mai khao jai {p}"), "mai khao jai khrap")
        XCTAssertEqual(Politeness.off.fillRoman("khop khun {p}"), "khop khun")
    }

    func testPhrasebookTemplatesAreFilled() {
        for p in Phrasebook.builtIn {
            for form in Politeness.allCases {
                XCTAssertFalse(form.fill(p.th).contains("{"), p.en)
                XCTAssertFalse(form.fillRoman(p.roman).contains("{"), p.en)
            }
        }
    }
}
