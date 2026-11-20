#!/usr/bin/env python3
"""Sucht in allen Phrasenpaketen (Saetze, Glossar, Namen, Stichwoerter), de/en/th.

Aufruf:  python3 tools/preset_search.py BEGRIFF [--dir ORDNER] [--critical] [--limit N] [--json]
Treffer: Paket-id, Fundort (phrase/glossary/name), englisch und Thai. Ohne Gross-/Kleinschreibung."""
import argparse
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _presetlib import load_packs, norm  # noqa: E402


def search(packs, query, critical_only=False):
    q = norm(query)
    if not q:
        return []
    hits = []
    for name, d in packs:
        pid = d.get("id", name[:-5])
        for lang, text in (d.get("names") or {}).items():
            if q in norm(text):
                hits.append({"pack": pid, "where": "name", "en": d["names"].get("en", ""),
                             "th": d["names"].get("th", "")})
                break
        if not critical_only:
            for g in d.get("glossary", []):
                if q in norm(g.get("en", "")) or q in norm(g.get("th", "")):
                    hits.append({"pack": pid, "where": "glossary", "en": g["en"], "th": g["th"]})
        for p in d.get("phrases", []):
            if critical_only and not p.get("critical"):
                continue
            if q in norm(p.get("en", "")) or q in norm(p.get("th", "")):
                hits.append({"pack": pid, "where": "phrase", "en": p["en"], "th": p["th"],
                             "critical": bool(p.get("critical"))})
    return hits


def main(argv=None):
    ap = argparse.ArgumentParser(description="In allen Phrasenpaketen suchen.")
    ap.add_argument("query")
    ap.add_argument("--dir")
    ap.add_argument("--critical", action="store_true", help="nur kritische Saetze")
    ap.add_argument("--limit", type=int, default=50)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    hits = search(load_packs(a.dir), a.query, a.critical)[:max(0, a.limit)]
    if a.json:
        print(json.dumps(hits, ensure_ascii=False, indent=1))
    else:
        for h in hits:
            mark = "  [!]" if h.get("critical") else ""
            print("%-26s %-8s %s | %s%s" % (h["pack"], h["where"], h["en"], h["th"], mark))
        print("%d Treffer" % len(hits))
    return 0 if hits else 1


if __name__ == "__main__":
    sys.exit(main())
