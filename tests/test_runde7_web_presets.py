"""Paketliste (presets-index.json), JSON-Schema, Dubletten ueber Pakete, Not-Saetze (reine Dateipruefung)."""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PACKS = {f.stem: json.loads(f.read_text(encoding="utf-8")) for f in (ROOT / "presets").glob("*.json")}
INDEX = json.loads((ROOT / "presets-index.json").read_text(encoding="utf-8"))
HTML = (ROOT / "index.html").read_text(encoding="utf-8")
SW = (ROOT / "sw.js").read_text(encoding="utf-8")


def _ids(src):
    return re.findall(r"'(\w+)'", re.search(r"const PRESET_IDS = \[(.*?)\]", src, re.S).group(1))


def test_index_matches_folder_and_is_current():
    assert {p["id"] for p in INDEX["packs"]} == set(PACKS)
    r = subprocess.run([sys.executable, str(ROOT / "tools" / "make_presets_index.py"), "--check"], capture_output=True)
    assert r.returncode == 0, "presets-index.json veraltet: python3 tools/make_presets_index.py"
    for p in INDEX["packs"]:
        assert p["phrases"] == len(PACKS[p["id"]]["phrases"]) and isinstance(p["reviewed"], bool)


def test_web_lists_follow_index_order():
    order = [p["id"] for p in INDEX["packs"]]
    assert _ids(HTML) == order and _ids(SW) == order
    assert "'presets-index.json'" in SW


def test_schema_fields_match_validator():
    schema = json.loads((ROOT / "docs" / "presets.schema.json").read_text(encoding="utf-8"))
    src = (ROOT / "presets.py").read_text(encoding="utf-8")
    allowed = set(re.findall(r'"(\w+)"', re.search(r"extra = set\(d\) - \{(.*?)\}", src, re.S).group(1)))
    assert set(schema["properties"]) == allowed
    for d in PACKS.values():
        assert set(d) <= allowed


def test_same_english_same_thai_across_packs():
    seen = {}
    for pid, d in PACKS.items():
        for ph in d["phrases"]:
            seen.setdefault(ph["en"].strip().lower(), {}).setdefault(ph["th"], []).append(pid)
    bad = {en: v for en, v in seen.items() if len(v) > 1}
    assert not bad, f"gleicher englischer Satz mit verschiedenem Thai: {bad}"


def test_safety_relevant_packs_have_critical():
    for pid in ("hotel", "office", "shopping", "temple", "answers", "access", "island", "airport", "dentist"):
        assert any(p.get("critical") for p in PACKS[pid]["phrases"]), pid


def test_new_packs_have_notes_and_mark_machine_thai():
    for pid in ("answers", "services", "island", "access", "coworking", "places", "dentist", "airport", "hotel"):
        n = PACKS[pid]["note"]
        assert "maschinell" in n["de"] and "machine-made" in n["en"], pid
