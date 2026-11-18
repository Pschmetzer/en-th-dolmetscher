"""Runde 8, zweite Paketgruppe: Mietwagen, Haustiere, Baby, Fitness, Hochzeit, Foto, Moenche, Krankenhaus."""
import json
import pathlib
import re

import pytest

import presets as P

ROOT = pathlib.Path(__file__).resolve().parent.parent
IDS = ["car-rental", "pets", "baby", "gym", "wedding", "photo", "monk", "hospital"]
ALL = {f.stem: json.loads(f.read_text(encoding="utf-8")) for f in (ROOT / "presets").glob("*.json")}


@pytest.mark.parametrize("pid", IDS)
def test_pack_valid_and_sized(pid):
    d = ALL[pid]
    assert P.validate(d) == [] and d["id"] == pid
    assert 16 <= len(d["phrases"]) <= 20
    assert len(d["glossary"]) == 6
    assert d["style"] == "polite"
    assert d["note"]["de"] and d["note"]["en"]
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


def test_same_english_same_thai_with_other_packs():
    seen = {}
    for pid, d in ALL.items():
        for p in d["phrases"]:
            seen.setdefault(p["en"].strip().lower(), set()).add(p["th"])
    assert not {k: v for k, v in seen.items() if len(v) > 1}
