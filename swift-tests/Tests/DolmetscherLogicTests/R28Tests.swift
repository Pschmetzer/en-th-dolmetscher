import XCTest
@testable import DolmetscherLogic

final class R28Tests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!
    }

    // MARK: 1 BubbleA11y
    func testBubbleLabelFull() {
        XCTAssertEqual(BubbleA11y.label(speaker: "Sprecher 1", original: "Hello", translation: "สวัสดี", time: "12:00", lang: "en"),
                       "Sprecher 1. Hello. Translation: สวัสดี. 12:00")
    }
    func testBubbleLabelSkipsEmptyParts() {
        XCTAssertEqual(BubbleA11y.label(speaker: " ", original: "Hallo", translation: "", time: nil, lang: "de"), "Hallo")
        XCTAssertEqual(BubbleA11y.label(speaker: "", original: "", translation: "x", time: "", lang: "de"), "Übersetzung: x")
    }

    // MARK: 2 SettingsSearch
    func testSettingsSearchIgnoresCaseAndAccents() {
        XCTAssertTrue(SettingsSearch.matches(haystack: "Café Ausgabe", query: "CAFE"))
        XCTAssertTrue(SettingsSearch.matches(haystack: "Ausgabegerät Lautsprecher", query: "gerat laut"))
    }
    func testSettingsSearchAllWordsMustMatch() {
        XCTAssertFalse(SettingsSearch.matches(haystack: "Ausgabegerät Lautsprecher", query: "gerat xyz"))
        XCTAssertTrue(SettingsSearch.matches(haystack: "irgendwas", query: "   "))
    }
    func testSettingsSearchFilter() {
        let items = ["Mikrofon", "Ausgabe", "Anzeige"]
        XCTAssertEqual(SettingsSearch.filter(items, query: "anz", text: { $0 }), ["Anzeige"])
    }

    // MARK: 3 SystemShortcutGuard
    func testReservedShortcutsAreRecognizedRegardlessOfModifierOrder() {
        XCTAssertTrue(SystemShortcutGuard.isReserved("⌘Q"))
        XCTAssertTrue(SystemShortcutGuard.isReserved("⌘⇧3"))
        XCTAssertTrue(SystemShortcutGuard.isReserved("⇧⌘3"))
        XCTAssertFalse(SystemShortcutGuard.isReserved("⌥⌘J"))
    }
    func testSafeGlobalShortcutNeedsModifier() {
        XCTAssertTrue(SystemShortcutGuard.isSafeGlobal("⌥⌘J"))
        XCTAssertFalse(SystemShortcutGuard.isSafeGlobal("J"))
        XCTAssertFalse(SystemShortcutGuard.isSafeGlobal("⌘"))
        XCTAssertFalse(SystemShortcutGuard.isSafeGlobal("⌘Q"))
        XCTAssertFalse(SystemShortcutGuard.isSafeGlobal("⇧J"))
    }
    func testNormalizeOrdersModifiers() {
        XCTAssertEqual(SystemShortcutGuard.normalize("⌘⌥s"), "⌥⌘S")
    }

    // MARK: 4 SessionClock
    func testClockFormats() {
        XCTAssertEqual(SessionClock.clock(65), "1:05")
        XCTAssertEqual(SessionClock.clock(3903), "1:05:03")
        XCTAssertEqual(SessionClock.clock(-5), "0:00")
    }
    func testClockSpoken() {
        XCTAssertEqual(SessionClock.spoken(3900, lang: "en"), "1 hour 5 minutes")
        XCTAssertEqual(SessionClock.spoken(0, lang: "de"), "0 Minuten")
        XCTAssertEqual(SessionClock.spoken(3600, lang: "de"), "1 Stunde")
        XCTAssertEqual(SessionClock.spoken(60, lang: "de"), "1 Minute")
    }

    // MARK: 5 Count
    func testCountPlural() {
        XCTAssertEqual(Count.sentences(1, lang: "de"), "1 Satz")
        XCTAssertEqual(Count.sentences(3, lang: "de"), "3 Sätze")
        XCTAssertEqual(Count.sentences(2, lang: "en"), "2 sentences")
        XCTAssertEqual(Count.sentences(0, lang: "en"), "0 sentences")
        XCTAssertEqual(Count.sentences(3, lang: "th"), "3 ประโยค")
    }

    // MARK: 6 SensitiveTextGuard
    func testDetectsApiKey() {
        XCTAssertEqual(SensitiveTextGuard.detect("my key is sk-abcdefghijklmnopqrstuvwxyz ok"), .apiKey)
        XCTAssertEqual(SensitiveTextGuard.detect("token a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6"), .apiKey)
    }
    func testDetectsCardNumberWithLuhn() {
        XCTAssertEqual(SensitiveTextGuard.detect("4111 1111 1111 1111"), .cardNumber)
        XCTAssertEqual(SensitiveTextGuard.detect("4111-1111-1111-1111"), .cardNumber)
        XCTAssertNil(SensitiveTextGuard.detect("4111111111111112"))
    }
    func testDetectsIban() {
        XCTAssertEqual(SensitiveTextGuard.detect("DE89 3704 0044 0532 0130 00"), .iban)
    }
    func testOrdinaryTextIsNotSensitive() {
        XCTAssertNil(SensitiveTextGuard.detect("Where is the station?"))
        XCTAssertNil(SensitiveTextGuard.detect("Call me on +66 81 234 5678"))
        XCTAssertNil(SensitiveTextGuard.detect(""))
    }

    // MARK: 7 EngineRestartPlan
    func testBackoffDoublesAndCaps() {
        XCTAssertEqual(EngineRestartPlan.delay(attempt: 0), 0)
        XCTAssertEqual(EngineRestartPlan.delay(attempt: 1), 2)
        XCTAssertEqual(EngineRestartPlan.delay(attempt: 2), 4)
        XCTAssertEqual(EngineRestartPlan.delay(attempt: 3), 8)
        XCTAssertEqual(EngineRestartPlan.delay(attempt: 5), 30)
        XCTAssertEqual(EngineRestartPlan.delay(attempt: 500), 30)
    }
    func testBackoffGivesUp() {
        XCTAssertTrue(EngineRestartPlan.shouldRetry(attempt: 5))
        XCTAssertFalse(EngineRestartPlan.shouldRetry(attempt: 6))
    }

    // MARK: 8 DiskSpaceAdvice
    func testDiskLevels() {
        XCTAssertEqual(DiskSpaceAdvice.level(freeBytes: 100_000_000), .critical)
        XCTAssertEqual(DiskSpaceAdvice.level(freeBytes: 1_000_000_000), .low)
        XCTAssertEqual(DiskSpaceAdvice.level(freeBytes: 10_000_000_000), .ok)
    }
    func testDiskTexts() {
        XCTAssertNil(DiskSpaceAdvice.text(freeBytes: 10_000_000_000, lang: "en"))
        XCTAssertTrue(DiskSpaceAdvice.text(freeBytes: 1_000_000_000, lang: "en")!.contains("1.0 GB"))
        XCTAssertTrue(DiskSpaceAdvice.text(freeBytes: 100_000_000, lang: "de")!.contains("Fast kein Speicherplatz"))
    }

    // MARK: 9 MicLevelText
    func testLevelNormalizedClamps() {
        XCTAssertEqual(MicLevelText.normalized(db: -60), 0)
        XCTAssertEqual(MicLevelText.normalized(db: -30), 0.5, accuracy: 0.0001)
        XCTAssertEqual(MicLevelText.normalized(db: 0), 1)
        XCTAssertEqual(MicLevelText.normalized(db: -100), 0)
        XCTAssertEqual(MicLevelText.normalized(db: 5), 1)
        XCTAssertEqual(MicLevelText.normalized(db: .nan), 0)
        XCTAssertEqual(MicLevelText.normalized(db: -.infinity), 0)
    }
    func testLevelBands() {
        XCTAssertEqual(MicLevelText.band(db: -60), .silent)
        XCTAssertEqual(MicLevelText.band(db: -50), .quiet)
        XCTAssertEqual(MicLevelText.band(db: -30), .good)
        XCTAssertEqual(MicLevelText.band(db: -3), .loud)
        XCTAssertEqual(MicLevelText.spoken(db: -3, lang: "de"), "zu laut")
        XCTAssertEqual(MicLevelText.spoken(db: -60, lang: "en"), "Silence")
    }

    // MARK: 10 NoInputAdvice
    func testNoInputAdvice() {
        XCTAssertNil(NoInputAdvice.text(listening: false, secondsSinceSpeech: 100, micMuted: true, lang: "en"))
        XCTAssertEqual(NoInputAdvice.text(listening: true, secondsSinceSpeech: 0, micMuted: true, lang: "en"), "The microphone is muted.")
        XCTAssertNil(NoInputAdvice.text(listening: true, secondsSinceSpeech: 10, micMuted: false, lang: "en"))
        XCTAssertTrue(NoInputAdvice.text(listening: true, secondsSinceSpeech: 45, micMuted: false, lang: "de")!.contains("45"))
    }

    // MARK: 11 ExportFileName
    func testExportFileName() {
        XCTAssertEqual(ExportFileName.make(date: date(2026, 11, 21, 14, 5), from: "en", to: "th", ext: "pdf", calendar: utc),
                       "dolmetscher_2026-11-21_1405_en-th.pdf")
    }
    func testExportFileNameSanitizes() {
        XCTAssertEqual(ExportFileName.sanitize("a b/c"), "a-b-c")
        XCTAssertEqual(ExportFileName.sanitize("..x.."), "x")
        XCTAssertEqual(ExportFileName.make(date: date(2026, 1, 2, 3, 4), from: "e/n", to: "t h", ext: ".MD", calendar: utc),
                       "dolmetscher_2026-01-02_0304_e-n-t-h.md")
        XCTAssertEqual(ExportFileName.make(date: date(2026, 1, 2), from: "en", to: "th", ext: "", calendar: utc),
                       "dolmetscher_2026-01-02_0000_en-th")
    }

    // MARK: 12 CharLimit
    func testCharLimitStates() {
        XCTAssertEqual(CharLimit.state(count: 10, limit: 500), .ok)
        XCTAssertEqual(CharLimit.state(count: 450, limit: 500), .warn)
        XCTAssertEqual(CharLimit.state(count: 500, limit: 500), .warn)
        XCTAssertEqual(CharLimit.state(count: 501, limit: 500), .over)
    }
    func testCharLimitLabel() {
        XCTAssertEqual(CharLimit.label(count: 12, limit: 500, lang: "en"), "12/500")
        XCTAssertEqual(CharLimit.label(count: 505, limit: 500, lang: "en"), "505/500 – 5 over")
        XCTAssertEqual(CharLimit.label(count: 505, limit: 500, lang: "de"), "505/500 – 5 zu viel")
    }

    // MARK: 13 SettingsMigration
    func testMigrationMovesOldKeys() {
        let r = SettingsMigration.migrate(["showTranslit": true, "other": 1])
        XCTAssertEqual(r.values["translit"] as? Bool, true)
        XCTAssertNil(r.values["showTranslit"])
        XCTAssertEqual(r.values["other"] as? Int, 1)
        XCTAssertEqual(r.moved, ["showTranslit"])
    }
    func testMigrationKeepsNewValue() {
        let r = SettingsMigration.migrate(["fontSize": 2.0, "fontScale": 1.2])
        XCTAssertEqual(r.values["fontScale"] as? Double, 1.2)
        XCTAssertNil(r.values["fontSize"])
        XCTAssertEqual(r.moved, [])
    }
    func testMigrationIsIdempotent() {
        let once = SettingsMigration.migrate(["topmost": true]).values
        let twice = SettingsMigration.migrate(once)
        XCTAssertEqual(twice.values["alwaysOnTop"] as? Bool, true)
        XCTAssertEqual(twice.moved, [])
    }

    // MARK: 14 PairSpeech
    func testPairSpeech() {
        XCTAssertEqual(PairSpeech.spoken(from: "en", to: "th", lang: "de"), "Englisch nach Thai")
        XCTAssertEqual(PairSpeech.spoken(from: "th", to: "en", lang: "en"), "Thai to English")
        XCTAssertEqual(PairSpeech.spoken(from: "en", to: "th", lang: "th"), "อังกฤษ เป็น ไทย")
        XCTAssertEqual(PairSpeech.name("xx", lang: "de"), "xx")
    }

    // MARK: 15 MenuTitle
    func testMenuTitleShorten() {
        XCTAssertEqual(MenuTitle.shorten("Hi there", max: 20), "Hi there")
        XCTAssertEqual(MenuTitle.shorten("a   b", max: 20), "a b")
        XCTAssertEqual(MenuTitle.shorten("Hello   world foo bar", max: 14), "Hello world…")
        XCTAssertEqual(MenuTitle.shorten("Supercalifragilistic", max: 8), "Superca…")
    }

    // MARK: 16 DayGroup
    func testDayGroup() {
        let now = date(2026, 11, 21, 12)
        XCTAssertEqual(DayGroup.label(for: date(2026, 11, 21, 1), now: now, lang: "de", calendar: utc), "Heute")
        XCTAssertEqual(DayGroup.label(for: date(2026, 11, 20, 23), now: now, lang: "en", calendar: utc), "Yesterday")
        XCTAssertEqual(DayGroup.label(for: date(2026, 11, 10), now: now, lang: "en", calendar: utc), "2026-11-10")
    }
}
