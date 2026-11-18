"""Runde 11 (Engine): Höflichkeitsstufe (`formality`), Sprechergeschlecht (`speaker_sex`), Thai-Partikel."""
import pathlib
import types

import pytest

import dolmetscher as d

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = (ROOT / "docs" / "PROTOKOLL.md").read_text(encoding="utf-8")


@pytest.fixture(autouse=True)
def _reset():
    old = d.LLM["formality"]
    yield
    d.LLM["formality"] = old


def test_auto_bleibt_wie_bisher():
    assert d.register_hint("de", "casual") == d.register_hint("de", "casual", "auto")
    assert "use du" in d.register_hint("de", "casual", "auto")
    assert "use Sie" in d.register_hint("de", "polite", "auto")
    assert d.register_hint("th", "casual", "auto") == ""


@pytest.mark.parametrize("dst,lvl,part", [
    ("de", "informal", "use du"), ("de", "neutral", "use Sie"), ("fr", "informal", "use tu"),
    ("fr", "polite", "use vous"), ("es", "informal", "use tú"), ("es", "polite", "use usted"),
    ("ja", "informal", "no keigo"), ("ja", "neutral", "teineigo"), ("ja", "polite", "sonkeigo"),
    ("ko", "informal", "반말"), ("ko", "polite", "합쇼체"),
    ("th", "informal", "casual spoken Thai"), ("th", "polite", "courteous Thai"),
])
def test_stufen_je_zielsprache(dst, lvl, part):
    assert part in d.register_hint(dst, "neutral", lvl)


def test_formality_schlaegt_style():
    assert "use du" in d.register_hint("de", "polite", "informal")
    assert d.effective_formality("casual") == "informal"
    assert d.effective_formality("polite", "neutral") == "neutral"


def test_sprachen_ohne_anrede_leer():
    assert d.register_hint("en", "neutral", "polite") == ""


def test_partikel_zu_krub():
    assert d.fit_thai_particles("ขอบคุณค่ะ", "krub") == "ขอบคุณครับ"
    assert d.fit_thai_particles("ไปไหนคะ", "krub") == "ไปไหนครับ"


def test_partikel_zu_ka_frage_und_aussage():
    assert d.fit_thai_particles("ขอบคุณครับ", "ka") == "ขอบคุณค่ะ"
    assert d.fit_thai_particles("ไปไหนครับ", "ka") == "ไปไหนคะ"
    assert d.fit_thai_particles("ราคาเท่าไหร่ครับ", "ka") == "ราคาเท่าไหร่คะ"


def test_partikel_unveraendert():
    assert d.fit_thai_particles("ขอบคุณครับ", "krub") == "ขอบคุณครับ"
    assert d.fit_thai_particles("สวัสดี", "ka") == "สวัสดี"
    assert d.fit_thai_particles("เขาพูดว่า ครับ แล้วเธอตอบว่า ค่ะ", "ka") == "เขาพูดว่า ครับ แล้วเธอตอบว่า ค่ะ"
    assert d.fit_thai_particles("", "ka") == ""


def test_partikel_ignoriert_komposita():
    assert d.fit_thai_particles("คะแนนเต็ม", "krub") == "คะแนนเต็ม"
    assert d.fit_thai_particles("บังคับใช้ ค่ะ", "krub") == "บังคับใช้ ครับ"
    assert d.fit_thai_particles("บังคับใช้ ครับ", "ka") == "บังคับใช้ ค่ะ"


def test_cache_key_trennt_stufen():
    d.LLM["formality"] = "auto"
    a = d._cache_key("hi", "en", "de", True, "krub")
    d.LLM["formality"] = "polite"
    b = d._cache_key("hi", "en", "de", True, "krub")
    assert a != b
    assert d._cache_key("hi", "en", "de", False, "krub")[3] == "mt"


def test_steuerfelder_dokumentiert_und_bekannt():
    for k in ("formality", "speaker_sex"):
        assert k in d.CTRL_KEYS and k in d.CTRL_LOG_KEYS
        assert f"`{k}`" in DOCS
    assert "abwärtskompatibel" in DOCS or "ignoriert" in DOCS


def _eng():
    return types.SimpleNamespace(translate_dir={"en": True, "th": True}, lock="auto", polite="krub", mute=False,
                                 paused=False, rate=0, volume=1.0, voices={"en": None, "th": None}, earcons=False,
                                 beam=1)


def test_apply_control_formality_und_sprechergeschlecht(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    eng = _eng()
    d.apply_control(eng, {"formality": "polite", "speaker_sex": "female"})
    assert d.LLM["formality"] == "polite" and eng.polite == "ka"
    d.apply_control(eng, {"speaker_sex": "male"})
    assert eng.polite == "krub"
    d.apply_control(eng, {"formality": "sehr", "speaker_sex": 3})      # ungültig: Wert bleibt, Meldung
    assert d.LLM["formality"] == "polite" and eng.polite == "krub"
    assert sum(1 for e, _ in events if e == "control_invalid") == 2
    d.apply_control(eng, {"polite": "ka"})                             # altes Feld unverändert
    assert eng.polite == "ka"
    assert not [e for e, _ in events if e == "control_ignored"]
