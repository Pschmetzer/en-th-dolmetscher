"""Runde 2, Mac-App: Kontrakt mit der Engine (Quelltext-Prüfungen, ohne App zu bauen)."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = {f.name: f.read_text(encoding="utf-8") for f in (ROOT / "app").glob("*.swift")}
SWIFT = "\n".join(APP.values())
ENGINE = (ROOT / "dolmetscher.py").read_text(encoding="utf-8")


def test_mikrofon_live_statt_neustart():
    sig = re.search(r"var restartSignature: String \{\s*\"([^\"]*)\"", APP["Engine.swift"]).group(1)
    assert "mic" not in sig.lower()
    assert 'send(["mic": Self.micControlValue(' in APP["Engine.swift"]
    assert "m.selectMic(index:" in APP["SettingsView.swift"] + APP["SettingsAudioSections.swift"]
    assert '"mic" in d' in ENGINE


def test_kopfzeile_richtung_vorlesen_texteingabe():
    bar = APP["Views.swift"].split("struct ConversationBar", 1)[1].split("\nstruct ", 1)[0]
    assert "selection: $m.lang" in bar and 'tag("auto")' in bar and "ForEach(Langs.pair" in bar
    assert "$m.speak" in bar and "m.sayTyped(draft)" in bar
    assert "ConversationBar()" in APP["Views.swift"]
    say = APP["Engine.swift"].split("func sayTyped", 1)[1].split("\n    }\n", 1)[0]
    assert "prefix(1000)" in say and "Langs.guessLang" in say and "mineLang" in say


def test_partner_band_bei_pause_und_mikro_aus():
    pv = APP["PartnerView.swift"]
    assert "partner_banner_paused" in pv and "partner_banner_mic_off" in pv
    assert "L.t(b.key, partnerUI)" in pv


def test_neue_ereignisse_und_felder_in_der_app():
    assert 'case "missed"' in SWIFT and 'emit("missed"' in ENGINE
    assert 'o["month_usd"]' in SWIFT and "month_usd=" in ENGINE
    assert 'o["code"] as? String == "translate_failed"' in SWIFT and "func retryFailed()" in SWIFT
    assert '"--llm-budget"' in SWIFT and 'send(["llm_budget": llmBudget])' in SWIFT
