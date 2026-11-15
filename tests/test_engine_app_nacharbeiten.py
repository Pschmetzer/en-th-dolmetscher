"""Engine-App-Nacharbeiten: Fehlercode beim Profil-Laden, `speak_text` (nur vorlesen), englische Zahlwörter."""
import json
import sys
import types

import pytest

import dolmetscher as d


def _eng():
    e = types.SimpleNamespace(translate_dir={"en": True, "th": True}, lock="auto", polite="krub", mute=False,
                              paused=False, rate=0, volume=1.0, voices={"en": None, "th": None}, earcons=False)
    e.stop_speaking = lambda: None
    e.spoken = []
    e.speak_text = lambda t, lg, uid=None: e.spoken.append((t, lg, uid))
    return e


# ---- Profil-Ladefehler mit Code -------------------------------------------------------------------

def test_reload_profiles_error_has_code(monkeypatch):
    ev = []
    monkeypatch.setattr(d, "emit", lambda event, **kw: ev.append((event, kw)))
    broken = types.ModuleType("profiles")

    def boom():
        raise RuntimeError("Modell fehlt")
    broken.list_profiles = boom
    monkeypatch.setitem(sys.modules, "profiles", broken)
    e = d.Engine.__new__(d.Engine)
    e.spk, e.two_person = None, True
    e.reload_profiles()
    err = [kw for name, kw in ev if name == "error"]
    assert err and err[0]["code"] == "profiles_failed" and "Modell fehlt" in err[0]["msg"]
    assert e.spk is None and ("roles", {"me": None, "on": False}) in ev


# ---- speak_text: fertigen Text nur vorlesen -------------------------------------------------------

def test_speak_text_runs_immediately_not_as_job():
    e = _eng()
    assert d.apply_control(e, {"speak_text": {"text": " Where is the station? ", "lang": "en", "id": "u7"}}) is None
    assert e.spoken == [("Where is the station?", "en", "u7")]
    assert e.mute is False                         # nicht mit dem bool-Feld `speak` verwechselt
    d.apply_control(e, {"speak_text": {"text": "สวัสดีครับ", "lang": "th"}})
    assert e.spoken[-1] == ("สวัสดีครับ", "th", None)


@pytest.mark.parametrize("arg", [
    {"text": "", "lang": "en"}, {"text": "x" * 5000, "lang": "en"}, {"text": "hi", "lang": "de"},
    {"text": "hi", "lang": "en", "id": 5}, {"text": "hi", "lang": "en", "id": "x" * 65},
])
def test_speak_text_invalid(monkeypatch, arg):
    ev = []
    monkeypatch.setattr(d, "emit", lambda event, **kw: ev.append((event, kw)))
    e = _eng()
    d.apply_control(e, {"speak_text": arg})
    assert not e.spoken and ev and ev[0][0] == "error" and ev[0][1]["code"] == "speak_invalid"


def test_speak_text_adds_to_speaker_with_id():
    calls = []
    e = d.Engine.__new__(d.Engine)
    e.speaker = types.SimpleNamespace(add=lambda *a, **kw: calls.append((a, kw)))
    e.speak_text("Hello", "en", "u9")
    e.speak_text("Hello", "en")
    assert calls[0] == (("Hello", "en", "u9"), {})
    assert calls[1][0][2].startswith("u")          # ohne id: neue id


def test_speak_text_not_logged_without_log_text(monkeypatch):
    logged = []
    monkeypatch.setattr(d, "log", lambda x: logged.append(x))
    monkeypatch.setattr(d, "LOG_TEXT", False)
    monkeypatch.setattr(d, "_BAD_JSON", {"n": 0, "t": 0.0})
    monkeypatch.setattr(d.sys, "stdin", iter([json.dumps({"speak_text": {"text": "geheim", "lang": "en"}}) + "\n"]))
    d.STOP.clear()
    d.control_loop(_eng())
    assert d.STOP.wait(3)
    d.STOP.clear()
    assert "geheim" not in json.dumps(logged, ensure_ascii=False)


# ---- englische Zahlwörter ---------------------------------------------------------------------------

@pytest.mark.parametrize("words, digits", [
    ("three hundred fifty", "350"), ("three hundred and fifty", "350"), ("twenty-five", "25"),
    ("two thousand five hundred", "2500"), ("fifteen hundred", "1500"), ("Five Million", "5000000"),
    ("one million two hundred thousand", "1200000"),
    ("one fifty", "one fifty"), ("two thirty", "two thirty"),    # Preis oder Uhrzeit? unklar: bleibt
    ("someone", "someone"), ("a hundred", "a hundred"),
])
def test_en_words_to_digits(words, digits):
    assert d.en_words_to_digits(words) == digits


@pytest.mark.parametrize("a, b, differ", [
    ("That costs three hundred fifty baht", "ราคา 350 บาท", False),
    ("That costs three hundred fifty baht", "ราคา 530 บาท", True),
    ("room twenty-five", "ห้อง 52", True),
    ("five million baht", "5 ล้านบาท", False),
    ("three hundred fifty baht", "สามร้อยห้าสิบบาท", False),      # Wörter auf beiden Seiten
    ("three hundred fifty baht", "ห้าร้อยสามสิบบาท", True),
    ("no one is here, 350 baht", "ไม่มีใคร 350 บาท", False),        # "one" einstellig: zählt nicht
    ("one fifty", "150", False),                                   # unklar: kein Vergleich
])
def test_numbers_differ_english_words(a, b, differ):
    assert d.numbers_differ(a, b) is differ
