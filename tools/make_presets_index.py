#!/usr/bin/env python3
"""Erzeugt presets-index.json (Paketliste fuer die Web-Version) aus presets/*.json.

Aufruf im Repo-Ordner:  python3 tools/make_presets_index.py          (schreibt die Datei)
                        python3 tools/make_presets_index.py --check  (Exitcode 1, wenn veraltet)
Die Datei liegt bewusst ausserhalb von presets/, damit presets.py und die Apps sie nicht als Paket lesen.
Reihenfolge: ORDER (wichtige zuerst), danach neue Pakete alphabetisch.
`reviewed` = Pruefstatus der Thai-Saetze (false: maschinell, nicht von Muttersprachlern geprueft);
wird beim Neuerzeugen aus der vorhandenen Datei uebernommen.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ORDER = ["doctor", "police", "lostchild", "pharmacy", "dentist", "taxi", "places", "airport", "transport",
         "travel", "hotel", "restaurant", "shopping", "bank", "answers", "access", "spa", "temple", "island",
         "scooter", "rental", "services", "coworking", "office"]


def categories(root=ROOT):
    """{pack_id: category} aus tools/preset_categories.json (health, emergency, transport, food, money, stay, culture,
    leisure, general); ohne Eintrag gilt "general" (ein Test verlangt Vollstaendigkeit)."""
    f = pathlib.Path(root) / "tools" / "preset_categories.json"
    if not f.exists():
        return {}
    data = json.loads(f.read_text(encoding="utf-8"))["categories"]
    return {pid: cat for cat, ids in data.items() for pid in ids}


def build(root=ROOT):
    cats = categories(root)
    old = {}
    f = pathlib.Path(root) / "presets-index.json"
    if f.exists():
        data = json.loads(f.read_text(encoding="utf-8"))
        old = {p["id"]: p.get("reviewed", False) for p in data.get("packs", [])}
    packs = {}
    for p in (pathlib.Path(root) / "presets").glob("*.json"):
        d = json.loads(p.read_text(encoding="utf-8"))
        packs[d["id"]] = {"id": d["id"], "names": d["names"], "phrases": len(d.get("phrases", [])),
                          "critical": sum(1 for x in d.get("phrases", []) if x.get("critical")),
                          "reviewed": old.get(d["id"], False), "category": cats.get(d["id"], "general")}
    ids = [i for i in ORDER if i in packs] + sorted(i for i in packs if i not in ORDER)
    return {"version": 1, "packs": [packs[i] for i in ids]}


if __name__ == "__main__":
    text = json.dumps(build(), ensure_ascii=False, indent=1) + "\n"
    out = ROOT / "presets-index.json"
    if "--check" in sys.argv:
        have = out.read_text(encoding="utf-8") if out.exists() else ""
        if have != text:
            import difflib
            diff = list(difflib.unified_diff(have.splitlines(), text.splitlines(), "presets-index.json (Repo)",
                                             "presets-index.json (neu)", lineterm="", n=1))
            print("presets-index.json veraltet; erste Abweichungen:\n" + "\n".join(diff[:20]), file=sys.stderr)
            sys.exit(1)
        sys.exit(0)
    out.write_text(text, encoding="utf-8")
