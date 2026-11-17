// Round6Tests.swift – Runde 6: Sprachausgabe, Kulturhinweise, Speicher, Zusammenfassung, Korpus-Tests.
import XCTest
@testable import Dolmetscher

final class Round6Tests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("r6-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: 906 Langsam und deutlich

    func testClearSpeechChunks() {
        XCTAssertEqual(ClearSpeech.chunks("Hello, how are you? Fine.", lang: .en), ["Hello,", "how are you?", "Fine."])
        // Thai: Leerzeichen trennt Satzteile.
        XCTAssertEqual(ClearSpeech.chunks("สวัสดีครับ ไปสนามบินเท่าไหร่ครับ", lang: .th), ["สวัสดีครับ", "ไปสนามบินเท่าไหร่ครับ"])
        // Latein: Leerzeichen trennt nicht (sonst Wort für Wort).
        XCTAssertEqual(ClearSpeech.chunks("How much is it", lang: .en), ["How much is it"])
        XCTAssertNil(ClearSpeech.ssml("How much is it", lang: .en), "nichts zu trennen: normaler Text")
    }

    func testClearSpeechSSMLEscapes() throws {
        let s = try XCTUnwrap(ClearSpeech.ssml("Tom & Jerry, <b>", lang: .en))
        XCTAssertTrue(s.hasPrefix("<speak>") && s.hasSuffix("</speak>"))
        XCTAssertTrue(s.contains("Tom &amp; Jerry,"))
        XCTAssertTrue(s.contains("&lt;b&gt;"))
        XCTAssertTrue(s.contains(#"<break time="350ms"/>"#))
    }

    func testClearSpeechTimeoutGrowsWhenSlow() {
        let normal = ClearSpeech.timeout(chars: 40, rate: 1, pauses: 0)
        XCTAssertEqual(normal, 18, accuracy: 0.001)
        XCTAssertGreaterThan(ClearSpeech.timeout(chars: 40, rate: 0.5, pauses: 3), normal * 2)
    }

    // MARK: 600 Text für die Stimme

    func testSpeechTextNormalize() {
        XCTAssertEqual(SpeechText.normalize("ราคา ฿120", lang: .th), "ราคา 120 บาท")
        XCTAssertEqual(SpeechText.normalize("120฿ ที่ 7-Eleven", lang: .th), "120 บาท ที่ เซเว่นอีเลฟเว่น")
        XCTAssertEqual(SpeechText.normalize("It costs ฿1,200", lang: .en), "It costs 1,200 baht")
        XCTAssertEqual(SpeechText.normalize("Hello", lang: .en), "Hello")
    }

    // MARK: Kulturhinweise

    func testCultureHintMatchesPack() {
        XCTAssertFalse(Phrasebook.packs.isEmpty, "presets im Bundle")
        XCTAssertEqual(CultureHint.pack(for: "Can we visit the temple tomorrow?", packs: Phrasebook.packs)?.id, "temple")
        XCTAssertEqual(CultureHint.pack(for: "ไปวัดพระแก้ว", packs: Phrasebook.packs)?.id, "temple")
        XCTAssertEqual(CultureHint.pack(for: "Please use the meter", packs: Phrasebook.packs)?.id, "taxi")
        // Ganzes Wort: „thermometer“ ist kein Taxameter.
        XCTAssertNil(CultureHint.pack(for: "I need a thermometer", packs: Phrasebook.packs.filter { $0.id == "taxi" }))
        // Schon gezeigt: nicht noch einmal.
        XCTAssertNil(CultureHint.pack(for: "temple", packs: Phrasebook.packs, skip: ["temple"]))
        XCTAssertNil(CultureHint.keywords["hotel"], "Hotel hat keinen Hinweis")
        for id in CultureHint.keywords.keys {
            XCTAssertNotNil(Phrasebook.packs.first { $0.id == id }?.noteText("en"), "Stichwörter für \(id) ohne Paket/Hinweis")
        }
    }

    @MainActor
    func testCultureHintOncePerSession() {
        let m = InterpreterModel(files: JSONStore(dir: dir))
        m.pair = .standard
        m.cultureHints = true
        m.noteCulture("Where is the temple?", nil)
        XCTAssertEqual(m.cultureHint, "temple")
        m.cultureHint = nil
        m.noteCulture("The temple is closed", nil)
        XCTAssertNil(m.cultureHint, "einmal je Paket")
        m.cultureHints = false
        m.noteCulture("Call the police", nil)
        XCTAssertNil(m.cultureHint, "abgeschaltet")
        m.cultureHints = true
    }

    // MARK: 592 Sprache beim Tippen

    func testTypedLanguageCheck() {
        XCTAssertEqual(TypedLanguageCheck.foreign("Wo ist bitte der nächste Bahnhof hier in der Nähe?", pair: .standard), "de")
        XCTAssertNil(TypedLanguageCheck.foreign("Where is the nearest train station please?", pair: .standard))
        XCTAssertNil(TypedLanguageCheck.foreign("ห้องน้ำอยู่ที่ไหนครับ ขอบคุณมากครับ ผมหาไม่เจอ", pair: .standard))
        XCTAssertNil(TypedLanguageCheck.foreign("Danke", pair: .standard), "zu kurz")
        XCTAssertEqual(TypedLanguageCheck.base("zh-Hans"), "zh")
    }

    // MARK: Zusammenfassung

    func testSummaryUsesMyLanguageOnly() {
        let es = [
            Entry(src: .en, dst: .th, text: "How much to the airport?", translation: "ไปสนามบินเท่าไหร่"),
            Entry(src: .th, dst: .en, text: "สี่ร้อยบาท", translation: "Four hundred baht"),
            Entry(src: .th, dst: .en, text: "ไม่รู้", translation: nil),
        ]
        XCTAssertEqual(ConversationSummary.lines(es, mine: .en), ["A: How much to the airport?", "B: Four hundred baht"])
        XCTAssertTrue(ConversationSummary.prompt(["A: x"]).contains("A: x"))
        XCTAssertTrue(ConversationSummary.instructions(language: "German").contains("German"))
        XCTAssertEqual(ConversationSummary.lines(Array(repeating: es[0], count: 200), mine: .en).count, 80)
    }

    // MARK: 581/647 Export

    func testTranscriptExportUsesAppLanguage() {
        let e = Entry(date: Date(timeIntervalSince1970: 1_800_000_000), src: .en, dst: .th, text: "Hi", translation: "สวัสดี")
        let de = TranscriptExport.text([e], lang: "de")
        XCTAssertTrue(de.contains("EN→TH: Hi\n→ สวัสดี"), de)
        XCTAssertTrue(de.contains("15.01.27"), de)
    }

    // MARK: 598 Empfindlichkeit, 593 Lautstärke

    func testSensitivityNormalKeepsOldThresholds() {
        let g = VoiceGate(pause: 0.8)
        let n = VoiceGate(pause: 0.8, sensitivity: .normal)
        XCTAssertEqual(g.factor, n.factor)
        XCTAssertEqual(g.minThreshold, n.minThreshold)
        XCTAssertLessThan(Sensitivity.quiet.factor, Sensitivity.loud.factor)
        XCTAssertLessThan(Sensitivity.quiet.minThreshold, Sensitivity.loud.minThreshold)
    }

    func testVolumeHint() {
        XCTAssertTrue(VolumeHint.tooQuiet(0.05))
        XCTAssertFalse(VolumeHint.tooQuiet(0.5))
    }

    // MARK: 604/566/579 Speicher

    func testLossyHistoryKeepsGoodEntriesAndBackup() throws {
        let s = JSONStore(dir: dir)
        let json = """
        [{"id":"\(UUID().uuidString)","date":0,"src":"en","text":"good one"},
         {"id":"kaputt","date":"gestern","src":5},
         {"id":"\(UUID().uuidString)","date":10,"src":"th","text":"ดี"}]
        """
        try Data(json.utf8).write(to: s.url("history.json"))
        let loaded = try XCTUnwrap(s.loadLossy(Entry.self, "history.json").value)
        XCTAssertEqual(loaded.map(\.text), ["good one", "ดี"])
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("history.json.bak-") }, "\(names)")
        try Data("{".utf8).write(to: s.url("broken.json"))
        guard case .corrupt = s.loadLossy(Entry.self, "broken.json") else { return XCTFail("corrupt") }
    }

    func testStoredFilesAreExcludedFromBackup() throws {
        let s = JSONStore(dir: dir)
        XCTAssertTrue(s.store(["a"], "favorites.json"))
        XCTAssertTrue(s.store(["b"], "favorites.json"))   // atomar ersetzt: Merkmal bleibt
        let v = try s.url("favorites.json").resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(v.isExcludedFromBackup, true)
    }

    /// 579: Verlauf einer frühen Version (nur en/th, ohne dst/provider/back) bleibt lesbar.
    func testOldHistoryFixtureStillDecodes() throws {
        let old = """
        [{"id":"\(UUID().uuidString)","date":700000000,"src":"th","text":"สวัสดี","translation":"Hello"},
         {"id":"\(UUID().uuidString)","date":700000100,"src":"en","text":"Thanks","translation":"ขอบคุณ","error":null}]
        """
        try Data(old.utf8).write(to: dir.appendingPathComponent("history.json"))
        let e = try XCTUnwrap(JSONStore(dir: dir).loadLossy(Entry.self, "history.json").value)
        XCTAssertEqual(e.count, 2)
        XCTAssertEqual(e[0].target, .en)
        XCTAssertEqual(e[1].target, .th)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(names.contains { $0.contains(".bak-") }, "nichts verworfen")
    }

    @MainActor
    func testPersistIsDebouncedAndWipeDropsPending() async throws {
        let s = JSONStore(dir: dir)
        let m = InterpreterModel(files: s)
        m.historyDays = 30
        m.submit("Hello there", speak: false)
        m.persistNow()
        InterpreterModel.io.sync {}
        XCTAssertEqual(s.load([Entry].self, "history.json").value?.map(\.text), ["Hello there"])
        // Ausstehendes Schreiben darf „Alle Daten löschen“ nicht überleben.
        m.submit("Second", speak: false)
        m.wipeAll(domain: nil)
        try await Task.sleep(for: .milliseconds(900))
        InterpreterModel.io.sync {}
        // Eine verspätete Übersetzung darf schreiben – aber nur den (leeren) Stand nach dem Löschen.
        XCTAssertEqual(s.load([Entry].self, "history.json").value?.count ?? 0, 0)
    }

    // MARK: 589 Vorlesen je Richtung

    @MainActor
    func testAutoSpeakPerDirection() {
        let m = InterpreterModel(files: JSONStore(dir: dir))
        m.pair = .standard
        m.autoSpeak = true
        m.autoSpeakMine = false
        XCTAssertTrue(m.autoSpeaks(.th))
        XCTAssertFalse(m.autoSpeaks(.en))
        m.autoSpeakMine = true
        XCTAssertTrue(m.autoSpeaks(.en))
        m.autoSpeak = false
        XCTAssertFalse(m.autoSpeaks(.th))
        m.autoSpeak = true
    }

    // MARK: 555 Sprache der Oberfläche beobachtbar

    func testUILanguageIsObservable() {
        let before = L10n.lang
        defer { L10n.lang = before }
        L10n.lang = "de"
        var changed = false
        withObservationTracking { _ = T("close") } onChange: { changed = true }
        L10n.lang = "th"
        XCTAssertTrue(changed)
        XCTAssertEqual(T("close"), "ปิด")
    }

    // MARK: 577 Satzbuch

    func testBuiltInPhrasebookIsConsistent() throws {
        let ids = Phrasebook.builtIn.map(\.id)
        let dupes = Dictionary(grouping: ids, by: { $0 }).filter { $1.count > 1 }.keys
        XCTAssertTrue(dupes.isEmpty, "doppelte en-Schlüssel: \(dupes)")
        let cats = Set(Phrasebook.categories.map(\.key))
        let rx = try NSRegularExpression(pattern: #"\{[a-z]\}"#)
        func marks(_ s: String) -> [String] {
            rx.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range, in: s)!]) }.sorted()
        }
        for p in Phrasebook.builtIn {
            XCTAssertTrue(cats.contains(p.category), "\(p.en): Kategorie \(p.category)")
            XCTAssertFalse(p.th.isEmpty, p.en)
            XCTAssertFalse(p.roman.isEmpty, "\(p.en): Umschrift fehlt")
            XCTAssertEqual(marks(p.th), marks(p.roman), "\(p.en): Platzhalter Thai/Umschrift")
        }
    }

    // MARK: Live-Aktivität und Datenschutz

    func testLiveActivityDefaultsOffForNewUsersOnly() {
        XCTAssertFalse(LivePrivacy.initialSetting(stored: nil, existingUser: false), "neue Installation: aus")
        XCTAssertTrue(LivePrivacy.initialSetting(stored: nil, existingUser: true), "bisheriger Standard bleibt")
        XCTAssertTrue(LivePrivacy.initialSetting(stored: true, existingUser: false))
        XCTAssertFalse(LivePrivacy.initialSetting(stored: false, existingUser: true))
    }

    func testLiveActivityHidesSentencesWhenLocked() throws {
        XCTAssertEqual(LivePrivacy.text("Allergic to peanuts", locked: true), "")
        XCTAssertEqual(LivePrivacy.text("Hello", locked: false), "Hello")
        XCTAssertEqual(LivePrivacy.text(nil, locked: false), "")
        // Älterer Zustand ohne `hidden` bleibt lesbar.
        let old = #"{"status":"listening","statusText":"x","source":"a","translation":"b","srcFlag":"1","dstFlag":"2"}"#
        let st = try JSONDecoder().decode(ListeningActivityAttributes.ContentState.self, from: Data(old.utf8))
        XCTAssertNil(st.hidden)
        XCTAssertFalse(WidgetTexts.text("w_hidden", lang: "de").isEmpty)
    }

    // MARK: 578 Befehls-Korpus

    func testOrdinarySentencesAreNoCommands() {
        let corpus = [
            "Pass me the salt please", "A quiet room please", "Can you stop at the next corner", "I want to start a new account",
            "Please repeat the address slowly", "This one is slower than the other", "Can you go faster than that",
            "Is it louder at night here", "The water is very clear today", "I need help with my luggage",
            "Delete the photo from yesterday", "Please speak a bit louder", "The pose in this photo is nice",
            "Is there a pool at the hotel", "We will continue tomorrow morning", "My friend Paul is coming later",
            "Two coffees and a croissant please", "Where is the nearest pharmacy", "How much does this cost",
            "Can I pay by card", "I am allergic to peanuts", "Please take me to the airport", "Is breakfast included",
            "What time does the market open", "Do you have a smaller size", "Can you wrap it as a gift",
            "The room is too cold", "I lost my passport", "Call an ambulance", "We are looking for the night market",
            "Translate this menu for me please", "Translate: please stop here", "I like to translate old books",
            "The translator app is great", "Could you write the price down", "Is the museum open on Monday",
            "Please clean the room later", "I will pause my trip for a week", "We had a quiet dinner yesterday",
            "Is the beach far from here", "One ticket to Chiang Mai", "I would like the bill please",
            "Not spicy please", "Can you recommend a good restaurant", "Thank you very much for your help",
            "Where can I buy a SIM card", "How long does the ferry take", "What is your name", "Nice to meet you",
            "See you tomorrow",
        ]
        XCTAssertGreaterThanOrEqual(corpus.count, 50)
        for s in corpus {
            XCTAssertNil(Commands.detect(s), "kein Befehl: \(s)")
            if s.split(separator: " ").count > 3 {
                XCTAssertNil(Commands.detect(s, awake: true), "kein Befehl nach Weckwort: \(s)")
            }
        }
    }

    func testTypicalMishearingsAreCommands() {
        let cases: [(String, VoiceCommand)] = [
            ("Translator, pause", .pause), ("Translator pours", .pause), ("Translator, paws", .pause),
            ("Translator, porsche", .pause), ("Translator, pulse", .pause), ("Translator, post", .pause),
            ("Translator, pose", .pause), ("Translator, pals", .pause), ("Hey translator, mute", .pause),
            ("Translator, presume", .resume), ("Translator, rezoom", .resume), ("Translator, continue", .resume),
            ("Translator, go on", .resume), ("OK translator, wake up", .resume), ("Translator, re-peat", .repeat),
            ("Translator, say that again", .repeat), ("Translator, repeats", .repeat), ("Translator, slow down", .slower),
            ("Translator, slowly", .slower), ("Translator, speed up", .faster), ("Translator, quicker", .faster),
            ("Translator, lauder", .louder), ("Translator, volume up", .louder), ("Translator, softer", .quieter),
            ("Translator, volume down", .quieter), ("Translator, reset", .clear), ("Translator, clean", .clear),
            ("Translator, commands", .help), ("Translate or pause", .pause), ("Translate to repeat", .repeat),
        ]
        XCTAssertGreaterThanOrEqual(cases.count, 30)
        for (s, c) in cases { XCTAssertEqual(Commands.detect(s), c, s) }
    }
}
