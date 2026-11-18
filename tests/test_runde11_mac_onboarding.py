"""Runde 11 (Mac): Erststart und Einrichtung – Logik per swiftc, Verdrahtung per statischer Prüfung."""
import pathlib
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "app"

MAIN = r'''
import Foundation
var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if !ok { failures += 1; print("FAIL \(line): \(what)") }
}
func r(_ a: Double, _ b: Bool, _ c: String) -> String {
    OnboardingLogic.recommendedModel(ramGB: a, arm64: b, chip: c)
}
check(r(4, true, "Apple M1") == "small", "unter 8 GB")
check(r(16, false, "Intel") == "small", "Intel")
check(r(8, true, "Apple M1") == "medium", "8 GB")
check(r(16, true, "Apple M2") == "medium", "16 GB")
check(r(32, true, "Apple M3 Pro") == "best", "Pro ab 24 GB")
check(r(32, true, "Apple M3") == "medium", "Basischip bleibt medium")
check(OnboardingLogic.interrupted(started: true, envMissing: true, missingGB: nil), "Umgebung fehlt")
check(OnboardingLogic.interrupted(started: true, envMissing: false, missingGB: 1.5), "Modell fehlt")
check(!OnboardingLogic.interrupted(started: true, envMissing: false, missingGB: 0), "alles da")
check(!OnboardingLogic.interrupted(started: false, envMissing: true, missingGB: 2), "nie begonnen")
check(OnboardingLogic.remindDue(until: 0, now: 5), "ohne Merker fällig")
let until = OnboardingLogic.remindUntil(now: 100)
check(until == 100 + 86_400, "ein Tag")
check(!OnboardingLogic.remindDue(until: until, now: 101), "noch nicht fällig")
check(OnboardingLogic.nextStepKey(kind: "offline") == "envsetup_next_offline", "offline")
check(OnboardingLogic.nextStepKey(kind: "kaputt") == "envsetup_next_failed", "unbekannt")
check(OnboardingLogic.canShrinkModel(kind: "no_space", model: "medium"), "Platz: kleiner")
check(!OnboardingLogic.canShrinkModel(kind: "no_space", model: "small"), "schon small")
check(!OnboardingLogic.canShrinkModel(kind: "offline", model: "best"), "offline hilft kein Modell")
check(OnboardingLogic.testPhase(micAuthorized: false, listening: false, heard: false) == "mic", "mic")
check(OnboardingLogic.testPhase(micAuthorized: true, listening: false, heard: false) == "start", "start")
check(OnboardingLogic.testPhase(micAuthorized: true, listening: true, heard: false) == "say", "say")
check(OnboardingLogic.testPhase(micAuthorized: true, listening: true, heard: true) == "done", "done")
print(failures == 0 ? "OK" : "FAILED")
exit(failures == 0 ? 0 : 1)
'''


@pytest.mark.skipif(not shutil.which("swiftc"), reason="swiftc fehlt")
@pytest.mark.timeout(660)
def test_onboarding_logic_swift(tmp_path):
    main = tmp_path / "main.swift"
    main.write_text(MAIN, encoding="utf-8")
    exe = tmp_path / "onboarding_tests"
    b = subprocess.run(["swiftc", "-o", str(exe), str(APP / "OnboardingLogic.swift"), str(main)],
                       capture_output=True, text=True, timeout=600)
    assert b.returncode == 0, b.stderr[-2000:]
    r = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stdout


def test_logic_file_has_no_ui_dependencies():
    src = (APP / "OnboardingLogic.swift").read_text(encoding="utf-8")
    assert "import SwiftUI" not in src and "import AppKit" not in src


def test_welcome_sheet_has_all_steps_and_remind_later():
    v = (APP / "Views.swift").read_text(encoding="utf-8")
    assert "OnboardingSteps(m: engine)" in v
    assert 'L.t("onb_later")' in v and "tipsRemindUntil" in v
    o = (APP / "Onboarding.swift").read_text(encoding="utf-8")
    for needle in ("requestAccess", "Privacy_Microphone", "$m.mineLang", "$m.partnerLang", "$m.model",
                   "APIKeyStore", "onb_test_say", "startListening"):
        assert needle in o, needle


def test_setup_resumes_after_interruption_and_failures_name_the_next_step():
    e = (APP / "EnvSetup.swift").read_text(encoding="utf-8")
    assert e.count("startedKey") >= 4 and "OnboardingLogic.interrupted" in e
    assert "OnboardingLogic.nextStepKey" in e and "envsetup_smaller" in e
