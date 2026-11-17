import XCTest
@testable import Dolmetscher

/// Runde 5: Szenario-Pakete im Satzbuch, Favoriten-Migration, Lernmodus (Leitner), Textscan für Ziele, Alles löschen,
/// Halten je Hälfte.
final class ScenarioPackTests: XCTestCase {
    private let presets = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("presets")

    func testEveryPresetFileIsBundled() throws {
        let files = try FileManager.default.contentsOfDirectory(at: presets, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertGreaterThanOrEqual(files.count, 16)
        XCTAssertEqual(Set(Phrasebook.packs.map(\.id)), Set(files.map { $0.deletingPathExtension().lastPathComponent }),
                       "presets/*.json und App-Bundle weichen ab")
        for p in Phrasebook.packs {
            XCTAssertFalse(p.phrases.isEmpty, p.id)
            XCTAssertNotNil(p.names["en"], p.id)
        }
    }

    /// Neue Pakete (z. B. aus einem reinen presets-PR) dürfen ohne Übersetzung kommen – dann gilt Englisch.
    /// Wer in L10n.packNames steht, muss vollständig sein.
    func testPackNameInEveryLanguage() {
        for p in Phrasebook.packs where L10n.packNames[p.id] != nil {
            for lang in L10n.languages {
                let has = p.names[lang] != nil || L10n.packNames[p.id]?[lang] != nil
                XCTAssertTrue(has, "\(p.id): Name fehlt in \(lang)")
            }
        }
    }

    func testCriticalFirstAndMarked() throws {
        for p in Phrasebook.packs {
            let list = p.asPhrases
            XCTAssertEqual(list.count, p.phrases.count)
            if let firstNormal = list.firstIndex(where: { !$0.isCritical }) {
                XCTAssertFalse(list[firstNormal...].contains { $0.isCritical }, "\(p.id): kritische Sätze nicht zuerst")
            }
            XCTAssertTrue(list.allSatisfy { $0.category == p.key && $0.pack == p.id })
        }
        let doctor = try XCTUnwrap(Phrasebook.packs.first { $0.id == "doctor" })
        XCTAssertTrue(doctor.asPhrases.first?.isCritical ?? false)
        XCTAssertNotNil(doctor.noteText("de"))
        XCTAssertEqual(doctor.noteText("ja"), doctor.note?["en"], "ohne eigene Sprache: Englisch")
    }

    func testPackPhrasesInSearchAndMatch() {
        let p = Phrasebook.match("I am allergic to this medicine.", lang: .en)
        XCTAssertEqual(p?.pack, "doctor", "Satzbuch zuerst kennt Paket-Sätze")
        // Gleicher Satz eingebaut und im Paket: die eingebaute Fassung (mit Höflichkeitsform) gewinnt.
        let shared = Phrasebook.match("Do you speak English?", lang: .en)
        XCTAssertNil(shared?.pack)
        XCTAssertTrue(shared?.th.contains("{q}") ?? false)
        // Kritische Sätze nur genau – eine Verneinung darf nie zur geprüften Gegenteil-Fassung werden.
        XCTAssertNil(Phrasebook.match("I am not allergic to this medicine.", lang: .en))
        XCTAssertNil(Phrasebook.match("I am allergic to this medicin", lang: .en), "kritisch: kein Tippfehler-Treffer")
        XCTAssertNotNil(Phrasebook.match("Where is the toilett?", lang: .en), "unkritisch: Tippfehler erlaubt")
        XCTAssertTrue(Phrasebook.negated(Phrasebook.normalize("I don't want ice")))
                XCTAssertEqual(Phrasebook.suggestions("speak english", limit: 10).filter { $0.en == "Do you speak English?" }.count, 1)
    }

    func testPackRomanizedAutomatically() throws {
        let p = try XCTUnwrap(Phrasebook.packs.first?.asPhrases.first)
        XCTAssertTrue(p.roman.isEmpty)
        XCTAssertFalse((Phrasebook.roman(p, politeness: .male) ?? "").isEmpty)
    }

    /// Alte favorites.json (vor Runde 5, ohne critical/pack) müssen lesbar bleiben – sonst landen sie in Quarantäne.
    @MainActor
    func testLegacyFavoritesSurvive() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("r5-fav-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = """
        [{"en":"Thank you","th":"ขอบคุณ{p}","roman":"khop khun {p}","category":"basics","de":"Danke"},
         {"en":"Hola","th":"Hallo","roman":"","category":"favorites","src":"es","dst":"de"}]
        """
        try Data(legacy.utf8).write(to: dir.appendingPathComponent("favorites.json"))
        let m = InterpreterModel(files: JSONStore(dir: dir))
        XCTAssertEqual(m.favorites.map(\.en), ["Thank you", "Hola"])
        XCTAssertEqual(m.favorites[1].dst, .de)
        XCTAssertNil(m.favorites[0].critical)
        // Neuer Favorit aus einem Paket: Felder werden mitgespeichert und wieder gelesen.
        let pack = try XCTUnwrap(Phrasebook.packs.first { $0.id == "doctor" }?.asPhrases.first)
        m.toggleFavorite(pack)
        let again = InterpreterModel(files: JSONStore(dir: dir))
        XCTAssertEqual(again.favorites.first?.pack, "doctor")
        XCTAssertEqual(again.favorites.first?.isCritical, true)
        XCTAssertEqual(again.favorites.count, 3)
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(left.contains { $0.contains("corrupt") }, "nichts in Quarantäne")
    }
}

final class LeitnerTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return c
    }
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func src(_ s: String) -> LeitnerDeck.Source { .init(front: s, back: "th " + s, lang: .th, roman: nil) }

    func testSyncAddsOnceAndKeepsProgress() {
        var d = LeitnerDeck()
        XCTAssertEqual(d.sync([src("a"), src("b"), src("a")], now: t0), 2)
        d.answer(d.cards[0].id, knew: true, now: t0, calendar: cal)
        XCTAssertEqual(d.sync([src("a"), src("c")], now: t0), 1)
        XCTAssertEqual(d.cards.first { $0.front == "a" }?.box, 2, "Stand bleibt")
        XCTAssertEqual(d.cards.count, 3)
    }

    func testPromoteDemoteAndDueDates() {
        var d = LeitnerDeck()
        d.sync([src("a")], now: t0)
        let id = d.cards[0].id
        XCTAssertEqual(d.due(now: t0).count, 1, "neu = sofort fällig")
        d.answer(id, knew: true, now: t0, calendar: cal)
        XCTAssertEqual(d.cards[0].box, 2)
        XCTAssertEqual(d.cards[0].due, cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: t0)))
        XCTAssertTrue(d.due(now: t0).isEmpty)
        XCTAssertEqual(d.nextDue(after: t0), d.cards[0].due)
        for _ in 0..<10 { d.answer(id, knew: true, now: t0, calendar: cal) }
        XCTAssertEqual(d.cards[0].box, LeitnerDeck.boxes, "höchstens Fach 5")
        XCTAssertEqual(d.cards[0].due, cal.date(byAdding: .day, value: 14, to: cal.startOfDay(for: t0)))
        d.answer(id, knew: false, now: t0, calendar: cal)
        XCTAssertEqual(d.cards[0].box, 1)
        XCTAssertEqual(d.due(now: t0).count, 1, "Nochmal: gleich wieder dran")
        XCTAssertEqual(d.counts, [1, 0, 0, 0, 0])
    }

    func testDueOrderLowestBoxFirst() {
        var d = LeitnerDeck()
        d.sync([src("a"), src("b")], now: t0)
        d.cards[0].box = 3
        let order = d.due(now: t0).map(\.front)
        XCTAssertEqual(order, ["b", "a"])
    }

    func testCodableRoundTrip() throws {
        var d = LeitnerDeck()
        d.sync([src("a")], now: t0)
        let back = try JSONDecoder().decode(LeitnerDeck.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back, d)
    }

    func testSourcesFromEntriesAndFavorites() {
        let pair = LangPair.standard
        let mine = Entry(src: pair.mine, dst: pair.partner, text: "Where is the station?", translation: "สถานีอยู่ที่ไหน")
        let theirs = Entry(src: pair.partner, dst: pair.mine, text: "ตรงไป", translation: "Straight on")
        let failed = Entry(src: pair.mine, dst: pair.partner, text: "x", translation: nil, error: "e")
        XCTAssertEqual(LeitnerDeck.Source.from(mine, pair: pair)?.back, "สถานีอยู่ที่ไหน")
        XCTAssertEqual(LeitnerDeck.Source.from(theirs, pair: pair)?.front, "Straight on")
        XCTAssertEqual(LeitnerDeck.Source.from(theirs, pair: pair)?.back, "ตรงไป")
        XCTAssertNil(LeitnerDeck.Source.from(failed, pair: pair))
        let fav = Phrase(en: "Thank you", th: "ขอบคุณ{p}", roman: "khop khun {p}", category: "basics")
        let s = LeitnerDeck.Source.from(fav, politeness: .female)
        XCTAssertEqual(s.back, "ขอบคุณค่ะ")
        XCTAssertEqual(s.lang, .th)
    }
}

final class PlaceScanTests: XCTestCase {
    func testSplitsThaiFromLatinAndDropsContacts() {
        let lines = ["Riverside Hotel", "โรงแรมริเวอร์ไซด์", "123 ถนนเจริญกรุง บางรัก", "Tel. +66 2 123 4567",
                     "info@riverside.example", "www.riverside.example"]
        let r = PlaceScan.split(lines, local: .th)
        XCTAssertEqual(r.name, "Riverside Hotel")
        XCTAssertEqual(r.local, "โรงแรมริเวอร์ไซด์\n123 ถนนเจริญกรุง บางรัก")
    }

    func testNothingUseful() {
        let r = PlaceScan.split(["  ", "02-123-4567"], local: .th)
        XCTAssertEqual(r.name, "")
        XCTAssertEqual(r.local, "")
    }
}

@MainActor
final class Round5ModelTests: XCTestCase {
    private var dir: URL!
    private var saved: [String: Any] = [:]
    private let keys = ["autoSpeak", "pushToTalk", "liveActivity", "politeness", "mode", "langMine", "langPartner", "historyDays"]

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("r5-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for k in keys { saved[k] = UserDefaults.standard.object(forKey: k) }
    }

    override func tearDown() async throws {
        for k in keys { UserDefaults.standard.set(saved[k], forKey: k) }
        try? FileManager.default.removeItem(at: dir)
    }

    private func model(_ fake: FakeEngine = FakeEngine()) -> InterpreterModel {
        let m = InterpreterModel(files: JSONStore(dir: dir))
        m.pair = .standard
        m.autoSpeak = false
        m.liveActivity = false
        m.pushToTalk = false
        m.politeness = .male
        m.mode = .auto
        m.historyDays = 30
        m.checkModels = false
        m.makeEngine = { fake }
        return m
    }

    private func wait(_ what: String, _ cond: () -> Bool) async {
        for _ in 0..<100 where !cond() { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(cond(), what)
    }

    func testLearnSyncStoresDeck() throws {
        let m = model()
        m.sayBuiltIn("Thank you")
        m.toggleFavorite(Phrase(en: "Hello", th: "สวัสดี{p}", roman: "sa-wat-dee {p}", category: "basics"))
        m.syncLearn()
        XCTAssertEqual(m.learn.cards.count, 2)
        let id = m.learn.cards[0].id
        m.answerCard(id, knew: true)
        let again = model()
        XCTAssertEqual(again.learn.cards.first { $0.id == id }?.box, 2, "lokal gespeichert")
    }

    func testLockedHistoryNotInLearnSources() {
        let m = model()
        m.sayBuiltIn("Thank you")
        m.lockHistory = true
        m.lockNow()
        XCTAssertEqual(m.hiddenCount, 1)
        XCTAssertTrue(m.learnSources.isEmpty)
        m.lockHistory = false
    }

    func testWipeAllRemovesEverything() throws {
        let m = model()
        m.sayBuiltIn("Thank you")
        m.toggleFavorite(Phrase(en: "Hello", th: "สวัสดี{p}", roman: "", category: "basics"))
        m.places = [Place(name: "Hotel", local: "โรงแรม")]
        var e = EmergencyInfo(); e.name = "A"; m.emergency = e
        m.syncLearn()
        try Data("x".utf8).write(to: dir.appendingPathComponent("emergency.json.corrupt-1"))
        m.wipeAll(domain: nil)
        XCTAssertTrue(m.entries.isEmpty && m.favorites.isEmpty && m.places.isEmpty && m.learn.cards.isEmpty)
        XCTAssertEqual(m.emergency.name, "")
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(left, [], "keine Dateien übrig")
        let fresh = model()
        XCTAssertTrue(fresh.entries.isEmpty && fresh.favorites.isEmpty && fresh.places.isEmpty)
    }

    /// 537: Halten einer Hälfte legt die Sprache fest, auch wenn dafür neu gestartet werden muss.
    func testHoldToSpeakPerHalf() async {
        let fake = FakeEngine()
        let m = model(fake)
        m.pushToTalk = true
        m.mode = .mine
        m.start()
        await wait("hört zu") { m.isListening }
        XCTAssertEqual(fake.muted.last, true)
        m.holdToSpeak(m.pair.partner)
        XCTAssertTrue(m.pttHeld, "Halten bleibt nach Neustart bestehen")
        XCTAssertEqual(m.expected, m.pair.partner)
        XCTAssertTrue(m.mode.langs(m.pair).contains(m.pair.partner))
        await wait("hört wieder zu") { m.isListening }
        XCTAssertEqual(fake.muted.last, false, "beim Halten offen")
        m.pttRelease()
        XCTAssertFalse(m.pttHeld)
        XCTAssertGreaterThanOrEqual(fake.flushed, 1)
        m.stop()
    }
}
