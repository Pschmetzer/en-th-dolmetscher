"""Runde 4, Mac-App (Quelltext-Prüfungen, kein Live-Lauf): Ausgabegerät (24/357), VoiceOver-Ansagen (365, 367),
Filter einmal je Durchlauf (369), Diagnosebericht im Absturz-Banner (372), Erklärungen (389), Bericht (391)."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "app"


def src(name):
    return (APP / name).read_text(encoding="utf-8")


def test_ausgabegeraet_liste_aus_coreaudio_nur_ausgaenge():
    s = src("AudioOutputs.swift")
    assert "kAudioHardwarePropertyDevices" in s and "kAudioDevicePropertyScopeOutput" in s
    assert "kAudioDevicePropertyDeviceUID" in s


def test_ausgabegeraet_start_und_live():
    e = src("Engine.swift")
    assert '["--output-device", outputDevice]' in e and 'send(["output_device": outputDevice])' in e
    # nicht im Neustart-Fingerabdruck: Wechsel ohne Neuladen der Modelle
    fp = re.search(r'"\\\(model\)\|.*?"', e)
    assert fp and "outputDevice" not in fp.group(0)
    assert "OutputSection()" in src("SettingsView.swift")


def test_voiceover_zustandswechsel():
    e = src("Engine.swift")
    for key in ("a11y_ready", "a11y_mic_on", "a11y_mic_off", "a11y_paused", "a11y_offline", "a11y_online"):
        assert key in e, key
    assert "!pushToTalk" in e                       # keine Ansage bei jedem Push-to-Talk-Druck
    v = src("Views.swift")
    banner = v[v.index("struct NoticeBanner"):v.index("struct VocabSuggestionBanner")]
    assert ".onAppear { Announcer.post(text) }" in banner


def test_filter_einmal_je_durchlauf():
    v = src("Views.swift")
    conv = v[v.index("private var conversation"):]
    assert "let shown = self.shown" in conv


def test_absturz_banner_mit_diagnosebericht():
    v = src("Views.swift")
    crash = v[v.index("struct CrashBanner"):v.index("struct TipsSheet")]
    assert "diagnosticReport(python:" in crash and 'L.t("diag_copy")' in crash


def test_erklaerungen_und_bericht():
    s = src("SettingsView.swift")
    assert 'L.t("silence_help")' in s and 'L.t("sensitivity_help")' in s
    r = src("Support.swift")
    for f in ("silence=", "sensitivity=", "ttsRace=", "fastEndpoint=", "partialText=", "rate=", "kürzelFehler="):
        assert f in r, f
