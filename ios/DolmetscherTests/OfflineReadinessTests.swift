import XCTest
@testable import Dolmetscher

/// Runde 16: Offline-Bereitschaft (reine Logik), Reisewarnung, „Nur offline“.
final class OfflineReadinessTests: XCTestCase {
    private func inputs(rm: Readiness = .installed, rp: Readiness = .installed, t: Readiness = .installed,
                        vm: Bool = true, vp: Bool = true, loading: Set<PackKind> = [], phrasebook: Bool = false) -> OfflineInputs {
        OfflineInputs(mine: .en, partner: .th, recognizerMine: rm, recognizerPartner: rp, translation: t,
                      voiceMine: vm, voicePartner: vp, loading: loading, phrasebook: phrasebook)
    }

    func testEverythingInstalledIsReadyWithoutWarning() {
        let r = OfflineReport.evaluate(inputs())
        XCTAssertTrue(r.isReady)
        XCTAssertEqual(r.verdict, .ready)
        XCTAssertNil(r.travelWarning)
        XCTAssertEqual(r.missingMB, 0)
        XCTAssertTrue(r.recognitionReady && r.translationReady && r.speechReady)
    }

    func testMissingPacksAreLoadableAndSized() {
        let r = OfflineReport.evaluate(inputs(rp: .downloadable, t: .downloadable))
        XCTAssertEqual(r.verdict, .needsDownload)
        XCTAssertEqual(r.state(of: .recognizer(.th)), .missing)
        XCTAssertEqual(r.state(of: .translation), .missing)
        XCTAssertEqual(r.loadable.count, 2)
        XCTAssertEqual(r.missingMB, PackSize.recognizerMB + 2 * PackSize.translationMB)
        XCTAssertEqual(r.travelWarning, .missing([.recognizer(.th), .translation]))
        XCTAssertFalse(r.recognitionReady)
    }

    func testLoadingStateOnlyForMissingItems() {
        let r = OfflineReport.evaluate(inputs(rp: .downloadable, loading: [.recognizer(.th), .recognizer(.en)]))
        XCTAssertEqual(r.state(of: .recognizer(.th)), .loading)
        XCTAssertEqual(r.state(of: .recognizer(.en)), .ready)
        XCTAssertTrue(r.isLoading)
        XCTAssertEqual(r.verdict, .needsDownload)
        XCTAssertEqual(r.missingMB, PackSize.recognizerMB)
    }

    func testUnsupportedTranslationLimitsThePair() {
        let r = OfflineReport.evaluate(inputs(t: .unsupported))
        XCTAssertEqual(r.verdict, .limited)
        XCTAssertEqual(r.travelWarning, .limited([.translation], []))
        XCTAssertEqual(r.travelWarning?.textKey, "off_warn_limited")
    }

    func testMissingVoiceLimitsButIsNotLoadableHere() {
        let r = OfflineReport.evaluate(inputs(vp: false))
        XCTAssertEqual(r.verdict, .limited)
        XCTAssertEqual(r.state(of: .voice(.th)), .unavailable)
        XCTAssertFalse(r.items.first { $0.kind == .voice(.th) }!.canLoadHere)
        XCTAssertTrue(r.loadable.isEmpty)
        XCTAssertEqual(r.missingMB, 0)
    }

    func testPhrasebookPledgeFollowsThePair() {
        XCTAssertTrue(OfflineReport.evaluate(inputs(t: .downloadable, phrasebook: true)).phrasebookAlwaysOffline)
        XCTAssertFalse(OfflineReport.evaluate(inputs()).phrasebookAlwaysOffline)
    }

    func testOfflineOnlyOverridesOnlineSetting() {
        XCTAssertTrue(OfflineMode.allowsOnline(allowOnline: true, offlineOnly: false))
        XCTAssertFalse(OfflineMode.allowsOnline(allowOnline: true, offlineOnly: true))
        XCTAssertFalse(OfflineMode.allowsOnline(allowOnline: false, offlineOnly: false))
    }

    func testOfflineOnlyDefaultsToOff() {
        let d = UserDefaults(suiteName: "offline-test-\(UUID().uuidString)")!
        XCTAssertFalse(OfflineMode.setting(d))
        d.set(true, forKey: OfflineMode.key)
        XCTAssertTrue(OfflineMode.setting(d))
    }

    func testErrorKeyNamesTheOfflinePacksWhenOfflineOnly() {
        XCTAssertEqual(OfflineMode.missingErrorKey(offlineOnly: true, allowOnline: true), "err_offline_only")
        XCTAssertEqual(OfflineMode.missingErrorKey(offlineOnly: false, allowOnline: true), "err_translate")
        XCTAssertEqual(OfflineMode.missingErrorKey(offlineOnly: false, allowOnline: false), "err_offline_missing")
        XCTAssertEqual(ErrorAdvice.action(for: T("err_offline_only")), .appSettings)
    }

    func testTextsExistInAllLanguages() {
        for key in ["off_title", "off_warn_missing", "off_warn_limited", "off_all_ok", "off_only", "err_offline_only", "off_blocked"] {
            for lang in L10n.languages { XCTAssertFalse((L10n.text(key, lang: lang) ?? "").isEmpty, "\(lang): \(key)") }
        }
    }
}
