import XCTest
@testable import Dolmetscher

/// Runde 14: Erststart und Berechtigungen – Schritte, Hinweise, Größe, Texte.
final class Round14Tests: XCTestCase {
    func testStepsRunInOrderAndEndOnTest() {
        var flow = OnboardingFlow()
        XCTAssertEqual(flow.step, .pair)
        var seen = [flow.step]
        while !flow.finished { flow.advance(); if !flow.finished { seen.append(flow.step) } }
        XCTAssertEqual(seen, [.pair, .microphone, .speech, .packs, .test])
        XCTAssertTrue(OnboardingStep.test.isLast)
        XCTAssertEqual(OnboardingStep.test.position, OnboardingStep.count)
    }

    func testGoBackStopsAtFirstStep() {
        var flow = OnboardingFlow()
        flow.goBack()
        XCTAssertEqual(flow.step, .pair)
        flow.advance(); flow.advance(); flow.goBack()
        XCTAssertEqual(flow.step, .microphone)
    }

    func testLaterIsRememberedAndNotFinished() {
        var flow = OnboardingFlow()
        flow.later()
        XCTAssertTrue(flow.deferredLater)
        XCTAssertFalse(flow.finished)
    }

    func testPermissionAdvice() {
        XCTAssertEqual(PermissionAdvice.of(.notDetermined), .explainThenAsk)
        XCTAssertEqual(PermissionAdvice.of(.granted), .proceed)
        XCTAssertEqual(PermissionAdvice.of(.denied), .openSettings)
        XCTAssertEqual(PermissionAdvice.of(.restricted), .restricted)
        XCTAssertTrue(PermissionAdvice.openSettings.offersSettings)
        XCTAssertTrue(PermissionAdvice.restricted.offersSettings)
        XCTAssertFalse(PermissionAdvice.explainThenAsk.offersSettings)
        XCTAssertFalse(PermissionAdvice.proceed.offersSettings)
    }

    func testSummaryBannerOnlyAfterRefusal() {
        XCTAssertNil(PermissionSummary(microphone: .notDetermined, speech: .notDetermined).bannerTextKey)
        XCTAssertFalse(PermissionSummary(microphone: .granted, speech: .granted).needsBanner)
        XCTAssertTrue(PermissionSummary(microphone: .granted, speech: .granted).allGranted)
        let micDenied = PermissionSummary(microphone: .denied, speech: .granted)
        XCTAssertTrue(micDenied.blocksListening)
        XCTAssertEqual(micDenied.bannerTextKey, "ob_mic_denied")
        XCTAssertEqual(PermissionSummary(microphone: .restricted, speech: .denied).bannerTextKey, "ob_mic_restricted")
        let speechDenied = PermissionSummary(microphone: .granted, speech: .denied)
        XCTAssertFalse(speechDenied.blocksListening)
        XCTAssertTrue(speechDenied.needsBanner)
        XCTAssertEqual(speechDenied.bannerTextKey, "ob_speech_denied")
        XCTAssertEqual(PermissionSummary(microphone: .granted, speech: .restricted).bannerTextKey, "ob_speech_restricted")
    }

    func testPolicyShowsOnlyForNewUsersWhoNeitherFinishedNorPostponed() {
        XCTAssertTrue(OnboardingPolicy.shouldShowAtLaunch(completed: false, deferred: false, existingUser: false))
        XCTAssertFalse(OnboardingPolicy.shouldShowAtLaunch(completed: true, deferred: false, existingUser: false))
        XCTAssertFalse(OnboardingPolicy.shouldShowAtLaunch(completed: false, deferred: true, existingUser: false))
        XCTAssertFalse(OnboardingPolicy.shouldShowAtLaunch(completed: false, deferred: false, existingUser: true))
    }

    func testPackSize() {
        XCTAssertEqual(PackSize.missingMB(recognizers: 0, translations: 0), 0)
        XCTAssertEqual(PackSize.missingMB(recognizers: 2, translations: 2), 700)
        XCTAssertEqual(PackSize.missingMB(recognizers: -1, translations: 1), PackSize.translationMB)
        XCTAssertNil(PackSize.format(mb: 0))
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(PackSize.format(mb: 700, locale: us), "700 MB")
        XCTAssertEqual(PackSize.format(mb: 347, locale: us), "350 MB")
        XCTAssertEqual(PackSize.format(mb: 1200, locale: us), "1.2 GB")
        XCTAssertEqual(PackSize.format(mb: 1200, locale: Locale(identifier: "de_DE")), "1,2 GB")
    }

    func testPairNeverEqual() {
        XCTAssertEqual(OnboardingFlow.pair(mine: .de, partner: .th), LangPair(mine: .de, partner: .th))
        XCTAssertEqual(OnboardingFlow.pair(mine: .en, partner: .en), LangPair(mine: .en, partner: .th))
        XCTAssertEqual(OnboardingFlow.pair(mine: .th, partner: .th), LangPair(mine: .th, partner: .en))
    }

    func testTextsCompleteInAllLanguages() {
        var keys: Set<String> = Set(L10n.round14.keys)
        for step in OnboardingStep.allCases { keys.insert(step.titleKey); keys.insert(step.bodyKey) }
        for s in [PermissionSummary(microphone: .denied, speech: .granted), PermissionSummary(microphone: .restricted, speech: .granted),
                  PermissionSummary(microphone: .granted, speech: .denied), PermissionSummary(microphone: .granted, speech: .restricted)] {
            keys.insert(s.bannerTextKey ?? "")
        }
        keys.remove("ob_packs_b")  // Platzhalter, eigener Test
        for key in keys {
            guard let row = L10n.round14[key] else { XCTFail("Schlüssel \(key) fehlt in round14"); continue }
            for lang in L10n.languages {
                XCTAssertFalse((row[lang] ?? "").trimmingCharacters(in: .whitespaces).isEmpty, "\(lang): \(key)")
            }
        }
        XCTAssertTrue(Set(L10n.round14.keys).isDisjoint(with: Set(L10n.table.keys).union(L10n.round4.keys).union(L10n.round5.keys)
            .union(L10n.round6.keys).union(L10n.round7.keys).union(L10n.round8.keys).union(L10n.round9.keys)), "Schlüssel doppelt")
        for lang in L10n.languages {
            XCTAssertTrue((L10n.round14["ob_packs_b"]?[lang] ?? "").contains("%@"), "\(lang): ob_packs_b ohne %@")
            XCTAssertTrue((L10n.round14["ob_step"]?[lang] ?? "").contains("%d"), "\(lang): ob_step ohne %d")
            XCTAssertEqual(L10n.text("ob_later", lang: lang), L10n.round14["ob_later"]?[lang])
        }
    }
}
