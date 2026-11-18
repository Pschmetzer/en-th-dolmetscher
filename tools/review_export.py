#!/usr/bin/env python3
"""Erzeugt einen Pruefbogen (CSV oder Markdown) fuer die Thai-Saetze der Phrasenpakete.

Aufruf:  python3 tools/review_export.py [--dir ORDNER] [--pack ID ...] [--critical] [--format csv|md] [--out DATEI]
Spalten: id, en, de, th, Status, Korrektur, Kommentar. Muttersprachler tragen Status (ok, korrigiert, unklar),
bei "korrigiert" die Korrektur und optional einen Kommentar ein. Die Spalte de ist fuer Erklaerungen gedacht und
bleibt leer (die Pakete haben keine deutschen Saetze). CSV: UTF-8 mit BOM (Excel), Formel-Schutz (Hochkomma vor
= + - @). Kritische Saetze stehen zuerst, wie in den Apps. Ausgabe deterministisch.
Danach: tools/review_import.py (Bogen einlesen), tools/review_status.py (Fortschritt).
"""
import argparse
import csv
import io
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _reviewlib import COLUMNS, load_packs, md_cell, protect, row_id  # noqa: E402


def build_rows(packs, critical_only=False):
    rows = []
    for name, d in packs:
        pid = d.get("id", name[:-5])
        allp = [p for p in d.get("phrases", []) if isinstance(p, dict)]
        order = sorted(range(len(allp)), key=lambda i: not allp[i].get("critical"))
        for i in order:
            p = allp[i]
            if critical_only and not p.get("critical"):
                continue
            rows.append([row_id(pid, i), str(p.get("en", "")), "", str(p.get("th", "")), "", "", ""])
    return rows


def render_csv(rows):
    buf = io.StringIO(newline="")
    w = csv.writer(buf, lineterminator="\r\n")
    w.writerow(COLUMNS)
    for r in rows:
        w.writerow([protect(c) for c in r])
    return "﻿" + buf.getvalue()


def render_md(rows):
    lines = ["| " + " | ".join(COLUMNS) + " |", "|" + "---|" * len(COLUMNS)]
    for r in rows:
        lines.append("| " + " | ".join(md_cell(c) for c in r) + " |")
    return "\n".join(lines) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description="Pruefbogen fuer Muttersprachler erzeugen (CSV mit BOM oder Markdown).")
    ap.add_argument("--dir", help="Paket-Ordner (Standard: presets/ im Repo)")
    ap.add_argument("--pack", action="append", default=[], metavar="ID", help="nur dieses Paket (mehrfach moeglich)")
    ap.add_argument("--critical", action="store_true", help="nur kritische Saetze (Notfall, Allergie, Polizei)")
    ap.add_argument("--format", choices=("csv", "md"), default="csv", help="Ausgabeformat (Standard: csv)")
    ap.add_argument("--out", metavar="DATEI", help="in Datei schreiben (Standard: Standardausgabe)")
    a = ap.parse_args(argv)
    rows = build_rows(load_packs(a.dir, a.pack), a.critical)
    text = render_csv(rows) if a.format == "csv" else render_md(rows)
    if a.out:
        pathlib.Path(a.out).write_bytes(text.encode("utf-8"))
        print("%d Saetze -> %s" % (len(rows), a.out), file=sys.stderr)
    else:
        sys.stdout.buffer.write(text.encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
