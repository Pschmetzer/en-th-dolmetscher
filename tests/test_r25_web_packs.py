# ruff: noqa: E501
"""Runde 25 (Web): 25 neue Pakete, Thai-Lint (tools/preset_lint.py), Korrekturen, Lautschrift als Probe, Paketzahlen."""
import json
import pathlib
import re
import sys

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import check_presets  # noqa: E402
import preset_lint  # noqa: E402
import preset_rom  # noqa: E402
from _presetlib import load_packs  # noqa: E402

NEW = ["apartment-hunting", "bank-app-otp-help", "bicycle-touring-repair", "car-breakdown-roadside", "car-insurance-claim",
       "childbirth-hospital", "coffee-tea-order", "electricity-water-bill", "glasses-lens-repair", "golf-caddie-tips",
       "kindergarten-daycare", "laundromat-self-service", "massage-prices-booking", "minivan-airport-transfer",
       "muay-thai-stadium", "pet-boarding-flight", "plumber-electrician-aircon", "smoothie-juice-stall",
       "street-food-custom-order", "sunburn-heat-rash", "tdac-arrival-card", "temple-photography",
       "toothache-emergency", "tour-agency-booking", "waste-recycling"]
PACKS = {p.stem: json.loads(p.read_text(encoding="utf-8")) for p in sorted((ROOT / "presets").glob("*.json"))}
INDEX = {p["id"]: p for p in json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))["packs"]}
CATS = json.loads((ROOT / "tools" / "preset_categories.json").read_text(encoding="utf-8"))["categories"]


def test_twentyfive_new_packs_exist_and_total_is_226():
    assert len(NEW) == 25 and set(NEW) <= set(PACKS)
    assert len(PACKS) >= 226 and len(INDEX) == len(PACKS)


@pytest.mark.parametrize("name", NEW)
def test_new_pack_shape_and_index(name):
    d = PACKS[name]
    assert d["style"] == "polite" and 20 <= len(d["phrases"]) <= 50 and len(d["glossary"]) >= 8
    assert sum(1 for p in d["phrases"] if p.get("critical")) >= 5
    flags = [bool(p.get("critical")) for p in d["phrases"]]
    assert flags == sorted(flags, reverse=True)
    assert INDEX[name]["reviewed"] is False and INDEX[name]["phrases"] == len(d["phrases"])
    assert d["note"]["de"].endswith("nicht von Muttersprachlern geprüft.") and d["note"]["en"].endswith("not checked by native speakers.")
    assert any(name in ids for ids in CATS.values())
    assert INDEX[name].get("keywords_de") and INDEX[name].get("keywords_th")


def test_checker_and_linter_are_clean_on_all_packs():
    assert check_presets.run(load_packs()) == []
    res = preset_lint.lint(load_packs())
    assert res == [], res[:5]


def test_lint_catches_typical_machine_errors():
    def rules(en, th):
        return {r for _lv, r, _m in preset_lint.lint_phrase(en, th)}
    assert "register" in rules("Please leave.", "ขอให้ เธอ ไป")
    assert "register" in rules("I am lost.", "ฉันหลงทาง")
    assert "register" in rules("Thanks.", "ขอบคุณนะ")
    assert "clunky" in rules("Please leave me alone.", "ขอให้ปล่อยให้อยู่คนเดียว")
    assert "clunky" in rules("Please wait.", "ช่วยรอด้วยหน่อย")
    assert "digits" in rules("Please call an ambulance (1669).", "ช่วยเรียกรถพยาบาลด้วย (191)")
    assert "digits" in rules("Please call the police (1669).", "ช่วยโทรหาตำรวจ 1669")
    assert "question" in rules("Is it open?", "เปิดอยู่")
    assert "names" in rules("A taxi, please.", "ขอแท็กซี")
    assert rules("Please call the tourist police (1155).", "ช่วยโทรหาตำรวจท่องเที่ยว 1155 ด้วย") == set()
    assert rules("Is it open?", "เปิดอยู่ไหม") == set()


def test_cli_exit_codes(tmp_path):
    good = {"id": "x", "names": {"de": "X", "en": "X", "th": "เอ็กซ์"}, "style": "polite", "phrases": [{"en": "Hello", "th": "สวัสดี"}]}
    bad = dict(good, id="y", phrases=[{"en": "Hello", "th": "ฉันหิว"}])
    (tmp_path / "x.json").write_text(json.dumps(good, ensure_ascii=False), encoding="utf-8")
    assert preset_lint.main(["--dir", str(tmp_path)]) == 0
    (tmp_path / "y.json").write_text(json.dumps(bad, ensure_ascii=False), encoding="utf-8")
    assert preset_lint.main(["--dir", str(tmp_path)]) == 1


CORRECTIONS = {   # Englischer Satz -> gewählte Thai-Fassung (vorher klobig oder doppelt gebeten)
    "Please leave me alone.": "ขออยู่คนเดียว ช่วยอย่ามายุ่งด้วย",
    "Please do not let me sign anything before I read it.": "ขออย่าเพิ่งให้เซ็นอะไรจนกว่าจะได้อ่าน",
    "Please take us to the island and wait.": "ช่วยพาไปที่เกาะแล้วรอด้วย",
    "Please send the file by email as well.": "ช่วยส่งไฟล์ทางอีเมลด้วย",
    "Please keep the group together.": "ช่วยอย่าให้กลุ่มแยกกันหน่อย",
}


@pytest.mark.parametrize("en", sorted(CORRECTIONS))
def test_corrected_sentences_are_used_everywhere(en):
    found = [p["th"] for d in PACKS.values() for p in d["phrases"] if p["en"] == en]
    assert found and set(found) == {CORRECTIONS[en]}


def test_emergency_sentences_are_critical_and_use_right_numbers():
    for name in NEW:
        for p in PACKS[name]["phrases"]:
            for num, word in (("1669", "ambulance"), ("1155", "tourist police"), ("199", "fire brigade")):
                if "(%s)" % num in p["en"]:
                    assert word in p["en"].lower() and num in p["th"], (name, p)
            if re.search(r"call an ambulance|call the police|tourist police|fire brigade", p["en"], re.I) and "will call" not in p["en"]:
                assert p.get("critical"), (name, p["en"])


@pytest.mark.parametrize("name", NEW)
def test_new_pack_rom_is_filled_and_clean(name):
    d = PACKS[name]
    assert preset_rom.check_rom(name + ".json", d) == []
    assert all(isinstance(p.get("rom"), str) and p["rom"] for p in d["phrases"]), name
    for p in d["phrases"]:
        assert not re.search("[฀-๿]", p["rom"]) and len(p["rom"]) <= 300
    assert d["names"]["th"] and not re.search("[A-Za-z]", d["names"]["th"])


def test_rom_tool_splits_words_before_romanizing():
    src = (ROOT / "tools" / "preset_rom.py").read_text(encoding="utf-8")
    assert "word_tokenize" in src and "[฀-๿]" in src


def test_pack_counts_in_docs():
    n = len(PACKS)
    assert n >= 226
    for f in ("README.md", "docs/ARCHITEKTUR.md", "llms.txt", "docs/PRESETS.md", "ios/README.md", "docs/th/README.md", "docs/th/WEB.md"):
        assert "%d " % n in (ROOT / f).read_text(encoding="utf-8"), f
    assert "Web, round 25" in (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    doc = (ROOT / "docs" / "PRESETS.md").read_text(encoding="utf-8")
    assert all("`%s`" % pid in doc for pid in NEW)
