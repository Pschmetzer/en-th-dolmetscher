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

final class RomanizerTests: XCTestCase {
    func testJapaneseUsesJapaneseReading() throws {
        let r = try XCTUnwrap(Romanizer.latin("東京", .ja))
        XCTAssertTrue(r.contains("tou") || r.contains("tō"), r)
        XCTAssertFalse(r.contains("jing"), "Pinyin statt japanischer Lesung: \(r)")
    }

    func testThaiIsSegmentedAndPlain() throws {
        let r = try XCTUnwrap(Romanizer.latin("ขอบคุณมากครับ", .th))
        XCTAssertEqual(r.split(separator: " ").count, 3, r)
        XCTAssertTrue(r.unicodeScalars.allSatisfy { $0.isASCII }, "nur ASCII: \(r)")
        XCTAssertTrue(r.hasSuffix("khrab"), r)
        let city = try XCTUnwrap(Romanizer.latin("ตั๋วไปเชียงใหม่ราคาเท่าไหร่ครับ", .th))
        XCTAssertTrue(city.unicodeScalars.allSatisfy { $0.isASCII }, "nur ASCII: \(city)")
    }

    func testChineseAndKorean() {
        XCTAssertEqual(Romanizer.latin("你好", .zh), "nǐ hǎo")
        XCTAssertEqual(Romanizer.latin("안녕하세요", .ko), "annyeonghaseyo")
    }

    func testOnlyForScriptLanguages() {
        XCTAssertNil(Romanizer.latin("Hello", .en))
        XCTAssertNil(Romanizer.latin("Hello", .th))   // kein Thai im Text
        XCTAssertNil(Romanizer.latin("Привет", .ru))   // nicht vorgesehen
    }
}

final class BackCheckTests: XCTestCase {
    func testSimilarity() {
        XCTAssertEqual(BackCheck.similarity("Where is the toilet?", "where is the toilet"), 1, accuracy: 0.001)
        XCTAssertGreaterThan(BackCheck.similarity("Where is the toilet?", "Where is the bathroom?"), 0.45)
        XCTAssertLessThan(BackCheck.similarity("Where is the toilet?", "I like green tea very much"), 0.3)
        XCTAssertGreaterThan(BackCheck.similarity("ห้องน้ำอยู่ที่ไหน", "ห้องน้ำอยู่ไหน"), 0.6)
    }

    func testShortSentencesNeverWarn() {
        XCTAssertFalse(BackCheck.deviates(original: "Yes", back: "Correct"))
        XCTAssertTrue(BackCheck.deviates(original: "Please take me to the airport", back: "Bring the plane to me"))
        XCTAssertFalse(BackCheck.deviates(original: "Please take me to the airport", back: "Please take me to the airport."))
    }
}

final class ReviewGateTests: XCTestCase {
    func testAsksAfterFiveRealConversationsOncePerVersion() {
        var g = ReviewGate()
        for _ in 0..<4 { g.conversationEnded(translations: 3) }
        g.conversationEnded(translations: 1)   // zu kurz, zählt nicht
        XCTAssertFalse(g.shouldAsk(version: "1.0", busy: false))
        g.conversationEnded(translations: 2)
        XCTAssertTrue(g.shouldAsk(version: "1.0", busy: false))
        XCTAssertFalse(g.shouldAsk(version: "1.0", busy: true), "nie mitten im Gespräch")
        g.asked(version: "1.0")
        for _ in 0..<6 { g.conversationEnded(translations: 5) }
        XCTAssertFalse(g.shouldAsk(version: "1.0", busy: false))
        XCTAssertTrue(g.shouldAsk(version: "1.1", busy: false))
    }

    func testPersistence() {
        let d = UserDefaults(suiteName: "review-test")!
        d.removePersistentDomain(forName: "review-test")
        var g = ReviewGate(); g.conversationEnded(translations: 2); g.asked(version: "2"); g.conversationEnded(translations: 2)
        g.save(d)
        XCTAssertEqual(ReviewGate.load(d), g)
    }
}

final class ThaiNumberTests: XCTestCase {
    func testWords() {
        XCTAssertEqual(ThaiNumber.words(0), "ศูนย์")
        XCTAssertEqual(ThaiNumber.words(1), "หนึ่ง")
        XCTAssertEqual(ThaiNumber.words(10), "สิบ")
        XCTAssertEqual(ThaiNumber.words(11), "สิบเอ็ด")
        XCTAssertEqual(ThaiNumber.words(21), "ยี่สิบเอ็ด")
        XCTAssertEqual(ThaiNumber.words(350), "สามร้อยห้าสิบ")
        XCTAssertEqual(ThaiNumber.words(1200), "หนึ่งพันสองร้อย")
        XCTAssertEqual(ThaiNumber.words(15_000), "หนึ่งหมื่นห้าพัน")
        XCTAssertEqual(ThaiNumber.words(1_000_001), "หนึ่งล้านเอ็ด")
        XCTAssertEqual(ThaiNumber.words(21_000_000), "ยี่สิบเอ็ดล้าน")
        XCTAssertNil(ThaiNumber.words(-1))
    }

    func testNumberCard() {
        var s = ""
        for c in "0350" { s = NumberCard.append(c, to: s) }
        XCTAssertEqual(s, "350")
        XCTAssertEqual(NumberCard.spoken("350", in: .th), "350 (สามร้อยห้าสิบ)")
        XCTAssertEqual(NumberCard.spoken("1200", in: .en), "1,200")
        XCTAssertEqual(NumberCard.spoken("1200", in: .de), "1.200")
    }
}

final class PartnerPhraseTests: XCTestCase {
    func testEveryPairLanguageHasEveryPhrase() {
        for l in Lang.all {
            let row = PartnerPhrases.row(l)
            XCTAssertNotNil(row, "\(l) fehlt")
            XCTAssertEqual(row?.count, PartnerKey.allCases.count, "\(l)")
            for k in PartnerKey.allCases { XCTAssertFalse(PartnerPhrases.text(k, l).isEmpty, "\(l) \(k)") }
        }
    }

    func testAllergyCards() throws {
        for l in Allergen.curated {
            for a in Allergen.allCases { XCTAssertNotNil(a.name(l), "\(l) \(a)") }
            let c = try XCTUnwrap(Allergen.card([.peanut, .fish], in: l, politeness: .female))
            XCTAssertTrue(c.title.contains(Allergen.peanut.name(l)!), "\(l)")
            XCTAssertFalse(c.title.contains("{") || c.warning.contains("{"), "\(l): Platzhalter übrig")
        }
        XCTAssertNil(Allergen.card([.peanut], in: .ru))
        XCTAssertNil(Allergen.card([], in: .th))
        let th = try XCTUnwrap(Allergen.card([.peanut], in: .th, politeness: .male))
        XCTAssertTrue(th.title.hasPrefix("ผมแพ้"), th.title)
        XCTAssertTrue(th.warning.hasSuffix("ครับ"), th.warning)
        let off = try XCTUnwrap(Allergen.card([.peanut], in: .th, politeness: .off))
        XCTAssertFalse(off.warning.hasSuffix("ครับ"), off.warning)
    }
}

final class EmergencyMigrationTests: XCTestCase {
    func testOldCardStillLoads() throws {
        // Format vor Runde 3: ohne Blutgruppe, Allergene, Übersetzungen
        let json = #"{"name":"Alex","hotel":"Riverside","allergies":"Peanuts","medical":"","contact":"+49 1"}"#
        let e = try JSONDecoder().decode(EmergencyInfo.self, from: Data(json.utf8))
        XCTAssertEqual(e.name, "Alex")
        XCTAssertEqual(e.allergies, "Peanuts")
        XCTAssertEqual(e.bloodType, "")
        XCTAssertEqual(e.allergens, [])
        XCTAssertFalse(e.isEmpty)
    }

    func testUnknownAllergenIsSkipped() throws {
        let json = #"{"allergens":["peanut","sesame"]}"#
        let e = try JSONDecoder().decode(EmergencyInfo.self, from: Data(json.utf8))
        XCTAssertEqual(e.allergens, [.peanut])
    }

    func testTranslationGoesStaleWhenTextChanges() throws {
        var e = EmergencyInfo()
        e.allergies = "Peanuts"
        e.translated = ["allergies": "ถั่วลิสง"]
        e.translatedLang = "th"
        e.translatedSource = e.translatableHash
        XCTAssertEqual(e.translation(for: "allergies", lang: .th), "ถั่วลิสง")
        XCTAssertNil(e.translation(for: "allergies", lang: .ja))
        let back = try JSONDecoder().decode(EmergencyInfo.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(back, e)
        e.allergies = "Peanuts, shrimp"
        XCTAssertNil(e.translation(for: "allergies", lang: .th))
    }

    func testEntryRomanizationAndBackCheck() throws {
        var e = Entry(src: .en, dst: .th, text: "Please take me to the airport", translation: "กรุณาพาไปสนามบินครับ")
        XCTAssertNotNil(e.romanized)
        e.roman = "ka-ru-na"
        XCTAssertEqual(e.romanized, "ka-ru-na", "Satzbuch-Umschrift hat Vorrang")
        XCTAssertFalse(e.backDeviates)
        e.back = "Bring the plane to me"
        XCTAssertTrue(e.backDeviates)
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":0,"src":"en","text":"Hi"}"#
        XCTAssertNil(try JSONDecoder().decode(Entry.self, from: Data(old.utf8)).back)
    }
}
