"""Runde 8 (Cloud A): acht neue Phrasenpakete – Schema, Umfang, kritische Sätze zuerst, einheitliches Thai."""
import json
import pathlib
import re

import pytest

import presets as P

ROOT = pathlib.Path(__file__).resolve().parent.parent
IDS = ["bus-train", "beach", "hiking", "street-food", "massage", "nightlife", "festival", "laundry-repair"]
PACKS = {i: json.loads((ROOT / "presets" / f"{i}.json").read_text(encoding="utf-8")) for i in IDS}
OTHER = {f.stem: json.loads(f.read_text(encoding="utf-8")) for f in (ROOT / "presets").glob("*.json")
         if f.stem not in IDS}
THAI = re.compile(r"[฀-๿]")


@pytest.mark.parametrize("pid", IDS)
def test_valid_and_id_matches_file(pid):
    assert P.validate(PACKS[pid]) == [], P.validate(PACKS[pid])
    assert PACKS[pid]["id"] == pid


@pytest.mark.parametrize("pid", IDS)
def test_size_note_glossary(pid):
    d = PACKS[pid]
    assert 16 <= len(d["phrases"]) <= 20
    assert len(d["glossary"]) == 6
    assert d["style"] == "polite"
    assert d["note"]["de"] and d["note"]["en"]
    assert "maschinell erstellt, nicht von Muttersprachlern geprüft" in d["note"]["de"]
    assert "machine-made, not checked by native speakers" in d["note"]["en"]


@pytest.mark.parametrize("pid", IDS)
def test_critical_first_and_present(pid):
    flags = [bool(ph.get("critical")) for ph in PACKS[pid]["phrases"]]
    assert flags == sorted(flags, reverse=True)
    assert any(flags)


@pytest.mark.parametrize("pid", IDS)
def test_thai_rules_and_no_duplicates(pid):
    phr = PACKS[pid]["phrases"]
    for ph in phr:
        th = ph["th"]
        assert "ครับ" not in th and "ค่ะ" not in th and "ฉัน" not in th and not th.startswith("ผม"), th
        assert not re.search(r"นะ(\s|$)", th), th
        assert THAI.search(th) and not THAI.search(ph["en"])
    for lang in ("en", "th"):
        vals = [x[lang].strip().lower() for x in phr]
        assert len(vals) == len(set(vals)), (pid, lang)


def test_same_english_same_thai_as_existing_packs():
    known = {}
    for d in OTHER.values():
        for ph in d["phrases"]:
            known.setdefault(ph["en"], ph["th"])
    for pid, d in PACKS.items():
        for ph in d["phrases"]:
            if ph["en"] in known:
                assert ph["th"] == known[ph["en"]], (pid, ph["en"])


def test_same_english_same_thai_between_new_packs():
    seen = {}
    for pid, d in PACKS.items():
        for ph in d["phrases"]:
            assert seen.setdefault(ph["en"], ph["th"]) == ph["th"], (pid, ph["en"])


def test_ids_are_new_and_listed_in_index():
    assert not set(IDS) & set(OTHER)
    index = {p["id"]: p for p in json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))["packs"]}
    for pid in IDS:
        assert index[pid]["phrases"] == len(PACKS[pid]["phrases"])
        assert index[pid]["critical"] == sum(1 for p in PACKS[pid]["phrases"] if p.get("critical"))
        assert index[pid]["reviewed"] is False
