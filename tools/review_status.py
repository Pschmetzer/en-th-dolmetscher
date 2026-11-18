#!/usr/bin/env python3
"""Zeigt den Pruefstand der Thai-Saetze: je Paket geprueft oder offen, Anteil.

Aufruf:  python3 tools/review_status.py [--dir ORDNER] [--pack ID ...] [--sheet BOGEN ...] [--format text|json]
Quelle ist `reviewed` in presets-index.json (ein Paket gilt nur als geprueft, wenn alle Saetze bestaetigt sind).
Mit --sheet (mehrfach moeglich) kommt der Satzstand aus ausgefuellten Boegen dazu: je Paket bestaetigt/Saetze
(Status ok oder korrigiert). Ausgabe deterministisch, sortiert nach Dateiname.
"""
import argparse
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _reviewlib import STATUS_FIXED, STATUS_OK, load_packs, read_index, read_sheet, split_id  # noqa: E402


def collect(packs, index, sheets):
    flags = {p.get("id"): bool(p.get("reviewed")) for p in (index or {}).get("packs", []) if isinstance(p, dict)}
    confirmed = {}
    for rows in sheets:
        for r in rows:
            loc = split_id(r["id"].strip())
            if loc and r["Status"].strip().casefold() in (STATUS_OK, STATUS_FIXED):
                confirmed.setdefault(loc[0], set()).add(loc[1])
    out = []
    for name, d in packs:
        pid = d.get("id", name[:-5])
        n = len([p for p in d.get("phrases", []) if isinstance(p, dict)])
        crit = sum(1 for p in d.get("phrases", []) if isinstance(p, dict) and p.get("critical"))
        row = {"id": pid, "phrases": n, "critical": crit, "reviewed": flags.get(pid, False)}
        if sheets:
            row["confirmed"] = len({i for i in confirmed.get(pid, set()) if 0 <= i < n})
        out.append(row)
    return out


def pct(a, b):
    return round(100.0 * a / b, 1) if b else 0.0


def render(rows, sheets):
    done = [r for r in rows if r["reviewed"]]
    lines = []
    for r in rows:
        extra = "  bestaetigt %d/%d" % (r["confirmed"], r["phrases"]) if sheets else ""
        lines.append("%-26s %3d Saetze (%2d kritisch)  %s%s"
                     % (r["id"], r["phrases"], r["critical"], "geprueft" if r["reviewed"] else "offen", extra))
    total = sum(r["phrases"] for r in rows)
    done_n = sum(r["phrases"] for r in done)
    lines.append("Pakete: %d geprueft, %d offen (%.1f %%)"
                 % (len(done), len(rows) - len(done), pct(len(done), len(rows))))
    lines.append("Saetze in geprueften Paketen: %d von %d (%.1f %%)" % (done_n, total, pct(done_n, total)))
    if sheets:
        conf = sum(r["confirmed"] for r in rows)
        lines.append("Laut Boegen bestaetigt: %d von %d Saetzen (%.1f %%)" % (conf, total, pct(conf, total)))
    return lines


def main(argv=None):
    ap = argparse.ArgumentParser(description="Pruefstand der Thai-Saetze je Paket anzeigen.")
    ap.add_argument("--dir", help="Paket-Ordner (Standard: presets/ im Repo)")
    ap.add_argument("--pack", action="append", default=[], metavar="ID", help="nur dieses Paket (mehrfach moeglich)")
    ap.add_argument("--sheet", action="append", default=[], metavar="BOGEN",
                    help="ausgefuellter Bogen fuer den Satzstand (mehrfach moeglich)")
    ap.add_argument("--format", choices=("text", "json"), default="text", help="Ausgabeformat (Standard: text)")
    a = ap.parse_args(argv)
    packs = load_packs(a.dir, a.pack)
    directory = a.dir or str(pathlib.Path(__file__).resolve().parent.parent / "presets")
    sheets = []
    for s in a.sheet:
        try:
            sheets.append(read_sheet(s))
        except ValueError as e:
            print("Fehler: %s: %s" % (s, e))
            return 1
    rows = collect(packs, read_index(directory), sheets)
    if a.format == "json":
        done = sum(1 for r in rows if r["reviewed"])
        print(json.dumps({"packs": rows, "reviewed": done, "open": len(rows) - done},
                         ensure_ascii=False, indent=1))
    else:
        print("\n".join(render(rows, sheets)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
