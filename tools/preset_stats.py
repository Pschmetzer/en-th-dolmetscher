#!/usr/bin/env python3
"""Statistik ueber Phrasenpakete: Saetze, kritische, Glossar, Laengen, Anteil kritisch.

Aufruf:  python3 tools/preset_stats.py [--dir ORDNER] [--pack ID ...] [--format text|json|md]
Ausgabe deterministisch, sortiert nach Dateiname.
"""
import argparse
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _presetlib import load_packs, phrases_of  # noqa: E402


def stats(packs):
    out = []
    for name, d in packs:
        ph = phrases_of(d)
        n = len(ph)
        crit = sum(1 for p in ph if p.get("critical"))
        en_len = [len(str(p.get("en", ""))) for p in ph]
        th_len = [len(str(p.get("th", ""))) for p in ph]
        out.append({"id": d.get("id", name[:-5]), "phrases": n, "critical": crit,
                    "glossary": len(d.get("glossary", [])),
                    "critical_pct": round(100.0 * crit / n, 1) if n else 0.0,
                    "avg_en": round(sum(en_len) / n, 1) if n else 0.0,
                    "avg_th": round(sum(th_len) / n, 1) if n else 0.0,
                    "max_th": max(th_len) if th_len else 0,
                    "has_note": bool(d.get("note"))})
    return out


def total(rows):
    n = sum(r["phrases"] for r in rows)
    c = sum(r["critical"] for r in rows)
    return {"packs": len(rows), "phrases": n, "critical": c, "glossary": sum(r["glossary"] for r in rows),
            "critical_pct": round(100.0 * c / n, 1) if n else 0.0}


COLS = [("id", "id"), ("phrases", "Saetze"), ("critical", "kritisch"), ("critical_pct", "kritisch%"),
        ("glossary", "Glossar"), ("avg_en", "o-en"), ("avg_th", "o-th"), ("max_th", "max-th")]


def table(rows, md):
    cells = [[str(r[k]) for k, _h in COLS] for r in rows]
    head = [h for _k, h in COLS]
    if md:
        lines = ["| " + " | ".join(head) + " |", "|" + "---|" * len(head)]
        lines += ["| " + " | ".join(c) + " |" for c in cells]
        return "\n".join(lines)
    w = [max(len(x) for x in col) for col in zip(head, *cells)]
    fmt = lambda row: "  ".join(x.ljust(w[i]) if i == 0 else x.rjust(w[i]) for i, x in enumerate(row))  # noqa: E731
    return "\n".join([fmt(head)] + [fmt(c) for c in cells])


def main(argv=None):
    ap = argparse.ArgumentParser(description="Statistik ueber Phrasenpakete.")
    ap.add_argument("--dir", help="Paket-Ordner (Standard: presets/ im Repo)")
    ap.add_argument("--pack", action="append", default=[], metavar="ID", help="nur dieses Paket (mehrfach moeglich)")
    ap.add_argument("--format", choices=["text", "json", "md"], default="text")
    a = ap.parse_args(argv)
    rows = stats(load_packs(a.dir, a.pack))
    t = total(rows)
    if a.format == "json":
        print(json.dumps({"packs": rows, "total": t}, ensure_ascii=False, indent=1))
    else:
        print(table(rows, a.format == "md"))
        print("\nGesamt: %(packs)d Pakete, %(phrases)d Saetze, %(critical)d kritisch (%(critical_pct)s%%), "
              "%(glossary)d Glossar-Paare" % t)
    return 0


if __name__ == "__main__":
    sys.exit(main())
