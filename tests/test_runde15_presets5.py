"""Runde 15, fünfte Paketgruppe: Visum, VAT, Werkstatt, Fahrrad, Yoga, Spielplatz, Bäckerei, 7-Eleven, Post, WLAN"""
import json
import pathlib
import re

import pytest

import presets as P

ROOT = pathlib.Path(__file__).resolve().parent.parent
IDS = ["visa-extension", "tax-refund", "car-wash-repair", "bicycle-rental", "yoga-retreat", "kids-playground",
       "bakery-cafe", "convenience-store-7eleven", "post-office-parcel", "wifi-coworking-cafe"]
ALL = {f.stem: json.loads(f.read_text(encoding="utf-8")) for f in (ROOT / "presets").glob("*.json")}


@pytest.mark.parametrize("pid", IDS)
def test_pack_valid_and_sized(pid):
    d = ALL[pid]
    assert P.validate(d) == [] and d["id"] == pid
    assert 16 <= len(d["phrases"]) <= 20
    assert len(d["glossary"]) == 6
    assert d["style"] == "polite"
    assert "maschinell" in d["note"]["de"] and "machine-made" in d["note"]["en"]


@pytest.mark.parametrize("pid", IDS)
def test_critical_first_and_present(pid):
    flags = [bool(p.get("critical")) for p in ALL[pid]["phrases"]]
    assert flags == sorted(flags, reverse=True) and sum(flags) >= 3


@pytest.mark.parametrize("pid", IDS)
def test_thai_neutral(pid):
    for p in ALL[pid]["phrases"]:
        th = p["th"]
        assert "ครับ" not in th and "ค่ะ" not in th and "ฉัน" not in th and not th.startswith("ผม")
        assert not re.search(r"นะ(\s|$)", th)


def test_pack_count_and_web_lists():
    n = len(ALL)                      # Paketzahl dynamisch: Doku muss mitwachsen
    assert n >= 91
    for name in ("index.html", "sw.js"):
        text = (ROOT / name).read_text(encoding="utf-8")
        for pid in IDS:
            assert "'%s'" % pid in text
    assert f"{n} Phrasenpakete" in (ROOT / "docs" / "PRESETS.md").read_text(encoding="utf-8")
    assert f"{n} phrase packs" in (ROOT / "README.md").read_text(encoding="utf-8")


def test_same_english_same_thai():
    seen = {}
    for pid in IDS:
        for p in ALL[pid]["phrases"]:
            seen.setdefault(p["en"], set()).add(p["th"])
    for other, d in ALL.items():
        for p in d["phrases"]:
            if p["en"] in seen:
                seen[p["en"]].add(p["th"])
    assert all(len(v) == 1 for v in seen.values())
