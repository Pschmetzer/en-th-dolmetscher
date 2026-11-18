#!/usr/bin/env python3
"""Exportiert Phrasenpakete (presets/*.json) als CSV, Markdown, druckbares HTML (A5/A6-Karten) oder Anki-TSV.

Beispiele:
  python3 tools/export_phrasebook.py csv --out satzbuch.csv
  python3 tools/export_phrasebook.py html --pack taxi --pack doctor --size a6 --out k.html
  python3 tools/export_phrasebook.py anki --critical-only
Ohne --out geht die Ausgabe nach stdout. Ausgabe deterministisch (Dateiname-Reihenfolge, kritische Saetze zuerst).
Hinweis: Thai-Saetze sind maschinell uebersetzt, nicht muttersprachlich geprueft.
"""
import argparse
import csv
import html
import io
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _presetlib import load_packs, phrases_of  # noqa: E402

DISCLAIMER = "Maschinell uebersetzt - muttersprachlich pruefen."
CSV_HEAD = ["pack", "critical", "en", "th"]


def rows(packs, critical_only):
    for name, d in packs:
        pid = d.get("id", name[:-5])
        for p in phrases_of(d):
            if critical_only and not p.get("critical"):
                continue
            yield pid, d, p


def to_csv(packs, critical_only):
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    w.writerow(CSV_HEAD)
    for pid, _d, p in rows(packs, critical_only):
        w.writerow([pid, "1" if p.get("critical") else "0", p.get("en", ""), p.get("th", "")])
    return buf.getvalue()


def to_markdown(packs, critical_only):
    out = ["# Satzbuch", "", "> " + DISCLAIMER, ""]
    for name, d in packs:
        ph = [p for p in phrases_of(d) if p.get("critical") or not critical_only]
        if not ph:
            continue
        names = d.get("names", {})
        out += ["## %s / %s" % (names.get("de", d.get("id", name)), names.get("th", "")), ""]
        note = d.get("note", {}).get("de")
        if note:
            out += ["> " + note, ""]
        out += ["| | English | ไทย |", "|---|---|---|"]
        for p in ph:
            cell = lambda s: str(s).replace("|", "\\|")  # noqa: E731
            mark = "!" if p.get("critical") else ""
            out.append("| %s | %s | %s |" % (mark, cell(p.get("en", "")), cell(p.get("th", ""))))
        out.append("")
    return "\n".join(out)


def to_html(packs, critical_only, size):
    dims = {"a5": ("148mm", "210mm"), "a6": ("105mm", "148mm")}[size]
    css = (
        "@page{size:%s %s;margin:0}body{margin:0;font-family:sans-serif}"
        ".card{width:%s;height:%s;box-sizing:border-box;padding:8mm;page-break-after:always;overflow:hidden}"
        ".card h1{font-size:12pt;margin:0 0 4mm}.card .crit{border-left:3mm solid #c00;padding-left:2mm}"
        ".en{font-size:11pt}.th{font-size:15pt;margin-bottom:3mm}.hint{font-size:7pt;color:#555;position:absolute;bottom:4mm}"
        % (dims[0], dims[1], dims[0], dims[1])
    )
    out = ['<!doctype html>', '<html lang="en"><head><meta charset="utf-8">',
           "<title>Satzbuch %s</title>" % size.upper(), "<style>%s</style></head><body>" % css]
    for _name, d, group in _cards(packs, critical_only, size):
        names = d.get("names", {})
        out.append('<section class="card"><h1>%s / %s</h1>' % (html.escape(names.get("en", d.get("id", ""))),
                                                              html.escape(names.get("th", ""))))
        for p in group:
            cls = ' class="crit"' if p.get("critical") else ""
            out.append('<div%s><div class="en">%s</div><div class="th" lang="th">%s</div></div>'
                       % (cls, html.escape(p.get("en", "")), html.escape(p.get("th", ""))))
        out.append('<div class="hint">%s</div></section>' % html.escape(DISCLAIMER))
    out.append("</body></html>")
    return "\n".join(out) + "\n"


def _cards(packs, critical_only, size):
    per = 8 if size == "a5" else 4
    for name, d in packs:
        ph = [p for p in phrases_of(d) if p.get("critical") or not critical_only]
        for i in range(0, len(ph), per):
            yield name, d, ph[i:i + per]


def to_anki(packs, critical_only):
    lines = []
    for pid, _d, p in rows(packs, critical_only):
        tags = pid + (" critical" if p.get("critical") else "")
        fields = [p.get("en", ""), p.get("th", ""), tags]
        lines.append("\t".join(f.replace("\t", " ").replace("\n", " ") for f in fields))
    return "\n".join(lines) + ("\n" if lines else "")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Phrasenpakete als CSV, Markdown, HTML-Karten oder Anki-TSV exportieren.")
    ap.add_argument("format", choices=["csv", "md", "html", "anki"], help="Ausgabeformat")
    ap.add_argument("--dir", help="Paket-Ordner (Standard: presets/ im Repo)")
    ap.add_argument("--pack", action="append", default=[], metavar="ID", help="nur dieses Paket (mehrfach moeglich)")
    ap.add_argument("--critical-only", action="store_true", help="nur sicherheitskritische Saetze")
    ap.add_argument("--size", choices=["a5", "a6"], default="a6", help="Kartengroesse fuer html (Standard: a6)")
    ap.add_argument("--out", help="Zieldatei (Standard: stdout)")
    a = ap.parse_args(argv)
    packs = load_packs(a.dir, a.pack)
    text = {"csv": lambda: to_csv(packs, a.critical_only), "md": lambda: to_markdown(packs, a.critical_only),
            "html": lambda: to_html(packs, a.critical_only, a.size),
            "anki": lambda: to_anki(packs, a.critical_only)}[a.format]()
    if a.out:
        pathlib.Path(a.out).write_text(text, encoding="utf-8", newline="")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
