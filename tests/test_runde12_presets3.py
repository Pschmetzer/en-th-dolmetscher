"""Runde 12, dritte Paketgruppe: Geldautomat, 90-Tage-Meldung, Unfall, Reisepass, Schneider, Tuk-Tuk, Kochkurs, ..."""
import json
import pathlib
import re

import pytest

import presets as P

ROOT = pathlib.Path(__file__).resolve().parent.parent
IDS = ["atm-bank-card", "immigration-90day", "motorbike-accident", "lost-passport", "tailor-custom",
       "tuk-tuk-songthaew", "thai-cooking-class", "elephant-sanctuary", "cinema-concert", "dating-small-talk"]
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
    assert len(ALL) == 71
    for name in ("index.html", "sw.js"):
        text = (ROOT / name).read_text(encoding="utf-8")
        for pid in IDS:
            assert "'%s'" % pid in text
    assert "71 Phrasenpakete" in (ROOT / "docs" / "PRESETS.md").read_text(encoding="utf-8")
    assert "71 phrase packs" in (ROOT / "README.md").read_text(encoding="utf-8")
