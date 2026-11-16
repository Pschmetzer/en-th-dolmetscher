import XCTest
@testable import Dolmetscher

/// Sprachpaar: Migration alter Daten, Schrift-Anteil, Sprachwahl für mehrere Paare, Gating.
final class MigrationTests: XCTestCase {
    func testOldHistoryEntryDecodes() throws {
        // Format vor dem Sprachpaar: nur "src" (en/th), kein "dst".
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":700000000,"src":"th","text":"สวัสดี","translation":"Hello","provider":"apple"},{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","date":700000001,"src":"en","text":"Hi"}]"#
        let e = try JSONDecoder().decode([Entry].self, from: Data(json.utf8))
        XCTAssertEqual(e.count, 2)
        XCTAssertEqual(e[0].src, .th)
        XCTAssertNil(e[0].dst)
        XCTAssertEqual(e[0].target, .en)
        XCTAssertEqual(e[1].src, .en)
        XCTAssertEqual(e[1].target, .th)
    }

    func testNewEntryRoundTrip() throws {
        let e = Entry(src: .de, dst: .ja, text: "Hallo")
        let back = try JSONDecoder().decode(Entry.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(back.src, .de)
        XCTAssertEqual(back.target, .ja)
        // gespeichert wird nur der Code
        let raw = String(decoding: try JSONEncoder().encode(e), as: UTF8.self)
        XCTAssertTrue(raw.contains(#""src":"de""#), raw)
    }

    func testUnknownCodeDoesNotBreakHistory() throws {
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":0,"src":"xx","text":"?"}]"#
        let e = try JSONDecoder().decode([Entry].self, from: Data(json.utf8))
        XCTAssertEqual(e[0].src.rawValue, "xx")
        // strikt bleibt strikt (Whisper-Codes wie "lo" zählen nicht)
        XCTAssertNil(Lang(rawValue: "lo"))
    }

    func testOldFavoritesDecode() throws {
        let json = #"[{"en":"Thank you","th":"ขอบคุณ{p}","roman":"khop khun {p}","category":"favorites"}]"#
        let f = try JSONDecoder().decode([Phrase].self, from: Data(json.utf8))
        XCTAssertEqual(f[0].srcLang, .en)
        XCTAssertEqual(f[0].dstLang, .th)
    }

    func testDirectionMigration() {
        let p = LangPair.standard
        XCTAssertEqual(Direction.migrate("auto", pair: p), .auto)
        XCTAssertEqual(Direction.migrate("en", pair: p), .mine)
        XCTAssertEqual(Direction.migrate("th", pair: p), .partner)
        XCTAssertEqual(Direction.migrate(nil, pair: p), .auto)
        XCTAssertEqual(Direction.migrate("mine", pair: p), .mine)
        XCTAssertEqual(Direction.migrate("garbage", pair: p), .auto)
        XCTAssertEqual(Direction.auto.langs(p), [.en, .th])
        XCTAssertEqual(Direction.partner.langs(p), [.th])
    }

    func testPairDefaultsWithoutSettings() {
        XCTAssertEqual(LangPair.load(mine: nil, partner: nil), .standard)
        XCTAssertEqual(LangPair.load(mine: "de", partner: nil), LangPair(mine: .de, partner: .th))
        XCTAssertEqual(LangPair.load(mine: "th", partner: "th"), LangPair(mine: .th, partner: .en))
        XCTAssertEqual(LangPair.load(mine: "xx", partner: "ja"), LangPair(mine: .en, partner: .ja))
    }

    func testTableMatchesEngine() {
        XCTAssertEqual(Lang.all.count, 19)
        XCTAssertEqual(Set(Lang.all.map(\.rawValue)),
                       ["en", "th", "de", "es", "fr", "it", "pt", "nl", "ru", "zh", "ja", "ko", "vi", "id", "ar", "hi", "tr", "pl", "uk"])
        XCTAssertEqual(Lang.zh.translationCode, "zh-Hans")
        XCTAssertEqual(Lang.zh.mtCode, "zh-CN")
        XCTAssertEqual(Lang.de.region, "DE")
        XCTAssertEqual(Lang.ja.voiceLocale, "ja-JP")
    }
}

final class ScriptPickTests: XCTestCase {
    private func h(_ t: String, _ c: Double = 0.5) -> Hypothesis { Hypothesis(text: t, confidence: c) }

    func testScriptShare() {
        XCTAssertEqual(Lang.th.scriptShare("ห้องน้ำอยู่ที่ไหน"), 1, accuracy: 0.001)
        XCTAssertEqual(Lang.ja.scriptShare("トイレはどこですか"), 1, accuracy: 0.001)
        XCTAssertEqual(Lang.ja.scriptShare("駅はどこ"), 1, accuracy: 0.001)   // Kanji + Kana
        XCTAssertEqual(Lang.zh.scriptShare("厕所在哪里"), 1, accuracy: 0.001)
        XCTAssertEqual(Lang.ko.scriptShare("화장실이 어디예요"), 1, accuracy: 0.001)
        XCTAssertEqual(Lang.ru.scriptShare("Где туалет"), 1, accuracy: 0.001)
        XCTAssertEqual(Lang.de.scriptShare("Wo ist die Toilette? Grüße"), 1, accuracy: 0.001)
        XCTAssertEqual(Lang.vi.scriptShare("Nhà vệ sinh ở đâu"), 1, accuracy: 0.001)
        XCTAssertEqual(Lang.en.scriptShare("ห้องน้ำ"), 0, accuracy: 0.001)
        XCTAssertEqual(Lang.th.scriptShare("123 !"), 0, accuracy: 0.001)
    }

    func testDistinguishable() {
        let p = { (a: Lang, b: Lang) in LangPair(mine: a, partner: b).distinguishable }
        XCTAssertTrue(p(.en, .th))
        XCTAssertTrue(p(.de, .th))
        XCTAssertTrue(p(.en, .ja))
        XCTAssertTrue(p(.es, .ru))
        XCTAssertFalse(p(.en, .de))
        XCTAssertFalse(p(.es, .fr))
        XCTAssertFalse(p(.ru, .uk))
        XCTAssertFalse(p(.zh, .ja))   // gemeinsame Han-Zeichen
    }

    func testAutoHiddenForSameScript() {
        let enDe = LangPair(mine: .en, partner: .de)
        XCTAssertEqual(Direction.auto.effective(enDe), .mine)
        XCTAssertEqual(Direction.auto.langs(enDe), [.en])
        XCTAssertEqual(Direction.partner.langs(enDe), [.de])
        XCTAssertEqual(Direction.auto.langs(LangPair(mine: .de, partner: .th)), [.de, .th])
    }

    func testPickGermanThai() {
        let p = LangPair(mine: .de, partner: .th)
        // Thai-Erkenner schreibt lateinisch -> es war Deutsch
        XCTAssertEqual(LanguagePick.pick([.de: h("Wo ist die Toilette", 0.4), .th: h("Wo ist die Toilette", 0.9)], pair: p), .de)
        // Deutscher Erkenner hört Thai als Kauderwelsch, Thai-Erkenner liefert Thai: Konfidenz entscheidet
        XCTAssertEqual(LanguagePick.pick([.de: h("Hong nam ju ti nai", 0.3), .th: h("ห้องน้ำอยู่ที่ไหน", 0.8)], pair: p), .th)
        // Kein Englisch im Paar: „Translator, pause“ ist kein Befehl, sondern Text
        XCTAssertEqual(LanguagePick.pick([.de: h("Translator, pause", 0.2), .th: h("ทรานสเลเตอร์ พอส", 0.9)], pair: p), .th)
    }

    func testPickEnglishJapanese() {
        let p = LangPair(mine: .en, partner: .ja)
        XCTAssertEqual(LanguagePick.pick([.en: h("Where is the station", 0.6), .ja: h("Where is the station", 0.9)], pair: p), .en)
        XCTAssertEqual(LanguagePick.pick([.en: h("Eki wa doko", 0.4), .ja: h("駅はどこですか", 0.7)], pair: p), .ja)
        XCTAssertEqual(LanguagePick.pick([.en: h("Translator, repeat", 0.2), .ja: h("トランスレーター", 0.9)], pair: p), .en)
    }

    func testPickEnglishThaiUnchanged() {
        // gleiche Fälle wie LogicTests.testPickLanguage über die neue Schnittstelle
        let p = LangPair.standard
        XCTAssertEqual(LanguagePick.pick([.en: h("Where is the toilet", 0.5), .th: h("Where is the toilet", 0.9)], pair: p), .en)
        XCTAssertEqual(LanguagePick.pick([.en: h("Chan non crap", 0.3), .th: h("ฉันง่วงนอนครับ", 0.8)], pair: p), .th)
        XCTAssertEqual(LanguagePick.pick([.en: h("I am very tired", 0.9), .th: h("ไอแอมเวรี่ไทร์", 0.4)], pair: p), .en)
    }

    func testPartialPreviewNotAlwaysEnglish() {
        // #514: Die Vorschau bekommt jetzt die echte Konfidenz der Erkenner (vorher fest 0.5 für beide,
        // Gleichstand -> immer Englisch).
        let p = LangPair.standard
        XCTAssertEqual(LanguagePick.pick([.en: h("Hong nam yu ti nai", 0.3), .th: h("ห้องน้ำอยู่ที่ไหน", 0.6)], pair: p), .th)
        // Thai-Erkenner liefert (noch) Latein: Englisch, auch bei höherer Thai-Konfidenz
        XCTAssertEqual(LanguagePick.pick([.en: h("Where is", 0.3), .th: h("Where is", 0.9)], pair: p), .en)
        // Gleichstand mit unterschiedlicher Schrift-Treue: die treuere Schrift gewinnt
        XCTAssertEqual(LanguagePick.pick([.en: h("ไอแอม ok", 0.5), .th: h("ห้องน้ำ", 0.5)], pair: p), .th)
    }

    func testTypedLanguage() {
        XCTAssertEqual(LanguagePick.ofTyped("Wo ist das Hotel?", pair: LangPair(mine: .de, partner: .th)), .de)
        XCTAssertEqual(LanguagePick.ofTyped("โรงแรมอยู่ที่ไหน", pair: LangPair(mine: .de, partner: .th)), .th)
        XCTAssertEqual(LanguagePick.ofTyped("ホテルはどこ", pair: LangPair(mine: .en, partner: .ja)), .ja)
        XCTAssertEqual(LanguagePick.ofTyped("ไปสยาม Paragon", pair: .standard), .th)
        // gleiche Schrift: Richtung entscheidet
        let enDe = LangPair(mine: .en, partner: .de)
        XCTAssertEqual(LanguagePick.ofTyped("Guten Tag", pair: enDe, fallback: .de), .de)
        XCTAssertEqual(LanguagePick.ofTyped("Guten Tag", pair: enDe), .en)
    }
}

final class GatingTests: XCTestCase {
    func testThaiExtrasOnlyWithThai() {
        XCTAssertTrue(LangPair.standard.features.thaiExtras)
        XCTAssertTrue(LangPair(mine: .de, partner: .th).features.thaiExtras)
        XCTAssertFalse(LangPair(mine: .en, partner: .ja).features.thaiExtras)
        XCTAssertFalse(LangPair(mine: .de, partner: .es).features.thaiExtras)
    }

    func testVoiceCommandsOnlyWithEnglish() {
        XCTAssertTrue(LangPair.standard.features.voiceCommands)
        XCTAssertTrue(LangPair(mine: .en, partner: .ja).features.voiceCommands)
        XCTAssertTrue(LangPair(mine: .th, partner: .en).features.voiceCommands)
        XCTAssertFalse(LangPair(mine: .de, partner: .th).features.voiceCommands)
    }

    func testAvailabilityLevel() {
        XCTAssertEqual(LangLevel.of(recognizer: .installed, translation: .installed, voice: true), .ready)
        XCTAssertEqual(LangLevel.of(recognizer: .downloadable, translation: .installed, voice: true), .needsDownload)
        XCTAssertEqual(LangLevel.of(recognizer: .installed, translation: .downloadable, voice: true), .needsDownload)
        XCTAssertEqual(LangLevel.of(recognizer: .installed, translation: .installed, voice: false), .needsDownload)
        XCTAssertEqual(LangLevel.of(recognizer: .unsupported, translation: .installed, voice: true), .unavailable)
        XCTAssertEqual(LangLevel.of(recognizer: .installed, translation: .unsupported, voice: true), .unavailable)
    }
}
