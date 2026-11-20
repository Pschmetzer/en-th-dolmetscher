import XCTest
@testable import Dolmetscher

@MainActor
final class Round25Tests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: "r25-" + UUID().uuidString)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func model() -> InterpreterModel {
        let m = InterpreterModel(files: JSONStore(dir: dir))
        m.autoSpeak = false; m.liveActivity = false; m.historyDays = 30; m.checkModels = false
        return m
    }

    func testPartnerEmergencyNumbers() {
        XCTAssertEqual(PartnerEmergency.numbers(for: Lang(rawValue: "ja")!).map(\.number), ["110", "119"])
        // Korea und China: nur Reiseführer als Quelle -> keine Nummer (lieber keine als eine falsche)
        XCTAssertTrue(PartnerEmergency.numbers(for: Lang(rawValue: "ko")!).isEmpty)
        XCTAssertTrue(PartnerEmergency.numbers(for: Lang(rawValue: "zh")!).isEmpty)
        XCTAssertEqual(PartnerEmergency.numbers(for: Lang(rawValue: "id")!).map(\.number), ["112", "110", "113"])
        XCTAssertNotNil(L10n.round25["em_n_unknown"])
        XCTAssertTrue(PartnerEmergency.numbers(for: .th).isEmpty)   // Thai hat einen eigenen Bildschirm
        for code in ["ja", "vi", "id", "de", "fr", "es"] {
            let list = PartnerEmergency.numbers(for: Lang(rawValue: code)!)
            XCTAssertFalse(list.isEmpty, code)
            for n in list {
                XCTAssertTrue(n.number.allSatisfy(\.isNumber), n.number)
                XCTAssertNotNil(L10n.round25[n.kind.textKey], n.kind.textKey)
            }
        }
    }

    func testBuiltInPhraseIsMachineOnlyWithoutThai() {
        let m = model()
        let p = Phrasebook.builtIn[0]
        m.pair = LangPair(mine: .en, partner: .th)
        XCTAssertFalse(m.isMachinePhrase(p))
        m.pair = LangPair(mine: .de, partner: Lang(rawValue: "ja")!)
        XCTAssertTrue(m.isMachinePhrase(p))
    }

    func testSayMachinePhraseCreatesEnglishSourceEntryForPartner() {
        let m = model()
        m.pair = LangPair(mine: .de, partner: Lang(rawValue: "ja")!)
        m.say(Phrasebook.builtIn[0])
        let e = m.entries.last
        XCTAssertEqual(e?.src, .en)
        XCTAssertEqual(e?.target, Lang(rawValue: "ja"))
        XCTAssertEqual(e?.text, Phrasebook.builtIn[0].en)
    }

    func testSayMachinePhraseWithEnglishPartnerNeedsNoTranslation() {
        let m = model()
        m.pair = LangPair(mine: .de, partner: .en)
        m.say(Phrasebook.builtIn[0])
        XCTAssertEqual(m.entries.last?.translation, Phrasebook.builtIn[0].en)
        XCTAssertEqual(m.entries.last?.provider, "phrasebook")
    }

    func testTextsComplete() {
        let langs = ["de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id"]
        XCTAssertFalse(L10n.round25.isEmpty)
        for (k, row) in L10n.round25 {
            XCTAssertEqual(Set(row.keys), Set(langs), k)
            XCTAssertTrue(row.values.allSatisfy { !$0.isEmpty }, k)
        }
    }
}

final class Round25WhisperTests: XCTestCase {
    func testModelFilesNeedCoreMLData() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "r25w-" + UUID().uuidString)
        defer { try? fm.removeItem(at: dir) }
        let names = ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "MelSpectrogram.mlmodelc"]
        for n in names { try fm.createDirectory(at: dir.appending(path: n), withIntermediateDirectories: true) }
        XCTAssertFalse(WhisperStore.hasModelFiles(in: dir), "leere Ordner zählen nicht")
        for n in names { fm.createFile(atPath: dir.appending(path: n).appending(path: "coremldata.bin").path, contents: Data([1])) }
        XCTAssertTrue(WhisperStore.hasModelFiles(in: dir))
        try fm.removeItem(at: dir.appending(path: "TextDecoder.mlmodelc/coremldata.bin"))
        XCTAssertFalse(WhisperStore.hasModelFiles(in: dir))
    }
}
