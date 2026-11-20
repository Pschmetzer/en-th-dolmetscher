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


def routes(root=ROOT):
    """Reisearten als Paketbündel (tools/preset_routes.json): {id: {names, packs}}."""
    f = pathlib.Path(root) / "tools" / "preset_routes.json"
    return json.loads(f.read_text(encoding="utf-8"))["routes"] if f.exists() else {}


def keywords(d, limit=12):
    """Suchbegriffe eines Pakets: englische Glossarbegriffe (klein, ohne Dubletten, höchstens `limit`)."""
    out = []
    for g in d.get("glossary", []):
        w = str(g.get("en", "")).strip().lower()
        if w and w not in out:
            out.append(w)
    return out[:limit]


def extra_keywords(root=ROOT):
    """Deutsche und thailaendische Suchbegriffe je Paket (tools/preset_keywords.json, {id: {de: [...], th: [...]}})."""
    f = pathlib.Path(root) / "tools" / "preset_keywords.json"
    return json.loads(f.read_text(encoding="utf-8"))["keywords"] if f.exists() else {}


def build(root=ROOT):
    cats = categories(root)
    extra = extra_keywords(root)
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
                          "reviewed": old.get(d["id"], False), "category": cats.get(d["id"], "general"),
                          "keywords": keywords(d)}
        for lang in ("de", "th"):
            words = [w for w in extra.get(d["id"], {}).get(lang, []) if isinstance(w, str) and w.strip()]
            if words:
                packs[d["id"]]["keywords_" + lang] = words
        de, th = packs[d["id"]].get("keywords_de", []), packs[d["id"]].get("keywords_th", [])
        if de or th:   # Web-Suche liest nur `keywords`: en, de, th mischen (max. 12)
            mixed = keywords(d, 6) + [w.lower() for w in de[:3]] + [w.lower() for w in th[:3]]
            packs[d["id"]]["keywords"] = list(dict.fromkeys(mixed))[:12]
    ids = [i for i in ORDER if i in packs] + sorted(i for i in packs if i not in ORDER)
    out = {"version": 1, "packs": [packs[i] for i in ids]}
    rt = routes(root)
    if rt:
        out["routes"] = rt
    return out


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
