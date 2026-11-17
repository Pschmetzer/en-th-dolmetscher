"""Inhalt und Schema der mitgelieferten Phrasenpakete (presets/*.json): note, critical, Höflichkeit, Dubletten."""
import json
import pathlib
import re

import pytest

import dolmetscher as D
import presets as P

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = sorted((ROOT / "presets").glob("*.json"))
PACKS = {f.stem: json.loads(f.read_text(encoding="utf-8")) for f in FILES}
NEW = {"pharmacy", "police", "bank", "spa", "temple", "rental", "scooter", "transport", "lostchild"}
THAI = re.compile(r"[฀-๿]")


def good(**kw):
    d = {"id": "demo", "names": {"de": "Demo", "en": "Demo", "th": "เดโม"}, "style": "polite",
         "glossary": [{"en": "room", "th": "ห้อง"}], "phrases": [{"en": "Hello", "th": "สวัสดี"}]}
    d.update(kw)
    return d


@pytest.mark.parametrize("name", sorted(PACKS))
def test_file_valid_and_id_matches(name):
    d = PACKS[name]
    assert P.validate(d) == [], P.validate(d)
    assert d["id"] == name


def test_new_packs_shipped_with_note_and_size():
    assert NEW <= set(PACKS)
    for pid in NEW:
        d = PACKS[pid]
        assert 15 <= len(d["phrases"]) <= 25, pid
        assert d["note"]["de"] and d["note"]["en"], pid
        assert d["style"] == "polite", pid


@pytest.mark.parametrize("name", sorted(PACKS))
def test_thai_polite_neutral(name):
    for ph in PACKS[name]["phrases"]:
        th = ph["th"]
        assert "ครับ" not in th and "ค่ะ" not in th, th                         # Partikel setzt die Engine
        assert "ฉัน" not in th and not th.startswith("ผม"), th                  # Pronomen weglassen = neutral
        assert not re.search(r"นะ(\s|$)", th), th                              # „นะ“ zu vertraut
        assert THAI.search(th), th
        assert not THAI.search(ph["en"]), ph["en"]


@pytest.mark.parametrize("name", sorted(PACKS))
def test_no_duplicates(name):
    d = PACKS[name]
    for key in ("phrases", "glossary"):
        for lang in ("en", "th"):
            vals = [x[lang].strip().lower() for x in d[key]]
            dup = {v for v in vals if vals.count(v) > 1}
            assert not dup, (name, key, lang, dup)


@pytest.mark.parametrize("name", sorted(PACKS))
def test_critical_first(name):
    flags = [bool(ph.get("critical")) for ph in PACKS[name]["phrases"]]
    assert flags == sorted(flags, reverse=True), name


@pytest.mark.parametrize("name", ["doctor", "police", "lostchild", "pharmacy", "restaurant", "travel"])
def test_safety_packs_have_critical(name):
    crit = [ph for ph in PACKS[name]["phrases"] if ph.get("critical") is True]
    assert len(crit) >= 3, name


def test_emergency_numbers():
    assert any("1669" in ph["th"] for ph in PACKS["doctor"]["phrases"] if ph.get("critical"))
    assert any("1155" in ph["th"] for ph in PACKS["police"]["phrases"] if ph.get("critical"))
    assert "1669" in PACKS["doctor"]["note"]["de"]


def test_temple_note_covers_etiquette():
    de = PACKS["temple"]["note"]["de"]
    for word in ("Schultern", "Schuhe", "Wai", "Trinkgeld"):
        assert word in de


def test_lostchild_blanks_are_plain():
    phr = PACKS["lostchild"]["phrases"]
    assert sum("___" in ph["th"] for ph in phr) >= 5
    assert all("{" not in ph["th"] and "{" not in ph["en"] for ph in phr)     # kein Platzhalter-Format
    assert all(("___" in ph["en"]) == ("___" in ph["th"]) for ph in phr)


@pytest.mark.parametrize("patch", [
    {"note": "Text"}, {"note": {"de": "x"}}, {"note": {"de": "x", "en": ""}},
    {"note": {"de": "x", "en": "y", "fr": "z"}}, {"note": {"de": "x" * 501, "en": "y"}},
    {"note": {"de": "x", "en": "y", "th": 3}},
    {"phrases": [{"en": "a", "th": "ก", "critical": "yes"}]}, {"phrases": [{"en": "a", "th": "ก", "critical": 1}]},
])
def test_validate_rejects_new_fields(patch):
    assert P.validate(good(**patch))


def test_validate_accepts_new_fields_and_old_format():
    assert P.validate(good()) == []                                   # abwärtskompatibel: ohne note/critical
    assert P.validate(good(note={"de": "Hinweis", "en": "Note"},
                           phrases=[{"en": "Help!", "th": "ช่วยด้วย", "critical": True},
                                    {"en": "Hi", "th": "สวัสดี", "critical": False}])) == []
    assert P.validate(good(note={"de": "a", "en": "b", "th": "ค"})) == []


@pytest.mark.parametrize("text, key", [
    ("police mode", "preset:police"), ("preset pharmacy", "preset:pharmacy"), ("lost child mode", "preset:lostchild"),
    ("temple mode", "preset:temple"), ("preset scooter", "preset:scooter"),
])
def test_voice_command_new_packs(text, key):
    assert D.parse_command(text) == key


def test_docs_list_every_pack():
    doc = (ROOT / "docs" / "PRESETS.md").read_text(encoding="utf-8")
    assert "muttersprachlich prüfen" in doc
    for pid in PACKS:
        assert f"`{pid}`" in doc, pid
