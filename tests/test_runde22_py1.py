"""Runde 22 (py1): Pfad-Maskierung, Sprechform von Währung/Grad, Glossar-Namen, Konsole ohne Absturz."""
import io
import contextlib

import pytest

import dolmetscher as d


def test_scrub_home_nur_ganzer_pfadteil(monkeypatch):
    monkeypatch.setenv("HOME", "/Users/x")
    assert d._scrub("/Users/xavier/a") == "/Users/<user>/a"
    assert d._scrub("/Users/x/b") == "~/b"
    assert d._scrub("fehler in /Users/x") == "fehler in ~"


@pytest.mark.parametrize("text,lang,want", [
    ("Das kostet 5€", "de", "5 Euro"), ("It costs 500฿", "en", "500 baht"),
    ("It is 20° outside", "en", "20 degrees"), ("Es ist 25°C", "de", "25 Grad Celsius"),
    ("room 5€x", "en", "room 5€x")])
def test_speak_form_nachgestellt(text, lang, want):
    assert want in d.speak_form(text, lang)


def test_speak_form_vorangestellt_bleibt():
    assert d.speak_form("฿1,500", "en") == "1,500 baht"


def test_learn_glossary_names_filtert_zeilen(monkeypatch, tmp_path):
    monkeypatch.setattr(d, "GLOSSARY_FILE", str(tmp_path / "g.txt"))
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    d.PRESET.active = None
    got = d.learn_glossary_names(None, ["Somchai", "a\nb", "x => y", "#Kommentar", "  Nok  ", "z" * 500])
    assert got == ["Somchai", "Nok"]
    d.load_glossary("")


def test_emit_konsole_ohne_felder(monkeypatch):
    monkeypatch.setattr(d, "JSON", False)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        d._emit("utt", lang="en")
    assert "EN" in buf.getvalue()


def test_json_line_scrubt_verschachtelt(monkeypatch):
    monkeypatch.setenv("HOME", "/Users/x")
    line = d._json_line("error", {"files": ["/Users/x/p.json"]})
    assert "/Users/x" not in line and "~/p.json" in line
