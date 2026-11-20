import XCTest
@testable import Dolmetscher

final class Round33Tests: XCTestCase {
    // MARK: HFP-Hinweis in L10n

    func testHfpWarningComesFromL10nInEveryLanguage() {
        for lg in ["de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id"] {
            XCTAssertEqual(SessionTuning.warnText(lang: lg), L10n.text("r33_hfp_warn", lang: lg), lg)
            XCTAssertFalse(SessionTuning.warnText(lang: lg).isEmpty)
        }
        XCTAssertTrue(SessionTuning.warnText(lang: "th").contains("บลูทูธ"))
        XCTAssertEqual(SessionTuning.warnText(lang: "xx"), L10n.text("r33_hfp_warn", lang: "en"))
    }

    func testEveryRound33KeyIsCompleteAndRegistered() {
        for (key, row) in L10n.round33 {
            XCTAssertTrue(L10n.allKeys.contains(key), key)
            for lg in ["de", "en", "th", "es", "fr", "ja", "ko", "zh-Hans", "vi", "id"] {
                XCTAssertFalse((row[lg] ?? "").trimmingCharacters(in: .whitespaces).isEmpty, "\(key).\(lg)")
                XCTAssertNotNil(L10n.text(key, lang: lg), "\(key).\(lg)")
            }
        }
    }

    // MARK: Streaming-Teiltexte

    func testPartialShowsOnlyTheStablePrefix() {
        var s = PartialStabilizer()
        XCTAssertNil(s.feed("I would like", duration: 2))
        XCTAssertEqual(s.feed("I would like a coffee", duration: 3), "I would like")
        XCTAssertEqual(s.feed("I would like a coffee please", duration: 4), "I would like a coffee")
        XCTAssertEqual(s.feed("I would like a coffee please", duration: 4), "I would like a coffee please")   // zweimal gleich: stabil
        XCTAssertNil(s.feed("I would like a coffee please", duration: 4))   // nichts Neues: kein erneutes Anzeigen
    }

    func testPartialNeverCutsInsideAWord() {
        var s = PartialStabilizer()
        _ = s.feed("where is the stat", duration: 2)
        XCTAssertEqual(s.feed("where is the station", duration: 3), "where is the")
        XCTAssertEqual(PartialStabilizer.commonPrefix(["hello wor", "hello world"]), "hello")
        XCTAssertEqual(PartialStabilizer.commonPrefix(["abc", "xyz"]), "")
    }

    func testPartialDropsHallucinationsAndPunctuationNoise() {
        var s = PartialStabilizer()
        XCTAssertNil(s.feed(">>", duration: 1))
        XCTAssertNil(s.feed(String(repeating: "abcdefg ", count: 6), duration: 0.2))   // viel zu schnell
        XCTAssertTrue(s.history.isEmpty)
    }

    func testPartialThaiUsesCharacterBoundaryAndFinalAlwaysWins() {
        var s = PartialStabilizer()
        XCTAssertNil(s.feed("สวัสดีครับ", duration: 1.5))
        XCTAssertEqual(s.feed("สวัสดีครับผม", duration: 2), "สวัสดีครับ")
        XCTAssertEqual(s.finish("สวัสดีครับ ยินดีที่ได้รู้จัก"), "สวัสดีครับ ยินดีที่ได้รู้จัก")
        XCTAssertTrue(s.history.isEmpty)
        XCTAssertEqual(s.shown, "")
    }

    // MARK: Speisekarten-Allergene

    func testEggplantIsNotEgg() {
        XCTAssertTrue(MenuAllergens.scan(lines: ["Grilled eggplant"], avoid: ["egg"]).isEmpty)
        XCTAssertEqual(MenuAllergens.scan(lines: ["Fried egg with rice", "Pad Thai"], avoid: ["egg"]).map(\.line), ["Fried egg with rice"])
        XCTAssertEqual(MenuAllergens.scan(lines: ["Peanut sauce", "Erdnussbutter"], avoid: ["peanut"]).count, 2)
    }

    func testThaiSnackIsNotMilkButMilkIs() {
        XCTAssertTrue(MenuAllergens.scan(lines: ["ขนมหวาน"], avoid: ["milk"]).isEmpty)
        XCTAssertEqual(MenuAllergens.scan(lines: ["นมสด", "ชาไทยใส่นม"], avoid: ["milk"]).count, 2)
    }

    func testSquidIsNotFishButFishSauceIs() {
        XCTAssertTrue(MenuAllergens.scan(lines: ["ปลาหมึกผัดไข่เค็ม"], avoid: ["fish"]).isEmpty)
        XCTAssertEqual(MenuAllergens.scan(lines: ["ผัดกะเพรา น้ำปลา"], avoid: ["fish", "fishsauce"]).first?.ids, ["fish", "fishsauce"])
        XCTAssertEqual(MenuAllergens.scan(lines: ["ปลาหมึกผัด"], avoid: ["mollusc"]).count, 1)
    }

    func testBareThaiBeanIsOnlyMaybePeanut() {
        let bean = MenuAllergens.scan(lines: ["ผัดถั่ว"], avoid: ["peanut"])
        XCTAssertEqual(bean.first?.ids, [])
        XCTAssertEqual(bean.first?.maybe, ["peanut"])
        XCTAssertTrue(MenuAllergens.scan(lines: ["ถั่วงอก ถั่วฝักยาว"], avoid: ["peanut"]).isEmpty)
        XCTAssertEqual(MenuAllergens.scan(lines: ["ซอสถั่วลิสง"], avoid: ["peanut"]).first?.ids, ["peanut"])
    }

    func testMenuScanWithoutAvoidListAndSesameWordFalsePositive() {
        XCTAssertTrue(MenuAllergens.scan(lines: ["Fried egg"], avoid: []).isEmpty)
        XCTAssertTrue(MenuAllergens.scan(lines: ["งานเลี้ยง"], avoid: ["sesame"]).isEmpty)
        XCTAssertEqual(MenuAllergens.scan(lines: ["น้ำมันงา"], avoid: ["sesame"]).count, 1)
    }

    func testAllergenCardMapsToAllergenIds() {
        XCTAssertEqual(MenuAllergens.ids(from: [.peanut, .gluten]), ["peanut", "gluten", "wheat"])
        for a in Allergen.allCases { XCTAssertFalse(MenuAllergens.ids(from: [a]).isEmpty) }
    }

    // MARK: Reise-Modus

    func testTravelSuggestsPartnerEmergencyAndCurrency() throws {
        let s = try XCTUnwrap(TravelMode.suggest(region: "th", home: "DE", pair: LangPair(mine: .de, partner: .en)))
        XCTAssertEqual(s.partner, .th)
        XCTAssertTrue(s.changesPair)
        XCTAssertEqual(s.emergency.ambulance, "1669")
        XCTAssertEqual(s.currency, "THB")
    }

    func testTravelNeverSuggestsAtHomeOrForSamePair() {
        XCTAssertNil(TravelMode.suggest(region: "DE", home: "de", pair: .standard))
        XCTAssertNil(TravelMode.suggest(region: nil, home: "DE", pair: .standard))
        XCTAssertNil(TravelMode.suggest(region: "THA", home: "DE", pair: .standard))
        XCTAssertEqual(TravelMode.suggest(region: "TH", home: "DE", pair: .standard)?.changesPair, false)
        let unknown = TravelMode.suggest(region: "ZZ", home: "DE", pair: .standard)
        XCTAssertNil(unknown?.partner)
        XCTAssertEqual(unknown?.emergency.ambulance, "112")
    }

    // MARK: Zwei-Geräte-Modus

    func testPeerMessageRoundTripAndLimits() throws {
        let m = PeerMessage.text("Hello", lang: .en, id: "1")
        XCTAssertEqual(PeerMessage.decode(try XCTUnwrap(m.encode())), m)
        XCTAssertNil(PeerMessage.text(String(repeating: "x", count: 5000), lang: .en).encode())
        XCTAssertNil(PeerMessage.decode(Data("nope".utf8)))
        XCTAssertNil(PeerMessage.decode(Data(#"{"v":9,"kind":"text","id":"1","lang":"en","text":"x"}"#.utf8)))
    }

    func testPeerStateDedupesAndNeedsConnection() {
        var p = PeerState()
        let m = PeerMessage.text("Hi", lang: .th, id: "a")
        XCTAssertFalse(p.accept(m))
        p.startSearch()
        XCTAssertEqual(p.phase, .searching)
        p.connected("iPhone")
        XCTAssertTrue(p.accept(m))
        XCTAssertFalse(p.accept(m))
        XCTAssertFalse(p.accept(PeerMessage(kind: .ack, id: "b", lang: "en", text: "")))
        p.lost()
        XCTAssertEqual(p.phase, .idle)
    }

    func testPeerStateMemoryIsBounded() {
        var p = PeerState()
        p.connected("x")
        for i in 0..<(PeerState.memory + 20) { _ = p.accept(PeerMessage.text("t", lang: .en, id: "\(i)")) }
        XCTAssertEqual(p.seen.count, PeerState.memory)
    }

    // MARK: Aussprache-Coach

    func testPronunciationScores() {
        XCTAssertEqual(PronunciationCoach.score(expected: "Where is the station?", heard: "where is the station").score, 100)
        XCTAssertEqual(PronunciationCoach.score(expected: "Where is the station", heard: "where is the station").verdict, .good)
        let close = PronunciationCoach.score(expected: "Where is the station", heard: "where is station")
        XCTAssertEqual(close.missing, ["the"])
        XCTAssertNotEqual(close.verdict, .retry)
        XCTAssertEqual(PronunciationCoach.score(expected: "Where is the station", heard: "banana").verdict, .retry)
        XCTAssertEqual(PronunciationCoach.score(expected: "", heard: "x").score, 0)
    }

    func testPronunciationThaiAndAccents() {
        XCTAssertEqual(PronunciationCoach.score(expected: "สวัสดีครับ", heard: "สวัสดีครับ").score, 100)
        let t = PronunciationCoach.score(expected: "สวัสดีครับ", heard: "สวัสดีค่ะ")
        XCTAssertTrue(t.score < 100 && t.score > 40, "\(t.score)")
        XCTAssertEqual(PronunciationCoach.score(expected: "Café", heard: "cafe").score, 100)
        XCTAssertEqual(PronunciationCoach.distance(Array("kitten"), Array("sitting")), 3)
    }

    // MARK: Wiederholungs-Planer

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testFirstReviewOrderedByRating() {
        let iv = { (r: SpacedRepetition.Rating) in SpacedRepetition.review(SpacedRepetition.fresh(now: self.t0), r, now: self.t0).due.timeIntervalSince(self.t0) }
        XCTAssertTrue(iv(.again) < iv(.hard) && iv(.hard) < iv(.good) && iv(.good) < iv(.easy))
        XCTAssertLessThan(iv(.again), 3600)
    }

    func testGoodAnswersGrowTheInterval() {
        var s = SpacedRepetition.review(SpacedRepetition.fresh(now: t0), .good, now: t0)
        var last = s.due.timeIntervalSince(t0)
        var now = s.due
        for _ in 0..<4 {
            s = SpacedRepetition.review(s, .good, now: now)
            let iv = s.due.timeIntervalSince(now)
            XCTAssertGreaterThan(iv, last)
            last = iv; now = s.due
        }
        XCTAssertEqual(s.reps, 5)
        XCTAssertLessThanOrEqual(last, SpacedRepetition.maxInterval * 86_400)
    }

    func testLapseShrinksStabilityAndDueSoon() {
        let a = SpacedRepetition.review(SpacedRepetition.fresh(now: t0), .good, now: t0)
        let b = SpacedRepetition.review(a, .good, now: a.due)
        let c = SpacedRepetition.review(b, .again, now: b.due)
        XCTAssertEqual(c.lapses, 1)
        XCTAssertLessThan(c.stability, b.stability)
        XCTAssertLessThan(c.due.timeIntervalSince(b.due), 3600)
        XCTAssertTrue(SpacedRepetition.isDue(c, now: b.due.addingTimeInterval(700)))
        XCTAssertFalse(SpacedRepetition.isDue(a, now: t0))
    }

    func testRetrievabilityCurveAndClamps() {
        XCTAssertEqual(SpacedRepetition.retrievability(days: 0, stability: 5), 1, accuracy: 1e-9)
        XCTAssertEqual(SpacedRepetition.retrievability(days: 45, stability: 5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(SpacedRepetition.retrievability(days: 3, stability: 0), 0)
        XCTAssertEqual(SpacedRepetition.interval(stability: 10_000), SpacedRepetition.maxInterval)
        var s = SpacedRepetition.fresh(now: t0)
        for _ in 0..<30 { s = SpacedRepetition.review(s, .again, now: t0) }
        XCTAssertLessThanOrEqual(s.difficulty, 10)
        XCTAssertGreaterThanOrEqual(s.stability, 0.3)
    }

    // MARK: Standort-Auslöser

    func testPlaceKindFromMapCategory() {
        XCTAssertEqual(PlaceKind.from(category: "MKPOICategoryAirport"), .airport)
        XCTAssertEqual(PlaceKind.from(category: "MKPOICategoryRestaurant"), .restaurant)
        XCTAssertEqual(PlaceKind.from(category: "MKPOICategoryHospital"), .hospital)
        XCTAssertEqual(PlaceKind.from(category: "MKPOICategoryFoodMarket"), .market)
        XCTAssertEqual(PlaceKind.from(category: "MKPOICategoryPark"), .other)
    }

    func testLocationTriggerPicksDueCardsForThePlaceOnly() {
        struct C { var id: Int; var tags: Set<String>; var due: Bool }
        let cards = [C(id: 1, tags: ["food"], due: true), C(id: 2, tags: ["transport"], due: true), C(id: 3, tags: ["food"], due: false),
                     C(id: 4, tags: ["restaurant"], due: true), C(id: 5, tags: ["food"], due: true)]
        let r = LocationTrigger.pick(cards, tags: \.tags, due: \.due, place: .restaurant, limit: 2)
        XCTAssertEqual(r.map(\.id), [1, 4])
        XCTAssertTrue(LocationTrigger.pick(cards, tags: \.tags, due: \.due, place: .other).isEmpty)
    }

    // MARK: Reise-Tagebuch

    private func entry(_ day: Int, _ provider: String?, error: String? = nil, text: String = "x") -> Entry {
        var e = Entry(src: .en, dst: .th, text: text, translation: "y", provider: provider)
        e.date = Date(timeIntervalSince1970: 1_800_000_000 + Double(day) * 86_400)
        e.error = error
        return e
    }

    func testDiarySummary() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let list = [entry(0, "apple"), entry(0, "apple"), entry(1, "google"), entry(3, "phrasebook"), entry(3, "apple", error: "boom"), entry(4, "apple", text: "  ")]
        let s = TravelDiary.summarize(list, calendar: cal)
        XCTAssertEqual(s.turns, 4)
        XCTAssertEqual(s.days, 3)
        XCTAssertEqual(s.longestStreak, 2)
        XCTAssertEqual(s.offlinePercent, 75)
        XCTAssertEqual(s.perLang["en"], 4)
        XCTAssertEqual(s.busiest, cal.startOfDay(for: list[0].date))
        XCTAssertEqual(TravelDiary.summarize([]), TravelDiary.Summary())
    }

    // MARK: Hotelkarte (QR)

    func testHotelQRPayload() throws {
        let p = try XCTUnwrap(HotelCardQR.payload(name: "Hotel, Bangkok", address: "1 Sukhumvit; Soi 5", phone: "+66 2 123-4567"))
        XCTAssertTrue(p.hasPrefix("BEGIN:VCARD") && p.hasSuffix("END:VCARD"))
        XCTAssertTrue(p.contains("FN:Hotel\\, Bangkok"))
        XCTAssertTrue(p.contains("1 Sukhumvit\\; Soi 5"))
        XCTAssertTrue(p.contains("TEL;TYPE=WORK:+6621234567"))
        XCTAssertNil(HotelCardQR.payload(name: "  ", address: "x"))
        XCTAssertNil(HotelCardQR.payload(name: "H", address: String(repeating: "a", count: 2000)))
        XCTAssertFalse(HotelCardQR.payload(name: "H", address: "")!.contains("ADR"))
    }

    func testQRImageIsRenderedForPayloadOnly() throws {
        let p = try XCTUnwrap(HotelCardQR.payload(name: "Hotel", address: "Bangkok"))
        let img = try XCTUnwrap(QRImage.make(p))
        XCTAssertGreaterThan(img.size.width, 50)
        XCTAssertNil(QRImage.make(""))
    }

    // MARK: Uhr

    func testWatchPhraseCodec() throws {
        let w = WatchPhrase(text: "Hello", translation: "สวัสดี", lang: "th", roman: "sa-wat-dee")
        let d = try XCTUnwrap(w.encode())
        XCTAssertNoThrow(try PropertyListSerialization.data(fromPropertyList: d, format: .binary, options: 0))   // WatchConnectivity verlangt eine Property List
        XCTAssertEqual(WatchPhrase.decode(d), w)
        var bad = d; bad["v"] = 2
        XCTAssertNil(WatchPhrase.decode(bad))
        XCTAssertNil(WatchPhrase.decode(["v": 1, "text": "x"]))
        XCTAssertNil(WatchPhrase(text: String(repeating: "x", count: 401), translation: "y", lang: "th").encode())
        XCTAssertFalse(WatchBridge.available)   // kein gekoppelte Uhr im Simulator, kein Absturz
    }

    // MARK: Spotlight

    func testSpotlightIsOptInAndNeverWhileLocked() {
        XCTAssertFalse(SpotlightPlan.shouldIndex(enabled: false, locked: false))
        XCTAssertFalse(SpotlightPlan.shouldIndex(enabled: true, locked: true))
        XCTAssertTrue(SpotlightPlan.shouldIndex(enabled: true, locked: false))
        XCTAssertFalse(HistorySpotlight.enabled)   // Standard aus
    }

    func testSpotlightItemsNewestFirstLimitedAndFiltered() {
        var list = (0..<250).map { entry($0, "apple", text: "t\($0)") }
        list.append(entry(300, "card", text: "card"))
        list.append(entry(301, "apple", error: "e", text: "bad"))
        var photo = entry(302, "apple", text: "menu"); photo.photo = true
        list.append(photo)
        let items = SpotlightPlan.items(list)
        XCTAssertEqual(items.count, SpotlightPlan.limit)
        XCTAssertEqual(items.first?.title, "t249")
        XCTAssertFalse(items.contains { ["card", "bad", "menu"].contains($0.title) })
        XCTAssertEqual(items.first?.content, "y")
    }

    // MARK: Bereitschafts-Ampel

    private func inputs(translation: Readiness = .installed, voiceMine: Bool = true, voicePartner: Bool = true) -> OfflineInputs {
        OfflineInputs(mine: .de, partner: .th, recognizerMine: .installed, recognizerPartner: .installed, translation: translation,
                      voiceMine: voiceMine, voicePartner: voicePartner)
    }

    func testTrafficLightIncludesVoiceQuality() {
        let r = OfflineReport.evaluate(inputs())
        XCTAssertEqual(ReadinessLight.evaluate(r, partnerVoice: .premium), .green)
        XCTAssertEqual(ReadinessLight.evaluate(r, partnerVoice: .enhanced), .green)
        XCTAssertEqual(ReadinessLight.evaluate(r, partnerVoice: .compact), .yellow)
        XCTAssertEqual(ReadinessLight.evaluate(r, partnerVoice: .none), .red)
    }

    func testTrafficLightRedWhenEssentialsMissingYellowWhenOnlyMyVoiceIs() {
        XCTAssertEqual(ReadinessLight.evaluate(OfflineReport.evaluate(inputs(translation: .downloadable)), partnerVoice: .premium), .red)
        XCTAssertEqual(ReadinessLight.evaluate(OfflineReport.evaluate(inputs(translation: .unsupported)), partnerVoice: .premium), .red)
        XCTAssertEqual(ReadinessLight.evaluate(OfflineReport.evaluate(inputs(voiceMine: false)), partnerVoice: .premium), .yellow)
        XCTAssertEqual(ReadinessLight.green.textKey, "r33_light_green")
        XCTAssertNotNil(L10n.text(ReadinessLight.red.textKey, lang: "de"))
        XCTAssertTrue(VoiceQuality.premium > VoiceQuality.enhanced && VoiceQuality.compact > VoiceQuality.none)
        _ = VoiceCheck.quality(for: .en)   // Systemabfrage läuft ohne Absturz
    }

    // MARK: Backup-Ausschluss und Dateischutz

    func testFilePolicyDecisions() {
        XCTAssertEqual(FileGuard.policy(forFileNamed: "history.json"), FileGuard.Policy(excludeFromBackup: true, protection: .untilFirstUnlock))
        XCTAssertEqual(FileGuard.policy(forFileNamed: "emergency.json").protection, .complete)
        XCTAssertEqual(FileGuard.policy(forFileNamed: "medical-card.json").protection, .complete)
        XCTAssertFalse(FileGuard.policy(forFileNamed: "export-2026.csv").excludeFromBackup)
        XCTAssertTrue(FileGuard.policy(forFileNamed: "learn.json").excludeFromBackup)
    }

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("r33-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testBackupExclusionRoundTrip() throws {
        let dir = tempDir()
        let h = dir.appendingPathComponent("history.json"), e = dir.appendingPathComponent("export.csv")
        try Data("[]".utf8).write(to: h); try Data("a,b".utf8).write(to: e)
        FileGuardApply.apply(h); FileGuardApply.apply(e)
        XCTAssertEqual(try h.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertEqual(try e.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, false)
    }

    func testJSONStoreKeepsDataOutOfTheBackupAfterEveryWrite() throws {
        let dir = tempDir()
        let s = JSONStore(dir: dir)
        XCTAssertTrue(s.store(["a": 1], "history.json"))
        XCTAssertTrue(s.store(["a": 2], "history.json"))   // `.atomic` ersetzt die Datei: Merkmal muss erneut gesetzt sein
        XCTAssertEqual(try s.url("history.json").resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    // MARK: Umweg über Englisch

    func testPivotLabelAndProvider() {
        XCTAssertTrue(PivotLabel.isPivot("apple-pivot"))
        XCTAssertFalse(PivotLabel.isPivot("apple"))
        XCTAssertEqual(PivotLabel.route(src: .th, dst: .de), "th → en → de")
        XCTAssertEqual(PivotLabel.provider, "apple-pivot")
        XCTAssertEqual(L10n.text("r33_pivot_via", lang: "de"), "über Englisch")
        var e = entry(0, PivotLabel.provider)
        e.error = nil
        XCTAssertEqual(TravelDiary.summarize([e]).offlinePercent, 100)   // Umweg zählt als offline
    }
}
