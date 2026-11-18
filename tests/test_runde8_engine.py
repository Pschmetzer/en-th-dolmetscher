"""Runde 8 (Engine): Glossar-Parser, Zahlen-Normalisierung, sprechbare Währungs-/Gradzeichen."""
import pytest

import dolmetscher as d


@pytest.fixture
def glossary(tmp_path, monkeypatch):
    monkeypatch.setattr(d, "GLOSSARY_FILE", str(tmp_path / "glossary.txt"))
    monkeypatch.setattr(d, "GLOSSARY", [])
    monkeypatch.setattr(d, "_GLOSSARY_OWN", None)
    return d


def test_glossary_skips_comments_bom_and_duplicates(glossary):
    glossary.load_glossary("﻿# meine Namen\nPat\nHello => สวัสดี\nhello => ดี\n  # eingerückt\nPAT\n")
    assert d.GLOSSARY == [("Pat", None), ("Hello", "สวัสดี")]


def test_glossary_drops_sentence_sized_entries(glossary):
    d.load_glossary("x" * 200 + "\nOk => " + "y" * 200 + "\nGut\n")
    assert d.GLOSSARY == [("Gut", None)]


def test_learned_names_ignore_comment_lines(glossary, monkeypatch):
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    monkeypatch.setattr(d, "set_preset", lambda *a, **k: None)
    d.load_glossary("# Pat\nSomchai\n")
    assert d.learn_glossary_names(None, ["Pat"]) == ["Pat"]


def test_pronounce_skips_comments_and_duplicates(tmp_path, monkeypatch):
    f = tmp_path / "p.txt"
    f.write_text("﻿# x\nPat => Pät\npat => Paat\nbad line\n", encoding="utf-8")
    monkeypatch.setattr(d, "PRONOUNCE", [])
    d.load_pronounce(str(f))
    assert d.PRONOUNCE == [("Pat", "Pät")]


@pytest.mark.parametrize("a,b", [
    ("1 500", "1500"), ("12 345 678", "12,345,678"), ("1 500 baht", "1.500 บาท"),
    ("5 hundred", "500"), ("3 ร้อย", "สามร้อย"), ("2 lakh", "200,000"), ("1 crore", "10000000"),
])
def test_equivalent_numbers_do_not_differ(a, b):
    assert not d.numbers_differ(a, b)


def test_space_grouping_does_not_hide_real_differences():
    assert d.numbers_differ("1 500", "1600")
    assert d._numbers("081 234 5678") == ["234", "5678", "81"]     # Telefon: führende Null, keine Gruppe
    assert d._numbers("2026 12 25") == ["12", "2026", "25"]         # Datum bleibt getrennt


def test_speak_form_currency_and_degrees():
    assert d.speak_form("It costs ฿1,500. Then $5.", "en") == "It costs 1,500 baht. Then 5 dollars."
    assert d.speak_form("ราคา ฿ 300", "th") == "ราคา 300 บาท"
    assert d.speak_form("25°C", "en") == "25 degrees Celsius"
    assert d.speak_form("30°C", "th") == "30 องศาเซลเซียส"
    assert d.speak_form("98 °F", "de") == "98 Grad Fahrenheit"
    assert d.speak_form("฿5", "ja") == "฿5"                          # keine Tabelle: unverändert


def test_history_search_short_query_ignores_case_beyond_ascii(tmp_path):
    import history_store as h
    s = h.Store(str(tmp_path / "h.sqlite"))
    s.add("É bom", "good", "pt")
    s.add("Über die Brücke", "Over the bridge", "de")
    assert [r["text"] for r in s.search("é")] == ["É bom"]
    assert [r["text"] for r in s.search("Ü")] == ["Über die Brücke"]
    assert s.search("100%") == []                  # Platzhalter werden nicht als Muster gelesen
    s.close()
