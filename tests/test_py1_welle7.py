"""Runde 21 (py1) Welle 7: Rücknahmen und Negativtests zu früheren Wellen."""
import pytest

import dolmetscher as d


def test_thai_translation_with_sorry_is_not_a_refusal():
    # echte Übersetzung von "Sorry, I can't make it tomorrow" – darf nicht als Claude-Ablehnung gelten
    assert not d._LLM_REFUSAL.search("ขออภัย ไม่สามารถมาพรุ่งนี้ได้ครับ")
    assert d._LLM_REFUSAL.search("ขออภัย ฉันไม่สามารถแปลประโยคนี้ได้")
    assert d._LLM_REFUSAL.search("ฉันไม่สามารถแปลข้อความนี้")


def test_events_and_work_are_not_land_units():
    assert not d.numbers_differ("We have 3 events today", "วันนี้มี 3 งาน")
    assert not d.numbers_differ("3 fingers", "3 นิ้ว")
    assert not d.numbers_differ("a 5 inch screen", "หน้าจอ 5 นิ้ว")


def test_rai_still_converted():
    assert not d.numbers_differ("a 2 rai plot", "ที่ดิน 3,200 ตารางเมตร")
    assert d.numbers_differ("a 2 rai plot", "ที่ดิน 2,000 ตารางเมตร")


@pytest.mark.parametrize("lang", ["ru", "uk", "pl"])
def test_slavic_currency_and_degrees_left_to_the_voice(lang):
    assert d.speak_form("$1", lang) == "$1"
    assert d.speak_form("2°C", lang) == "2°C"


def test_say_voice_choice_is_refreshed_with_the_list(monkeypatch):
    import subprocess
    import types
    picks = []
    out = {"v": "Anna de_DE x\n"}
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: types.SimpleNamespace(stdout=out["v"]))
    monkeypatch.setattr(d, "_SAY_LIST", {"out": None, "fail_t": None})
    real = d.pick_voice
    monkeypatch.setattr(d, "pick_voice", lambda lang: picks.append(lang) or real(lang))
    eng = types.SimpleNamespace(voice={})
    d._say_voice(eng, "de")
    d._say_voice(eng, "de")
    assert picks == ["de"]                                   # gemerkt
    d._SAY_LIST["t"] -= d.SAY_LIST_TTL + 1                   # Liste abgelaufen -> neu lesen, Wahl verwerfen
    d._say_voice(eng, "de")
    assert picks == ["de", "de"]


def test_output_device_kept_after_not_found(monkeypatch):
    # Bluetooth-Gerät noch nicht verbunden: die Wahl bleibt, avhelper fällt auf den Standard zurück
    import avhelper
    monkeypatch.setattr(d, "list_outputs", lambda: [{"name": "MacBook Speakers"}])
    monkeypatch.setattr(avhelper, "match_output", lambda outs, dev: None)
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    monkeypatch.setitem(d.OUTPUT, "device", "")
    import threading
    done = threading.Event()
    real_thread = threading.Thread

    def thread(target=None, **kw):
        return real_thread(target=lambda: (target(), done.set()), **kw)
    monkeypatch.setattr(threading, "Thread", thread)
    d.set_output_device("AirPods")
    assert done.wait(3)
    assert d.OUTPUT["device"] == "AirPods"


def test_glossary_change_keeps_persistent_cache_file(tmp_path, monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY_FILE", str(tmp_path / "g.txt"))
    monkeypatch.setattr(d, "CACHE_FILE", str(tmp_path / "cache.json"))
    d._cache_clear()
    d.load_glossary("")
    d.cache_persist(True)
    try:
        d._cache_put(d._cache_key("hello", "en", "de", False, "krub"), ("hallo", "google"))
        d._cache_save(force=True)
        assert (tmp_path / "cache.json").exists()
        d.load_glossary("Nok")
        assert (tmp_path / "cache.json").exists()            # früher: gelöscht
    finally:
        d._CACHE_DISK["on"] = False
        d.load_glossary("")
        d._cache_clear()


def test_cache_signature_llm_includes_preset_hint(monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY", [])
    monkeypatch.setattr(d, "_GLOSSARY_OWN", frozenset())
    monkeypatch.setattr(d.PRESET, "hint", None)
    k0 = d._cache_key("x", "en", "de", True, "krub")
    monkeypatch.setattr(d.PRESET, "hint", "Hotel check-in")
    k1 = d._cache_key("x", "en", "de", True, "krub")
    assert k0 != k1
    assert d._cache_key("x", "en", "de", False, "krub")[3] == "mt"      # ohne Glossar: Schlüssel wie früher


def test_cache_signature_mt_only_own_words(monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY", [("room", "ห้อง")])
    monkeypatch.setattr(d, "_GLOSSARY_OWN", frozenset())                # Preset-Wort, nicht eigenes
    k_preset = d._cache_key("x", "en", "th", False, "krub")
    monkeypatch.setattr(d, "_GLOSSARY_OWN", frozenset({("Nok", None)}))
    assert d._cache_key("x", "en", "th", False, "krub") != k_preset


def test_learn_names_with_real_preset_roundtrip(monkeypatch, tmp_path):
    import types
    import presets
    pid = next(iter(presets.load_all()))
    monkeypatch.setattr(d, "GLOSSARY_FILE", str(tmp_path / "g.txt"))
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    monkeypatch.setattr(d, "prerender_critical", lambda *a, **k: pytest.fail("keine TTS-Vorberechnung beim Lernen"))
    monkeypatch.setattr(d, "CACHE_FILE", str(tmp_path / "c.json"))
    eng = types.SimpleNamespace(polite="krub", voices={}, rate=0)
    d.load_glossary("Eigen\n")
    monkeypatch.setattr(d, "prerender_critical", lambda *a, **k: None)
    try:
        assert d.set_preset(eng, pid, quiet=True)
        n_before = len(d.GLOSSARY)
        monkeypatch.setattr(d, "prerender_critical", lambda *a, **k: pytest.fail("keine TTS-Vorberechnung beim Lernen"))
        assert d.learn_glossary_names(eng, ["Zorbax"]) == ["Zorbax"]
        assert d.PRESET.active == pid
        assert ("Zorbax", None) in d.GLOSSARY and len(d.GLOSSARY) >= min(n_before, d.GLOSSARY_LIMIT)
        assert [a for a, _ in d.GLOSSARY][:2] == ["Eigen", "Zorbax"]          # eigene Wörter vor den Preset-Wörtern
        monkeypatch.setattr(d, "prerender_critical", lambda *a, **k: None)
        d.set_preset(eng, None, quiet=True)
        assert d.GLOSSARY == [("Eigen", None), ("Zorbax", None)]              # Zurückstellen behält das Gelernte
        assert "Zorbax" in (tmp_path / "g.txt").read_text(encoding="utf-8")
    finally:
        monkeypatch.setattr(d, "prerender_critical", lambda *a, **k: None)
        d.set_preset(eng, None, quiet=True)
        d.load_glossary("")


def test_manual_tuning_change_survives_preset_switch_off(monkeypatch):
    import types
    monkeypatch.setattr(d, "SILENCE_END", 0.7)
    monkeypatch.setattr(d, "_TUNING_SAVED", {})
    monkeypatch.setattr(d, "_TUNING_APPLIED", {})
    monkeypatch.setitem(d.LET_FINISH, "s", 0.0)
    monkeypatch.setitem(d.CATCH_UP, "mode", "skip")
    eng = types.SimpleNamespace(rate=0)
    d._apply_preset_tuning(eng, {"tuning": {"silence": 1.5, "let_finish": 1.0, "rate": -20}})
    assert d.SILENCE_END == 1.5 and eng.rate == -20
    d.SILENCE_END = 1.1                       # Nutzer stellt die Stille währenddessen selbst ein
    d._apply_preset_tuning(eng, None)
    assert d.SILENCE_END == 1.1               # bleibt (früher: auf 0.7 zurückgesetzt)
    assert d.LET_FINISH["s"] == 0.0 and eng.rate == 0   # unveränderte Preset-Werte gehen zurück


def test_switching_between_presets_restores_original_not_previous(monkeypatch):
    import types
    monkeypatch.setattr(d, "SILENCE_END", 0.7)
    monkeypatch.setattr(d, "_TUNING_SAVED", {})
    monkeypatch.setattr(d, "_TUNING_APPLIED", {})
    eng = types.SimpleNamespace(rate=0)
    d._apply_preset_tuning(eng, {"tuning": {"silence": 1.5}})
    d._apply_preset_tuning(eng, {"tuning": {"silence": 1.2}})
    assert d.SILENCE_END == 1.2
    d._apply_preset_tuning(eng, None)
    assert d.SILENCE_END == 0.7
