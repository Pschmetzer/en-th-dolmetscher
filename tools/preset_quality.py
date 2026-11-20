#!/usr/bin/env python3
"""Qualitaetsbericht je Paket: Laenge, Zahlen, kritische Saetze, Glossar-Konsistenz, Pruefstatus.

Aufruf:  python3 tools/preset_quality.py [--dir ORDNER] [--json] [--min-score N]
Punkte (0-100): Abzug fuer lange Saetze, fehlende kritische Saetze in Sicherheitskategorien, Zahlen in nur einer
Sprache, abweichende Glossarwoerter gegenueber anderen Paketen, nicht muttersprachlich geprueft (kein Abzug,
nur Anzeige). Ein Hilfsmittel zum Priorisieren der Durchsicht, kein Urteil ueber die Uebersetzung."""
import argparse
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _presetlib import load_packs, norm  # noqa: E402
import make_presets_index  # noqa: E402

NUM = re.compile(r"\d+")
SAFETY = {"emergency", "health"}


def glossary_conflicts(packs):
    """{pack_id: Anzahl Begriffe, deren Thai von der Mehrheit der anderen Pakete abweicht}."""
    seen = {}
    for name, d in packs:
        for g in d.get("glossary", []):
            by_th = seen.setdefault(norm(g.get("en", "")), {})
            by_th.setdefault(norm(g.get("th", "")), set()).add(d.get("id", name[:-5]))
    out = {}
    for variants in seen.values():
        if len(variants) < 2:
            continue
        major = max(variants.values(), key=len)
        for packs_with in variants.values():
            if packs_with is not major:
                for pid in packs_with:
                    out[pid] = out.get(pid, 0) + 1
    return out


def report(packs, root=None):
    cats = make_presets_index.categories(root or make_presets_index.ROOT)
    idx = {}
    try:
        idx = {p["id"]: p for p in json.loads((pathlib.Path(root or make_presets_index.ROOT) / "presets-index.json")
                                              .read_text(encoding="utf-8"))["packs"]}
    except (OSError, ValueError, KeyError):
        pass
    gc = glossary_conflicts(packs)
    rows = []
    for name, d in packs:
        pid = d.get("id", name[:-5])
        ph = d.get("phrases", [])
        long_ = sum(1 for p in ph if len(p.get("en", "")) > 100 or len(p.get("th", "")) > 100)
        crit = sum(1 for p in ph if p.get("critical"))
        num_mismatch = sum(1 for p in ph if NUM.search(p.get("th", ""))
                           and sorted(NUM.findall(p.get("en", ""))) != sorted(NUM.findall(p["th"])))
        cat = cats.get(pid, "general")
        score = 100 - 3 * long_ - 10 * num_mismatch - 2 * gc.get(pid, 0)
        if cat in SAFETY and crit == 0:
            score -= 20
        if len(ph) < 12:
            score -= 10
        rows.append({"id": pid, "category": cat, "phrases": len(ph), "critical": crit, "long": long_,
                     "number_mismatch": num_mismatch, "glossary_conflicts": gc.get(pid, 0),
                     "reviewed": bool(idx.get(pid, {}).get("reviewed")), "score": max(0, score)})
    return sorted(rows, key=lambda r: (r["score"], r["id"]))


def main(argv=None):
    ap = argparse.ArgumentParser(description="Qualitaetsbericht der Phrasenpakete.")
    ap.add_argument("--dir")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--min-score", type=int, default=0, help="Exit 1, wenn ein Paket darunter liegt")
    a = ap.parse_args(argv)
    rows = report(load_packs(a.dir))
    if a.json:
        print(json.dumps(rows, ensure_ascii=False, indent=1))
    else:
        head = ("id", "kategorie", "satz", "krit", "lang", "zahl", "glos", "punkte")
        print("%-28s %-9s %5s %5s %5s %5s %5s %s" % head)
        for r in rows:
            print("%-28s %-9s %5d %5d %5d %5d %5d %6d%s" % (r["id"], r["category"], r["phrases"], r["critical"],
                  r["long"], r["number_mismatch"], r["glossary_conflicts"], r["score"], "" if r["reviewed"] else "  *"))
        print("* = nicht muttersprachlich geprueft")
    return 1 if rows and rows[0]["score"] < a.min_score else 0


if __name__ == "__main__":
    sys.exit(main())
