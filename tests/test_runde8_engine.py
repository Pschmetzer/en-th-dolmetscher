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
    assert d._numbers("081 234 5678") == ["812345678"]             # Telefon: eine Nummer (Runde 9)
    assert d._numbers("2026 12 25") == ["12", "2026", "25"]         # Datum bleibt getrennt


def test_speak_form_currency_and_degrees():
    assert d.speak_form("It costs ฿1,500. Then $5.", "en") == "It costs 1,500 baht. Then 5 dollars."
    assert d.speak_form("ราคา ฿ 300", "th") == "ราคา 300 บาท"
    assert d.speak_form("25°C", "en") == "25 degrees Celsius"
    assert d.speak_form("30°C", "th") == "30 องศาเซลเซียส"
    assert d.speak_form("98 °F", "de") == "98 Grad Fahrenheit"
    assert d.speak_form("฿5", "sv") == "฿5"                          # keine Tabelle: unverändert


def test_history_search_short_query_ignores_case_beyond_ascii(tmp_path):
    import history_store as h
    s = h.Store(str(tmp_path / "h.sqlite"))
    s.add("É bom", "good", "pt")
    s.add("Über die Brücke", "Over the bridge", "de")
    assert [r["text"] for r in s.search("é")] == ["É bom"]
    assert [r["text"] for r in s.search("Ü")] == ["Über die Brücke"]
    assert s.search("100%") == []                  # Platzhalter werden nicht als Muster gelesen
    s.close()


def test_thai_laugh_after_a_number_is_not_a_digit_group():
    assert not d.numbers_differ("ราคา 100 555", "price 100 haha")
    assert d._numbers("2 555 000") == ["2555000"]


# ---- Text-Echo-Schutz ------------------------------------------------------------------------------------------

@pytest.fixture
def echo(monkeypatch):
    monkeypatch.setattr(d, "_SPOKEN", __import__("collections").deque(maxlen=8))
    monkeypatch.setitem(d.ECHO, "on", True)
    return d


def test_echo_of_own_voice_is_detected(echo):
    d.note_spoken("Where is the nearest pharmacy?", "en", now=100.0)
    assert d.is_echo("where is the nearest pharmacy", "en", now=103.0)
    assert d.is_echo("Where is the nearest pharmacy please", "en", now=103.0)


def test_echo_needs_same_language_recent_and_long_enough(echo):
    d.note_spoken("Where is the nearest pharmacy?", "en", now=100.0)
    assert not d.is_echo("Where is the nearest pharmacy?", "th", now=101.0)
    assert not d.is_echo("Where is the nearest pharmacy?", "en", now=100.0 + d.ECHO_WINDOW_S + 1)
    assert not d.is_echo("Where is the nearest bank?", "en", now=101.0)
    d.note_spoken("Thank you", "en", now=100.0)
    assert not d.is_echo("Thank you", "en", now=101.0)          # kurze Sätze sind oft echte Wiederholungen


def test_echo_guard_can_be_switched_off(echo, monkeypatch):
    d.note_spoken("Where is the nearest pharmacy?", "en", now=100.0)
    monkeypatch.setitem(d.ECHO, "on", False)
    assert not d.is_echo("Where is the nearest pharmacy?", "en", now=101.0)


def test_echo_thai_without_spaces(echo):
    d.note_spoken("ร้านขายยาที่ใกล้ที่สุดอยู่ที่ไหนคะ", "th", now=10.0)
    assert d.is_echo("ร้านขายยาที่ใกล้ที่สุดอยู่ที่ไหน", "th", now=12.0)


def test_echo_control_and_state(echo, monkeypatch):
    eng = d.Engine.__new__(d.Engine)
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    d.apply_control(eng, {"echo_guard": False})
    assert d.ECHO["on"] is False
    d.apply_control(eng, {"echo_guard": True})
    assert d.ECHO["on"] is True and "echo_guard" in d.CTRL_KEYS
    assert d.drop_code("echo") == "other"


def test_process_drops_echo(echo, monkeypatch):
    import numpy as np
    from test_engine_pipeline import _engine
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    monkeypatch.setitem(d.LLM, "on", False)
    e = _engine([("en", 0.95)], {"en": ("Where is the nearest pharmacy?", -0.2), "th": ("x", -2.0)})
    d.note_spoken("Where is the nearest pharmacy?", "en")
    e.process(np.full(d.SR * 2, 0.05, dtype=np.float32), speak=False, uid="e1")
    drop = [kw for n, kw in events if n == "dropped"]
    assert drop and drop[0]["reason"] == "echo" and drop[0]["code"] == "other" and "heard" not in [n for n, _ in events]


def test_split_sentences_keeps_abbreviations_together():
    t = "The office is open from 9 a.m. to 5 p.m. every day and we also close for lunch on Sunday afternoon."
    assert d.split_sentences(t, "en") == [t]
    t = "Please ask Prof. Brown about it, he is here. They are in room no. 5 near the lobby of the main building."
    out = d.split_sentences(t, "en")
    assert out[0].endswith("he is here.") and out[1].startswith("They are")
    t = "Es kostet ca. 500 Baht, z. B. mit Frühstück und Abendessen. Das ist günstig und die Lage ist sehr gut hier."
    assert d.split_sentences(t, "de")[0].endswith("Abendessen.")
    assert d.split_sentences("Wait. Then go. Now please leave the building quickly and quietly, thank you.", "en")


def test_connection_errors_cover_body_read_failures():
    import http.client
    import json
    import socket
    import urllib.error
    for e in (socket.gaierror(8, "x"), ConnectionResetError(), TimeoutError(), http.client.IncompleteRead(b""),
              http.client.RemoteDisconnected("x"), urllib.error.URLError("x")):
        assert d._is_conn_error(e), type(e).__name__
    assert not d._is_conn_error(urllib.error.HTTPError("u", 503, "x", {}, None))
    assert not d._is_conn_error(json.JSONDecodeError("x", "", 0))


def test_truncated_response_backs_the_provider_off(monkeypatch):
    import http.client
    monkeypatch.setattr(d, "_PROV", {"google": {"fails": 0, "until": 0.0}})
    d._note_fail("google", http.client.IncompleteRead(b"ab"))
    assert d._PROV["google"]["fails"] == 1 and d._PROV["google"]["until"] > 0


def test_space_grouping_never_creates_a_difference():
    assert not d.numbers_differ("2 100 baht each", "2 ชิ้น ชิ้นละ 100 บาท")


def test_echo_keeps_thai_tone_marks():
    import collections
    d._SPOKEN = collections.deque(maxlen=8)
    d.note_spoken("ร้านนี้อร่อยมากเลยค่ะ", "th", now=5.0)
    assert d.is_echo("ร้านนี้อร่อยมากเลยค่ะ", "th", now=6.0)
    assert d._echo_norm("ร้านนี้ ค่ะ!") == "ร้านนี้ค่ะ"


def test_sentence_ending_no_still_splits():
    t = "No. I do not want it at all, thank you very much. Please take it away from the table now."
    assert d.split_sentences(t, "en")[0] == "No. I do not want it at all, thank you very much."
    t = "Room no. 5 is on the left side of the corridor. Please take the stairs next to the lobby."
    assert d.split_sentences(t, "en")[0].startswith("Room no. 5 is")
