import XCTest
@testable import Dolmetscher

/// Runde 35: neue Logik-Bausteine und zusätzliche Tests für die Logik der Runden 32 bis 34.
final class Round35Tests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Barrierefreiheit

    func testBubbleLabel() {
        XCTAssertEqual(R35Accessibility.bubbleLabel(speaker: "Ich", text: " Hallo \n", time: "14:05"), "Ich, 14:05: Hallo")
        XCTAssertEqual(R35Accessibility.bubbleLabel(speaker: "Ich", text: "Hi", time: nil), "Ich: Hi")
        XCTAssertEqual(R35Accessibility.bubbleLabel(speaker: "Ich", text: "  ", time: ""), "Ich")
    }

    func testConfidenceLevels() {
        XCTAssertEqual(R35Accessibility.confidence(0.1), .low)
        XCTAssertEqual(R35Accessibility.confidence(0.5), .medium)
        XCTAssertEqual(R35Accessibility.confidence(0.79), .medium)
        XCTAssertEqual(R35Accessibility.confidence(0.8), .high)
        XCTAssertEqual(R35Accessibility.confidence(1.5), .high)
        XCTAssertEqual(R35Accessibility.confidence(Double.nan), .low)
    }

    func testClampedSizeAndMotion() {
        XCTAssertEqual(R35Accessibility.clampedSize(base: 17, scale: 2, minimum: 12, maximum: 28), 28)
        XCTAssertEqual(R35Accessibility.clampedSize(base: 17, scale: 0.5, minimum: 12, maximum: 28), 12)
        XCTAssertEqual(R35Accessibility.clampedSize(base: 10, scale: 0, minimum: 5, maximum: 20), 10)   // ungültiger Faktor = 1
        XCTAssertEqual(R35Accessibility.clampedSize(base: 10, scale: 1, minimum: 20, maximum: 5), 10)   // vertauschte Grenzen
        XCTAssertEqual(R35Accessibility.animationDuration(0.3, reduceMotion: true), 0)
        XCTAssertEqual(R35Accessibility.animationDuration(0.3, reduceMotion: false), 0.3)
        XCTAssertEqual(R35Accessibility.animationDuration(-1, reduceMotion: false), 0)
    }

    // MARK: Offline-Warteschlange, Fehler, Wiederholung

    func testRetryQueueBoundedDedupedFifo() {
        var q = R35RetryQueue(limit: 3)
        XCTAssertFalse(q.add("   "))
        XCTAssertTrue(q.add("a")); q.add("b"); q.add("c")
        q.add(" a ")                       // Dopplung: rückt nach hinten
        XCTAssertEqual(q.items, ["b", "c", "a"])
        q.add("d")                         // voll: ältester fällt weg
        XCTAssertEqual(q.items, ["c", "a", "d"])
        XCTAssertEqual(q.next(), "c")
        XCTAssertEqual(q.count, 2)
        XCTAssertEqual(R35RetryQueue(limit: 0).limit, 1)
    }

    func testRetryQueueCodableRoundTrip() throws {
        var q = R35RetryQueue(limit: 5)
        q.add("สวัสดี"); q.add("Hallo")
        let data = try JSONEncoder().encode(q)
        XCTAssertEqual(try JSONDecoder().decode(R35RetryQueue.self, from: data), q)
    }

    func testErrorClassification() {
        XCTAssertEqual(R35ErrorKind.classify(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet), .offline)
        XCTAssertEqual(R35ErrorKind.classify(domain: NSURLErrorDomain, code: NSURLErrorTimedOut), .timeout)
        XCTAssertEqual(R35ErrorKind.classify(domain: NSURLErrorDomain, code: NSURLErrorCancelled), .cancelled)
        XCTAssertEqual(R35ErrorKind.classify(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted), .tls)
        XCTAssertEqual(R35ErrorKind.classify(domain: "http", code: 401), .auth)
        XCTAssertEqual(R35ErrorKind.classify(domain: "http", code: 429), .quota)
        XCTAssertEqual(R35ErrorKind.classify(domain: "http", code: 503), .server)
        XCTAssertEqual(R35ErrorKind.classify(domain: "http", code: 404), .unknown)
        XCTAssertEqual(R35ErrorKind.classify(domain: "Other", code: 1), .unknown)
        let e = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        XCTAssertEqual(R35ErrorKind.classify(e), .timeout)
    }

    func testRetryRules() {
        XCTAssertTrue(R35ErrorKind.offline.isRetryable)
        XCTAssertFalse(R35ErrorKind.auth.isRetryable)
        XCTAssertFalse(R35ErrorKind.quota.isRetryable)
        XCTAssertFalse(R35ErrorKind.cancelled.isRetryable)
        XCTAssertTrue(R35Backoff.shouldRetry(.server, attempt: 2))
        XCTAssertFalse(R35Backoff.shouldRetry(.server, attempt: 3))
        XCTAssertFalse(R35Backoff.shouldRetry(.tls, attempt: 0))
        XCTAssertEqual(R35Backoff.delay(attempt: 0), 1)
        XCTAssertEqual(R35Backoff.delay(attempt: 3), 8)
        XCTAssertEqual(R35Backoff.delay(attempt: 10), 30)    // gedeckelt
        XCTAssertEqual(R35Backoff.delay(attempt: -4), 1)
        XCTAssertEqual(R35Backoff.delay(attempt: 500), 30)   // kein Überlauf
    }

    // MARK: Speicher

    func testStorageVerdictAndFormat() {
        XCTAssertEqual(R35Storage.verdict(freeBytes: 100, requiredBytes: 200), .critical)
        XCTAssertEqual(R35Storage.verdict(freeBytes: 210, requiredBytes: 200), .low)
        XCTAssertEqual(R35Storage.verdict(freeBytes: 240, requiredBytes: 200), .ok)
        XCTAssertEqual(R35Storage.verdict(freeBytes: 0, requiredBytes: 0), .ok)
        XCTAssertEqual(R35Storage.format(0), "0 B")
        XCTAssertEqual(R35Storage.format(950), "950 B")
        XCTAssertEqual(R35Storage.format(950_000), "950 KB")
        XCTAssertEqual(R35Storage.format(1_400_000_000), "1.4 GB")
        XCTAssertEqual(R35Storage.format(12_340_000), "12.3 MB")
        XCTAssertEqual(R35Storage.format(-5), "0 B")
    }

    // MARK: Zeit

    func testClockFormats() {
        XCTAssertEqual(R35Clock.format(seconds: 0), "00:00")
        XCTAssertEqual(R35Clock.format(seconds: 123), "02:03")
        XCTAssertEqual(R35Clock.format(seconds: 3723), "1:02:03")
        XCTAssertEqual(R35Clock.format(seconds: -9), "00:00")
        XCTAssertEqual(R35Clock.spoken(seconds: 3723, lang: "de"), "1 Stunde 2 Minuten")
        XCTAssertEqual(R35Clock.spoken(seconds: 7260, lang: "en"), "2 hours 1 minute")
        XCTAssertEqual(R35Clock.spoken(seconds: 45, lang: "en"), "45 seconds")
        XCTAssertEqual(R35Clock.spoken(seconds: 1, lang: "de"), "1 Sekunde")
        XCTAssertEqual(R35Clock.spoken(seconds: 5, lang: "th"), "5 seconds")   // Rückfall auf Englisch
    }

    func testQuietHoursWrapMidnight() {
        XCTAssertTrue(R35Clock.isQuiet(hour: 23, start: 22, end: 7))
        XCTAssertTrue(R35Clock.isQuiet(hour: 3, start: 22, end: 7))
        XCTAssertFalse(R35Clock.isQuiet(hour: 7, start: 22, end: 7))
        XCTAssertFalse(R35Clock.isQuiet(hour: 12, start: 22, end: 7))
        XCTAssertTrue(R35Clock.isQuiet(hour: 13, start: 12, end: 14))
        XCTAssertFalse(R35Clock.isQuiet(hour: 5, start: 6, end: 6))   // gleich = nie
        XCTAssertTrue(R35Clock.isQuiet(hour: 47, start: 22, end: 7))  // 47 = 23 Uhr
    }

    // MARK: Sprachwahl

    func testLocaleResolve() {
        let supported = ["de", "en", "th", "zh-Hans", "es"]
        XCTAssertEqual(R35Locale.resolve(preferred: ["zh-Hans-CN"], supported: supported), "zh-Hans")
        XCTAssertEqual(R35Locale.resolve(preferred: ["de_AT"], supported: supported), "de")
        XCTAssertEqual(R35Locale.resolve(preferred: ["zh-TW", "th"], supported: supported), "zh-Hans")   // eine Variante
        XCTAssertEqual(R35Locale.resolve(preferred: ["pt-BR", "es-MX"], supported: supported), "es")
        XCTAssertEqual(R35Locale.resolve(preferred: ["pt-BR"], supported: supported), "en")
        XCTAssertEqual(R35Locale.resolve(preferred: [], supported: supported, fallback: "de"), "de")
        XCTAssertEqual(R35Locale.resolve(preferred: ["TH"], supported: supported), "th")
    }

    // MARK: Text

    func testTruncateKeepsGraphemes() {
        XCTAssertEqual(R35Text.truncate("Hallo", maxChars: 10), "Hallo")
        XCTAssertEqual(R35Text.truncate("Hallo Welt", maxChars: 6), "Hallo…")
        XCTAssertEqual(R35Text.truncate("Hallo Welt", maxChars: 1), "…")
        let thai = "สวัสดีครับ"
        let cut = R35Text.truncate(thai, maxChars: 4)
        XCTAssertEqual(cut.count, 4)
        XCTAssertTrue(cut.hasSuffix("…"))
        XCTAssertTrue(thai.hasPrefix(String(cut.dropLast())))   // Zeichenfolge bleibt ein Anfang des Originals
        let family = "👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦"
        XCTAssertEqual(R35Text.truncate(family, maxChars: 2).count, 2)
    }

    func testSanitizeRemovesControlAndBidiOverrides() {
        XCTAssertEqual(R35Text.sanitized("a\u{0007}b\u{202E}c\u{2066}d\u{0085}e"), "abcde")
        XCTAssertEqual(R35Text.sanitized("zeile1\nzeile2\tx"), "zeile1\nzeile2\tx")
        XCTAssertEqual(R35Text.sanitized("สวัสดี"), "สวัสดี")
    }

    func testShareText() {
        let t = R35Text.shareText(pairs: [("Hallo", "สวัสดี"), ("", ""), ("  Danke\u{202E} ", "ขอบคุณ"), ("Nur Quelle", "")])
        XCTAssertEqual(t, "1. Hallo\n   สวัสดี\n2. Danke\n   ขอบคุณ\n3. Nur Quelle")
        XCTAssertEqual(R35Text.shareText(pairs: []), "")
    }

    // MARK: Aufbewahrung, Entprellen, Version

    func testRetentionByAgeAndCount() {
        let day = 86_400.0
        let dates = [now.addingTimeInterval(-40 * day), now.addingTimeInterval(-5 * day), now.addingTimeInterval(-1 * day), now]
        XCTAssertEqual(R35Retention.keep(dates: dates, now: now, maxAgeDays: 0, maxCount: 0), [0, 1, 2, 3])
        XCTAssertEqual(R35Retention.keep(dates: dates, now: now, maxAgeDays: 30, maxCount: 0), [1, 2, 3])
        XCTAssertEqual(R35Retention.keep(dates: dates, now: now, maxAgeDays: 0, maxCount: 2), [2, 3])
        XCTAssertEqual(R35Retention.keep(dates: dates, now: now, maxAgeDays: 30, maxCount: 2), [2, 3])
        XCTAssertEqual(R35Retention.keep(dates: [], now: now, maxAgeDays: 7, maxCount: 1), [])
        // Unsortierte Eingabe: die neuesten bleiben, Reihenfolge der Indizes aufsteigend
        let shuffled = [now, now.addingTimeInterval(-3 * day), now.addingTimeInterval(-1 * day)]
        XCTAssertEqual(R35Retention.keep(dates: shuffled, now: now, maxAgeDays: 0, maxCount: 2), [0, 2])
    }

    func testDebounce() {
        XCTAssertTrue(R35Debounce.shouldFire(last: nil, now: now, interval: 2))
        XCTAssertFalse(R35Debounce.shouldFire(last: now, now: now.addingTimeInterval(1), interval: 2))
        XCTAssertTrue(R35Debounce.shouldFire(last: now, now: now.addingTimeInterval(2), interval: 2))
        XCTAssertTrue(R35Debounce.shouldFire(last: now, now: now.addingTimeInterval(-5), interval: 2))   // Uhr zurückgestellt
    }

    func testVersionCompare() {
        XCTAssertEqual(R35Version.compare("1.10.0", "1.9.2"), 1)
        XCTAssertEqual(R35Version.compare("1.3", "1.3.0"), 0)
        XCTAssertEqual(R35Version.compare("1.3", "1.3.1"), -1)
        XCTAssertEqual(R35Version.compare("2.0b1", "2.0"), 0)
        XCTAssertEqual(R35Version.compare("", "0"), 0)
    }

    // MARK: Zusätzliche Tests für Runde 32 bis 34

    func testTravelRegionTableIsUppercaseTwoLetters() {
        for (zone, r) in TravelRegion.byZone {
            XCTAssertEqual(r, r.uppercased(), zone)
            XCTAssertEqual(r.count, 2, zone)
            XCTAssertTrue(zone.contains("/"), zone)
        }
        XCTAssertEqual(TravelRegion.region(forZone: "Asia/Ho_Chi_Minh"), TravelRegion.region(forZone: "Asia/Saigon"))
    }

    func testHotelCardSplitAndOutcome() {
        let s = HotelCard.split("  Hotel Siam \n Soi 4 \n\n Bangkok ")
        XCTAssertEqual(s.name, "Hotel Siam")
        XCTAssertEqual(s.address, "Soi 4, Bangkok")
        XCTAssertEqual(HotelCard.split("").name, "")
        XCTAssertEqual(HotelCard.split("Nur Name").address, "")
        XCTAssertEqual(HotelCard.outcome(hotel: "  \n ", phone: "123"), .empty)
    }

    func testPlannerPruneAndHashedKeys() {
        var p = PlannerStore()
        p.rate("fav|Wo ist die Toilette?", .good, now: now)
        p.rate("b", .easy, now: now)
        XCTAssertNil(p.states["fav|Wo ist die Toilette?"])                 // nur Hash, nie der Satz
        XCTAssertEqual(PlannerStore.key("b").count, 64)
        p.prune(keeping: ["b"])
        XCTAssertEqual(p.states.count, 1)
        XCTAssertNotNil(p.states[PlannerStore.key("b")])
        p.prune(keeping: [])
        XCTAssertTrue(p.states.isEmpty)
        XCTAssertEqual(PlannerStore().forecast(now: now), PlannerStore.Forecast())
    }

    func testPlannerStoreSurvivesUserDefaultsRoundTrip() {
        let name = "r35-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        XCTAssertTrue(PlannerStore.load(d).states.isEmpty)
        var p = PlannerStore()
        p.rate("x", .good, now: now)
        p.save(d)
        XCTAssertEqual(PlannerStore.load(d), p)
        PlannerStore.clear(d)
        XCTAssertTrue(PlannerStore.load(d).states.isEmpty)
    }

    func testCardTopicsIgnoreConversationCards() {
        XCTAssertTrue(CardTopics.tags(cardID: "conv|hello", favorites: []).isEmpty)
        XCTAssertTrue(CardTopics.tags(cardID: "fav|unknown", favorites: []).isEmpty)
    }

    func testWhisperPartialsDecision() {
        func go(_ en: Bool = true, utt: Bool = true, sec: Double = 3, since: Double = 2, busy: Bool = false, fin: Bool = false) -> Bool {
            WhisperPartials.shouldStart(enabled: en, inUtterance: utt, utteranceSeconds: sec, sinceLast: since, partialBusy: busy, finalPending: fin)
        }
        XCTAssertTrue(go())
        XCTAssertFalse(go(false))
        XCTAssertFalse(go(utt: false))
        XCTAssertFalse(go(sec: 1.0))
        XCTAssertFalse(go(sec: 30))
        XCTAssertFalse(go(since: 1.0))
        XCTAssertFalse(go(busy: true))
        XCTAssertFalse(go(fin: true))
        XCTAssertEqual(WhisperPartials.language(last: nil, langs: [.th, .de]), .th)
        XCTAssertEqual(WhisperPartials.language(last: .de, langs: [.th, .de]), .de)
        XCTAssertEqual(WhisperPartials.language(last: .en, langs: [.th, .de]), .th)   // nicht im Paar
        XCTAssertNil(WhisperPartials.language(last: nil, langs: []))
    }

    func testMenuScanNames() {
        XCTAssertEqual(MenuScan.name(of: "unbekannt", in: .en), "unbekannt")
        XCTAssertEqual(MenuScan.names([], in: .en), "")
        XCTAssertEqual(MenuScan.names(["wheat", "gluten"], in: .en), MenuScan.name(of: "gluten", in: .en))   // keine Dopplung
    }
}
