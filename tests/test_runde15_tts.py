"""Runde 15, Engine: Sprachausgabe (nichts Sprechbares, Emoji, überlange Texte, Thai-Ziffern, Tempo-Grenzen)."""
import collections
import threading
import types

import pytest

import dolmetscher as d


def _speaker(monkeypatch):
    prepared = []

    class E:
        tts, mute, rate, volume = "edge", False, 0, 1.0

    sp = d.Speaker.__new__(d.Speaker)
    sp.eng, sp.items, sp.cond, sp.busy = E(), collections.deque(), threading.Condition(), False
    monkeypatch.setattr(sp, "_prepare", lambda s, lang, boost: (prepared.append(s), (None, None))[1])
    monkeypatch.setitem(d._QSTATE, "speaker", sp)
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    return sp, prepared


@pytest.mark.parametrize("text", ["", "   ", "!!!", "...", "— — —", "(?)", "😀😀", "👍 ?!"])
def test_nichts_sprechbares_wird_nicht_angefragt(monkeypatch, text):
    sp, prepared = _speaker(monkeypatch)
    sp.add(text, "en", "u1")
    assert sp.items[0]["parts"] == [] and prepared == []


def test_emoji_werden_nicht_vorgelesen():
    assert d.speak_form("Das ist super 😀👍!", "de") == "Das ist super !"
    assert d.speak_form("ขอบคุณ 🙏 ครับ", "th") == "ขอบคุณ ครับ"
    assert d.speak_form("5 °C ☀️", "en").startswith("5 degrees")


def test_thai_ziffern_werden_arabisch():
    assert d.speak_form("ราคา ๑๒๓ บาท", "th") == "ราคา 123 บาท"
    assert "๑" not in d.speak_form("๑๒๓", "th")


def test_thai_abkuerzungen_werden_ausgeschrieben():
    assert "กรุงเทพมหานคร" in d.speak_form("ไป กทม. พรุ่งนี้", "th")
    assert "และอื่นๆ" in d.speak_form("ผลไม้ ส้ม แอปเปิล ฯลฯ", "th")


def test_ueberlanger_text_ohne_satzzeichen_wird_geteilt(monkeypatch):
    sp, prepared = _speaker(monkeypatch)
    sp.add("wort " * 400, "en", "u1")
    parts = [p for p, _ in sp.items[0]["parts"]]
    assert len(parts) > 1 and all(len(p) <= d.MAX_SPEAK_CHARS for p in parts)
    assert " ".join(parts).split() == ["wort"] * 400                 # nichts verloren, kein Wort zerrissen


def test_ueberlanges_thai_ohne_leerzeichen_wird_geteilt():
    out = d.chunk_long(["ก" * 1000], "th")
    assert len(out) > 1 and all(len(p) <= d.MAX_SPEAK_CHARS for p in out) and "".join(out) == "ก" * 1000


def test_kurze_teile_bleiben_unveraendert():
    assert d.chunk_long(["Hello there.", "Bye."], "en") == ["Hello there.", "Bye."]


def test_szenario_tempo_wird_begrenzt(monkeypatch):
    eng = types.SimpleNamespace(rate=0)
    monkeypatch.setattr(d, "_TUNING_SAVED", {})
    d._apply_preset_tuning(eng, {"tuning": {"rate": 999}})
    assert eng.rate == 50
    d._apply_preset_tuning(eng, {"tuning": {"rate": "schnell"}})
    assert eng.rate == 0                                             # zurückgesetzt; „schnell“ ist keine Zahl
