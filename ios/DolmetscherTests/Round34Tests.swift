import XCTest
@testable import Dolmetscher

/// Runde 34: die Oberflächen-Anbindung der Runde-33-Bausteine (Entscheidungen, Speicher, Texte, Info.plist).
final class Round34Tests: XCTestCase {
    private let ios = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private func suite() -> UserDefaults {
        let name = "r34-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    // MARK: Texte

    func testEveryRound34KeyIsCompleteRegisteredAndPlaceholdersMatch() {
        let rx = try! NSRegularExpression(pattern: #"%(?:\d\$)?[@df]|%\.\d+f"#)
        func ph(_ s: String) -> [String] { rx.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range, in: s)!]) }.sorted() }
        XCTAssertFalse(L10n.round34.isEmpty)
        for (key, row) in L10n.round34 {
            XCTAssertTrue(L10n.allKeys.contains(key), key)
            for lg in L10n.languages {
                let t = row[lg] ?? ""
                XCTAssertFalse(t.trimmingCharacters(in: .whitespaces).isEmpty, "\(key).\(lg)")
                XCTAssertNotNil(L10n.text(key, lang: lg), "\(key).\(lg)")
                XCTAssertEqual(ph(t), ph(row["en"] ?? ""), "\(key).\(lg) Platzhalter")
            }
        }
        let other = Set(L10n.round33.keys).union(L10n.round32.keys).union(L10n.table.keys)
        XCTAssertTrue(Set(L10n.round34.keys).isDisjoint(with: other), "Schlüssel doppelt")
    }

    func testPlaceTextsExistForEveryChoice() {
        XCTAssertEqual(Set(PlaceChoices.all), Set(PlaceKind.allCases).subtracting([.other]))
        for p in PlaceChoices.all { XCTAssertNotNil(L10n.text(PlaceChoices.textKey(p), lang: "th"), p.rawValue) }
    }

    // MARK: Reise-Modus

    func testTimeZoneMapsToRegionOnlyWhenUnambiguous() {
        XCTAssertEqual(TravelRegion.region(forZone: "Asia/Bangkok"), "TH")
        XCTAssertEqual(TravelRegion.region(forZone: "Europe/Berlin"), "DE")
        XCTAssertNil(TravelRegion.region(forZone: "UTC"))
        XCTAssertNil(TravelRegion.region(forZone: "Etc/GMT+5"))
        // Jede Region der Tabelle kennt der Reise-Modus (Notruf kommt aus der Tabelle, Fallback sonst).
        for (_, r) in TravelRegion.byZone { XCTAssertEqual(r.count, 2) }
    }

    func testTravelSuggestionNeverSwitchesAndShowsOncePerRegion() {
        let pair = LangPair(mine: .de, partner: .en)
        let s = TravelMode.suggest(region: "TH", home: "DE", pair: pair)
        XCTAssertEqual(s?.partner, .th)
        XCTAssertEqual(s?.changesPair, true)
        XCTAssertEqual(pair, LangPair(mine: .de, partner: .en))   // Vorschlag ändert nichts
        XCTAssertNil(TravelMode.suggest(region: "DE", home: "DE", pair: pair))
        XCTAssertTrue(TravelPrompt.shouldShow(s, dismissed: nil, enabled: true))
        XCTAssertTrue(TravelPrompt.shouldShow(s, dismissed: "", enabled: true))
        XCTAssertFalse(TravelPrompt.shouldShow(s, dismissed: "th", enabled: true))   // schon abgelehnt
        XCTAssertTrue(TravelPrompt.shouldShow(s, dismissed: "JP", enabled: true))    // neues Land
        XCTAssertFalse(TravelPrompt.shouldShow(s, dismissed: nil, enabled: false))
        XCTAssertFalse(TravelPrompt.shouldShow(nil, dismissed: nil, enabled: true))
    }

    // MARK: Planer

    func testPlannerRatesPersistsAndForecasts() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var p = PlannerStore()
        p.rate("a", .good, now: now)
        p.rate("b", .again, now: now)
        XCTAssertEqual(p.states.count, 2)
        XCTAssertGreaterThan(p.states["a"]!.stability, p.states["b"]!.stability)
        XCTAssertEqual(p.forecast(now: now.addingTimeInterval(60)).dueNow, 0)   // „nochmal“ ist erst nach 10 Minuten fällig
        let f = p.forecast(now: now.addingTimeInterval(700))
        XCTAssertEqual(f.tracked, 2)
        XCTAssertEqual(f.dueNow, 1)
        // Nach einem Tag: beide fällig oder in der Woche
        let later = p.forecast(now: now.addingTimeInterval(8 * 86_400))
        XCTAssertEqual(later.dueNow, 2)
        XCTAssertTrue((0...100).contains(f.recallPercent))
        // Speicher
        let d = suite()
        p.save(d)
        XCTAssertEqual(PlannerStore.load(d), p)
        XCTAssertEqual(PlannerStore.load(suite()), PlannerStore())
        p.prune(keeping: ["a"])
        XCTAssertEqual(Set(p.states.keys), ["a"])
    }

    func testPlannerForecastWithoutStatesIsEmpty() {
        XCTAssertEqual(PlannerStore().forecast(now: Date()), PlannerStore.Forecast())
    }

    func testCardTopicsComeFromFavoritePhrase() {
        let fav = Phrase(en: "The bill, please", th: "เช็คบิลหน่อย", roman: "check bin", category: "food", pack: "bakery-cafe")
        let id = "fav|" + fav.favoriteKey
        let tags = CardTopics.tags(cardID: id, favorites: [fav])
        XCTAssertTrue(tags.contains("food"))
        XCTAssertTrue(tags.contains("bakery-cafe") && tags.contains("cafe"))
        XCTAssertTrue(CardTopics.tags(cardID: "th|something", favorites: [fav]).isEmpty)   // Gesprächskarte
        XCTAssertTrue(CardTopics.tags(cardID: "fav|unknown", favorites: [fav]).isEmpty)
        // Orts-Auswahl: Restaurant passt zu „food“, Flughafen nicht
        let cards = [id, "x"]
        let at = LocationTrigger.pick(cards, tags: { CardTopics.tags(cardID: $0, favorites: [fav]) }, due: { _ in true }, place: .restaurant)
        XCTAssertEqual(at, [id])
        XCTAssertTrue(LocationTrigger.pick(cards, tags: { CardTopics.tags(cardID: $0, favorites: [fav]) }, due: { _ in true }, place: .airport).isEmpty)
    }

    // MARK: Whisper-Teiltexte

    func testPartialsAreOffByDefault() {
        XCTAssertFalse(WhisperPartials.enabled)
        XCTAssertFalse(suite().bool(forKey: WhisperPartials.key))
    }

    func testPartialGateRules() {
        func go(_ on: Bool = true, utt: Bool = true, secs: Double = 3, since: Double = 2, busy: Bool = false, final: Bool = false) -> Bool {
            WhisperPartials.shouldStart(enabled: on, inUtterance: utt, utteranceSeconds: secs, sinceLast: since, partialBusy: busy, finalPending: final)
        }
        XCTAssertTrue(go())
        XCTAssertFalse(go(false))                  // Schalter aus
        XCTAssertFalse(go(utt: false))             // keine Äußerung
        XCTAssertFalse(go(secs: 0.5))              // zu kurz
        XCTAssertFalse(go(secs: 26))               // fast am Ende: das Endergebnis folgt
        XCTAssertFalse(go(since: 0.5))             // zu bald nach der letzten
        XCTAssertFalse(go(busy: true))             // nur eine Zwischenerkennung
        XCTAssertFalse(go(final: true))            // Endergebnis hat Vorrang
    }

    func testPartialLanguageFollowsLastOrFirst() {
        XCTAssertEqual(WhisperPartials.language(last: .th, langs: [.en, .th]), .th)
        XCTAssertEqual(WhisperPartials.language(last: .de, langs: [.en, .th]), .en)
        XCTAssertEqual(WhisperPartials.language(last: nil, langs: [.en, .th]), .en)
        XCTAssertNil(WhisperPartials.language(last: nil, langs: []))
    }

    func testPartialStateIgnoresLateResultsOfAnEndedUtterance() {
        let s = PartialState()
        s.reset()
        let g = s.begin()
        XCTAssertTrue(s.busy)
        XCTAssertNil(s.feed(gen: g, raw: "hello world today", duration: 3, rms: 0.05))        // erst ein Durchlauf
        XCTAssertEqual(s.feed(gen: g, raw: "hello world today", duration: 3, rms: 0.05), "hello world today")
        s.end(g)
        XCTAssertFalse(s.busy)
        s.invalidate()   // Äußerung zu Ende: Endergebnis folgt
        XCTAssertNil(s.feed(gen: g, raw: "hello world today and more", duration: 3, rms: 0.05))
        s.finalStarted(); XCTAssertTrue(s.finalRunning); s.finalEnded(); XCTAssertFalse(s.finalRunning)
        s.lastLang = .th; XCTAssertEqual(s.lastLang, .th)
    }

    // MARK: Speisekarte

    func testMenuHitsAreMappedToLinesAndNamedInUILanguage() {
        let lines = ["Pad Thai with peanuts", "Green curry", "ผัดไทยกุ้ง", "Fish sauce soup"]
        let avoid = MenuScan.avoidIDs([.peanut, .shellfish])
        let hits = MenuScan.hitsByLine(lines, avoid: avoid)
        XCTAssertEqual(Set(hits.keys), [0, 2])
        XCTAssertEqual(hits[0]?.ids, ["peanut"])
        XCTAssertEqual(hits[2]?.ids, ["shellfish"])
        XCTAssertEqual(MenuScan.names(["peanut"], in: .de), "Erdnüsse")
        XCTAssertEqual(MenuScan.names(["gluten", "wheat"], in: .en), "wheat (gluten)")   // keine Dopplung
        XCTAssertTrue(MenuScan.hitsByLine(lines, avoid: []).isEmpty)
    }

    func testMenuIdenticalLinesAreAllMarked() {
        let lines = ["Egg noodles", "Rice", "Egg noodles"]
        XCTAssertEqual(Set(MenuScan.hitsByLine(lines, avoid: ["egg"]).keys), [0, 2])
    }

    // MARK: Hotelkarte

    func testHotelCardOutcomes() {
        XCTAssertEqual(HotelCard.outcome(hotel: "", phone: ""), .empty)
        XCTAssertEqual(HotelCard.outcome(hotel: "  \n ", phone: ""), .empty)
        let h = HotelCard.split("Hotel Siam\n12 Sukhumvit Rd\nBangkok")
        XCTAssertEqual(h.name, "Hotel Siam")
        XCTAssertEqual(h.address, "12 Sukhumvit Rd, Bangkok")
        guard case .ready(let text) = HotelCard.outcome(hotel: "Hotel Siam\n12 Sukhumvit Rd", phone: "+66 2 123 4567") else { return XCTFail() }
        XCTAssertTrue(text.contains("FN:Hotel Siam"))
        XCTAssertTrue(text.contains("TEL;TYPE=WORK:+6621234567"))
        XCTAssertNotNil(QRImage.make(text))
        XCTAssertEqual(HotelCard.outcome(hotel: "H\n" + String(repeating: "x", count: 2000), phone: ""), .tooLong)
    }

    // MARK: Zwei Geräte

    func testPeerDisplayNameIsShortAndDistinct() {
        let n = PeerLink.displayName(device: String(repeating: "é", count: 80), suffix: "ab12")
        XCTAssertLessThanOrEqual(n.utf8.count, 63)
        XCTAssertTrue(n.hasSuffix("ab12"))
        XCTAssertNotEqual(PeerLink.displayName(device: "iPhone"), PeerLink.displayName(device: "iPhone"))
    }

    @MainActor func testPairSessionSendsOnlyWhenConnectedAndShowsNoHistory() {
        let s = PairSession()
        s.send("Hallo", lang: .de)
        XCTAssertTrue(s.lines.isEmpty)          // nicht verbunden: nichts wird gespeichert oder gesendet
        XCTAssertFalse(s.running)
        s.stop()
        XCTAssertEqual(s.state.phase, .idle)
    }

    func testNewSheetsExist() {
        XCTAssertEqual(AppSheet(rawValue: "menuScan"), .menuScan)
        XCTAssertEqual(AppSheet(rawValue: "diary"), .diary)
        XCTAssertEqual(AppSheet(rawValue: "hotelCard"), .hotelCard)
        XCTAssertEqual(AppSheet(rawValue: "twoDevice"), .twoDevice)
    }

    // MARK: Ampel

    func testLightFollowsPartnerVoiceAndReport() {
        let inputs = OfflineInputs(mine: .en, partner: .th, recognizerMine: .installed, recognizerPartner: .installed, translation: .installed,
                                   voiceMine: true, voicePartner: true)
        let r = OfflineReport.evaluate(inputs)
        XCTAssertEqual(ReadinessLight.evaluate(r, partnerVoice: .premium), .green)
        XCTAssertEqual(ReadinessLight.evaluate(r, partnerVoice: .compact), .yellow)
        XCTAssertEqual(ReadinessLight.evaluate(r, partnerVoice: .none), .red)
        var missing = inputs; missing.translation = .downloadable
        XCTAssertEqual(ReadinessLight.evaluate(OfflineReport.evaluate(missing), partnerVoice: .premium), .red)
        XCTAssertFalse(OfflineReport.evaluate(missing).loadable.isEmpty)   // „Alles laden“ hat etwas zu tun
    }

    // MARK: Info.plist

    func testInfoPlistDeclaresLocalNetworkAndBonjour() throws {
        let data = try Data(contentsOf: ios.appendingPathComponent("Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let project = try String(contentsOf: ios.appendingPathComponent("Dolmetscher.xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertTrue(project.contains("INFOPLIST_KEY_NSLocalNetworkUsageDescription"))
        let services = plist?["NSBonjourServices"] as? [String] ?? []
        XCTAssertTrue(services.contains("_\(PeerLink.serviceType)._tcp"))
        XCTAssertTrue(services.contains("_\(PeerLink.serviceType)._udp"))
        for lg in ["de", "es", "fr", "id", "ja", "ko", "th", "vi", "zh-Hans"] {
            let s = try String(contentsOf: ios.appendingPathComponent("Dolmetscher/\(lg).lproj/InfoPlist.strings"), encoding: .utf8)
            XCTAssertTrue(s.contains("NSLocalNetworkUsageDescription"), lg)
        }
    }
}
