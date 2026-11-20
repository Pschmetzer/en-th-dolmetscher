"""Runde 21, Welle 2: neue Phrasenpakete sind vollständig verdrahtet (Kategorie, Index, Doku, Web, Service Worker)."""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
NEW = ["tattoo-piercing", "driving-license", "bank-account-opening", "long-term-lease", "pregnancy-maternity",
       "drone-camera-rules", "fruit-market-durian", "songkran-water-festival", "private-driver-day-tour",
       "luggage-storage", "grand-palace-museum"]
SAFETY = ["tattoo-piercing", "pregnancy-maternity", "drone-camera-rules", "songkran-water-festival"]


def _pack(i):
    return json.loads((ROOT / "presets" / f"{i}.json").read_text(encoding="utf-8"))


def test_new_packs_have_machine_note_and_enough_phrases():
    for i in NEW:
        d = _pack(i)
        assert d["id"] == i and len(d["phrases"]) >= 14 and len(d["glossary"]) >= 6
        assert "maschinell" in d["note"]["de"] and "machine-made" in d["note"]["en"]


def test_safety_packs_mark_critical_sentences():
    for i in SAFETY:
        assert any(p.get("critical") for p in _pack(i)["phrases"]), i


def test_new_packs_in_exactly_one_category_and_index():
    cats = json.loads((ROOT / "tools" / "preset_categories.json").read_text(encoding="utf-8"))["categories"]
    idx = json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))
    text = json.dumps(idx)
    for i in NEW:
        assert sum(i in v for v in cats.values()) == 1, i
        assert f'"{i}"' in text


def test_new_packs_listed_for_web_and_docs():
    html = (ROOT / "index.html").read_text(encoding="utf-8")
    sw = (ROOT / "sw.js").read_text(encoding="utf-8")
    doc = (ROOT / "docs" / "PRESETS.md").read_text(encoding="utf-8")
    for i in NEW:
        assert f"'{i}'" in html and f"'{i}'" in sw and f"`{i}`" in doc
