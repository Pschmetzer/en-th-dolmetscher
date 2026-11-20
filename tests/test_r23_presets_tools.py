"""Runde 23: Suchbegriffe de/th im Index, Feld `rom` (Schema, Validierung, Werkzeug), Suche."""
import json
import pathlib
import sys

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT))
import make_presets_index  # noqa: E402
import preset_rom  # noqa: E402
import preset_search  # noqa: E402
import presets  # noqa: E402
from _presetlib import load_packs  # noqa: E402

KW = json.loads((ROOT / "tools" / "preset_keywords.json").read_text(encoding="utf-8"))["keywords"]
INDEX = {p["id"]: p for p in json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))["packs"]}


def good(**kw):
    d = {"id": "demo", "names": {"de": "Demo", "en": "Demo", "th": "เดโม"}, "style": "polite",
         "phrases": [{"en": "Hello", "th": "สวัสดี"}]}
    d.update(kw)
    return d


def test_index_is_current():
    assert make_presets_index.build() == json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))


@pytest.mark.parametrize("pid", sorted(KW))
def test_keywords_de_th_in_index(pid):
    p = INDEX[pid]
    assert p["keywords_de"] == KW[pid]["de"] and p["keywords_th"] == KW[pid]["th"]
    assert len(p["keywords"]) <= 12 and all(k == k.lower() and k.strip() for k in p["keywords"])
    assert any(any(c in "äöüß" or "฀" <= c <= "๿" for c in k) or k in KW[pid]["de"] for k in p["keywords"])
    assert len(KW[pid]["de"]) >= 3 and len(KW[pid]["th"]) >= 3


def test_search_finds_german_and_thai_keywords():
    packs = load_packs()
    hits = preset_search.search(packs, "unterzucker")
    assert any(h["pack"] == "diabetes-insulin" and h["where"] == "keyword" for h in hits)
    assert any(h["pack"] == "ev-charging" for h in preset_search.search(packs, "ชาร์จรถ"))


def test_rom_is_optional_and_validated():
    assert presets.validate(good()) == []
    assert presets.validate(good(phrases=[{"en": "Hello", "th": "สวัสดี", "rom": "sawatdi"}])) == []
    assert presets.validate(good(phrases=[{"en": "Hello", "th": "สวัสดี", "rom": ""}]))
    assert presets.validate(good(phrases=[{"en": "Hello", "th": "สวัสดี", "rom": 5}]))
    assert presets.validate(good(phrases=[{"en": "Hello", "th": "สวัสดี", "rom": "x" * 301}]))


def test_schema_knows_rom_and_stays_backward_compatible():
    s = json.loads((ROOT / "docs" / "presets.schema.json").read_text(encoding="utf-8"))
    pair = s["definitions"]["pair"]
    assert "rom" in pair["properties"] and "rom" not in pair["required"] and pair["additionalProperties"] is True


def test_rom_tool_fill_check_strip():
    packs = [("demo.json", good(phrases=[{"en": "Hello", "th": "สวัสดี"}, {"en": "Yes", "th": "ใช่", "rom": "chai"}]))]
    assert preset_rom.fill(packs, lambda th: " sa wat  di ") == 1
    ph = packs[0][1]["phrases"]
    assert ph[0]["rom"] == "sa wat di" and ph[1]["rom"] == "chai"
    assert preset_rom.check_rom("demo.json", packs[0][1]) == []
    ph[1]["rom"] = "ไช"
    assert preset_rom.check_rom("demo.json", packs[0][1])
    assert preset_rom.strip(packs) == 2 and all("rom" not in p for p in ph)


def test_rom_tool_check_runs_on_shipped_packs(capsys):
    assert preset_rom.main(["--check"]) == 0
    assert "0 Fehler" in capsys.readouterr().out
