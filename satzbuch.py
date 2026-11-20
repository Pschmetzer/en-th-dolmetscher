#!/usr/bin/env python3
"""Export- und Prüfwerkzeug für das Satzbuch (presets/*.json, siehe docs/PRESETS.md).

Aufruf im Repo-Ordner:
    python3 satzbuch.py check                      Prüfung, Exitcode 1 bei Fehlern
    python3 satzbuch.py check --strict             auch Warnungen lassen die Prüfung scheitern
    python3 satzbuch.py check --json               Befunde maschinenlesbar
    python3 satzbuch.py export csv  -o satzbuch.csv
    python3 satzbuch.py export json -o satzbuch.json
    python3 satzbuch.py export anki -o satzbuch.txt   (Anki: Datei → Importieren, Tab-getrennt)
Optionen für export: --pack ID (mehrfach), --no-glossary, --critical-only, --dir ORDNER.

Geprüft wird: Schema (presets.validate), JSON-Lesefehler, id = Dateiname, fehlende Übersetzungen (en/th leer,
Namen und Hinweis unvollständig), Dubletten im Paket (en oder th, ohne Groß-/Kleinschreibung und Satzzeichen),
gleiche englische Sätze mit verschiedener Thai-Übersetzung in mehreren Paketen, Formatfehler (Leerzeichen am
Rand oder doppelt, Thai-Schrift fehlt oder steht im Englischen, ``___``-Lücken ungleich, ungleiche Klammern,
Höflichkeitspartikel ครับ/ค่ะ, ``{p}``-Platzhalter, kritische Sätze nicht oben).
Das Modul ändert keine Paketdateien; es liest nur.
"""
import argparse
import csv
import io
import json
import pathlib
import re
import sys

import presets as P

ROOT = pathlib.Path(__file__).resolve().parent
DEFAULT_DIR = ROOT / "presets"
KINDS = ("phrases", "glossary")
THAI = re.compile(r"[฀-๿]")
BLANK = re.compile(r"_{3,}")
PARTICLES = ("ครับ", "ค่ะ", "คะ", "นะคะ", "นะครับ", "ดิฉัน")
# Runde 22: auch คะ/นะคะ/ดิฉัน (weibliche Form); คะ nicht in คะแนน, คะน้า, คะนอง, คะเน, คะยั้น, คะยอ
_PARTICLE_RX = re.compile(r"ครับ|ค่ะ|นะคะ|ดิฉัน|คะ(?!แนน|น้า|นอง|เน|ยั้น|ยอ)")
PAIRS = (("(", ")"), ("[", "]"), ("“", "”"))
ERROR, WARNING = "error", "warning"
CSV_FIELDS = ("pack", "kind", "index", "en", "th", "critical", "name_de", "name_en", "name_th")


# --------------------------------------------------------------------------------------------------- Laden

def load_dir(folder=DEFAULT_DIR):
    """(packs, findings): packs = {Dateistamm: Daten} für lesbare JSON-Objekte, findings = Lesefehler."""
    folder = pathlib.Path(folder)
    packs, findings = {}, []
    for path in sorted(folder.glob("*.json")):
        try:
            d = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            findings.append(_f(ERROR, path.stem, "json", f"Datei nicht lesbar: {e}"))
            continue
        packs[path.stem] = d
    return packs, findings


def _f(severity, pack, code, message, where=None):
    return {"severity": severity, "pack": pack, "code": code, "where": where, "message": message}


def _norm(s):
    """Vergleichsform für Dubletten: klein, ohne Satzzeichen am Ende, Leerzeichen zusammengefasst."""
    s = re.sub(r"\s+", " ", (s or "").strip().lower())
    return re.sub(r"[\s.!?。,;:]+$", "", s)


def _items(d, kind):
    v = d.get(kind, []) if isinstance(d, dict) else []
    return v if isinstance(v, list) else []


# -------------------------------------------------------------------------------------------------- Prüfung

def check_pack(stem, d):
    """Befunde für ein einzelnes Paket (Dateistamm, geladene Daten)."""
    out = []
    if not isinstance(d, dict):
        return [_f(ERROR, stem, "schema", "kein JSON-Objekt")]
    for msg in P.validate(d):
        out.append(_f(ERROR, stem, "schema", msg))
    if isinstance(d.get("id"), str) and d["id"] != stem:
        out.append(_f(ERROR, stem, "id", f"id {d['id']!r} passt nicht zum Dateinamen {stem!r}.json"))
    names = d.get("names") if isinstance(d.get("names"), dict) else {}
    for lang in ("de", "en", "th"):
        if not str(names.get(lang) or "").strip():
            out.append(_f(ERROR, stem, "missing", f"Name auf {lang} fehlt", "names"))
    note = d.get("note")
    if isinstance(note, dict):
        for lang in ("de", "en"):
            if not str(note.get(lang) or "").strip():
                out.append(_f(ERROR, stem, "missing", f"Hinweis auf {lang} fehlt", "note"))

    for kind in KINDS:
        seen = {"en": {}, "th": {}}
        for i, it in enumerate(_items(d, kind)):
            where = f"{kind}[{i}]"
            if not isinstance(it, dict):
                out.append(_f(ERROR, stem, "schema", "Eintrag ist kein Objekt", where))
                continue
            en, th = it.get("en"), it.get("th")
            for lang, val in (("en", en), ("th", th)):
                if not isinstance(val, str) or not val.strip():
                    out.append(_f(ERROR, stem, "missing", f"Übersetzung {lang} fehlt", where))
                    continue
                key = _norm(val)
                if key in seen[lang]:
                    out.append(_f(ERROR, stem, "duplicate",
                                  f"{lang} doppelt (wie {kind}[{seen[lang][key]}]): {val!r}", where))
                else:
                    seen[lang][key] = i
            if isinstance(en, str) and isinstance(th, str) and en.strip() and th.strip():
                out.extend(_format(stem, where, kind, en, th))
        if kind == "phrases":
            flags = [bool(x.get("critical")) for x in _items(d, kind) if isinstance(x, dict)]
            if flags != sorted(flags, reverse=True):
                out.append(_f(WARNING, stem, "order", "kritische Sätze stehen nicht alle am Anfang", kind))
    return out


def _format(stem, where, kind, en, th):
    out = []
    for lang, val in (("en", en), ("th", th)):
        if val != val.strip():
            out.append(_f(ERROR, stem, "format", f"{lang}: Leerzeichen am Anfang oder Ende", where))
        if "  " in val:
            out.append(_f(WARNING, stem, "format", f"{lang}: doppeltes Leerzeichen", where))
        if "{p}" in val:
            out.append(_f(ERROR, stem, "format", f"{lang}: Platzhalter {{p}} statt ___", where))
        for a, b in PAIRS:
            if val.count(a) != val.count(b):
                out.append(_f(WARNING, stem, "format", f"{lang}: Klammern {a}{b} ungleich", where))
    if not THAI.search(th):
        out.append(_f(ERROR, stem, "format", "th enthält keine Thai-Schrift", where))
    if THAI.search(en):
        out.append(_f(ERROR, stem, "format", "en enthält Thai-Schrift (vertauscht?)", where))
    if len(BLANK.findall(en)) != len(BLANK.findall(th)):
        out.append(_f(ERROR, stem, "format", "Anzahl der ___-Lücken in en und th verschieden", where))
    if kind == "phrases" and _PARTICLE_RX.search(th):
        out.append(_f(WARNING, stem, "format", "Höflichkeitspartikel in th (ergänzt die Engine)", where))
    return out


def check_cross(packs):
    """Paketübergreifend: gleicher englischer Satz, aber verschiedene Thai-Übersetzungen (Warnung)."""
    by_en = {}
    for stem, d in sorted(packs.items()):
        for kind in KINDS:
            for i, it in enumerate(_items(d, kind)):
                if isinstance(it, dict) and isinstance(it.get("en"), str) and isinstance(it.get("th"), str):
                    by_en.setdefault((kind, _norm(it["en"])), []).append((stem, i, it["th"].strip(), it["en"]))
    out = []
    for (kind, _), hits in sorted(by_en.items()):
        ths = sorted({t for _, _, t, _ in hits})
        if len({s for s, _, _, _ in hits}) > 1 and len(ths) > 1:
            where = ", ".join(f"{s}:{kind}[{i}]" for s, i, _, _ in hits)
            out.append(_f(WARNING, hits[0][0], "inconsistent",
                          f"{hits[0][3]!r} hat verschiedene th-Übersetzungen: " + " / ".join(ths), where))
    return out


def check(folder=DEFAULT_DIR):
    """Alle Befunde für einen Paketordner."""
    packs, findings = load_dir(folder)
    for stem, d in packs.items():
        findings.extend(check_pack(stem, d))
    findings.extend(check_cross({s: d for s, d in packs.items() if isinstance(d, dict)}))
    return findings


def summary(findings):
    return {sev: sum(1 for f in findings if f["severity"] == sev) for sev in (ERROR, WARNING)}


def format_findings(findings):
    lines = []
    for f in findings:
        loc = f["pack"] + (f" {f['where']}" if f["where"] else "")
        lines.append(f"{f['severity'].upper():7} [{f['code']}] {loc}: {f['message']}")
    s = summary(findings)
    lines.append(f"{s[ERROR]} Fehler, {s[WARNING]} Warnungen")
    return "\n".join(lines)


# --------------------------------------------------------------------------------------------------- Export

def entries(packs, pack_ids=None, glossary=True, critical_only=False):
    """Flache Liste aller Einträge in stabiler Reihenfolge (Paket, Sätze vor Glossar, Index)."""
    rows = []
    for stem in sorted(packs):
        d = packs[stem]
        if not isinstance(d, dict) or (pack_ids and stem not in pack_ids):
            continue
        names = d.get("names") if isinstance(d.get("names"), dict) else {}
        for kind in KINDS:
            if kind == "glossary" and (not glossary or critical_only):
                continue
            for i, it in enumerate(_items(d, kind)):
                if not isinstance(it, dict):
                    continue
                crit = bool(it.get("critical"))
                if critical_only and not crit:
                    continue
                rows.append({"pack": stem, "kind": kind, "index": i, "en": str(it.get("en") or "").strip(),
                             "th": str(it.get("th") or "").strip(), "critical": crit,
                             "name_de": names.get("de", ""), "name_en": names.get("en", ""),
                             "name_th": names.get("th", "")})
    return rows


def _csv_safe(v):
    """Excel/Numbers führen Zellen mit = + - @ (oder Tab/CR) am Anfang als Formel aus: ' voranstellen."""
    return "'" + v if isinstance(v, str) and v[:1] in ("=", "+", "-", "@", "\t", "\r") else v


def to_csv(rows):
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=CSV_FIELDS, lineterminator="\n")
    w.writeheader()
    for r in rows:
        w.writerow({k: _csv_safe(v) for k, v in {**r, "critical": "1" if r["critical"] else "0"}.items()})
    return buf.getvalue()


def to_json(rows):
    packs = {}
    for r in rows:
        p = packs.setdefault(r["pack"], {"id": r["pack"], "names": {"de": r["name_de"], "en": r["name_en"],
                                                                    "th": r["name_th"]},
                                         "phrases": [], "glossary": []})
        item = {"en": r["en"], "th": r["th"]}
        if r["kind"] == "phrases":
            item["critical"] = r["critical"]
        p[r["kind"]].append(item)
    return json.dumps({"version": 1, "packs": list(packs.values())}, ensure_ascii=False, indent=1) + "\n"


def _anki_field(s):
    return re.sub(r"[\t\r\n]+", " ", s)


def to_anki(rows):
    """Anki-Textimport: Vorderseite EN, Rückseite TH, Tags (Paket, Art, kritisch)."""
    lines = ["#separator:tab", "#html:false", "#columns:English\tThai\tTags", "#tags column:3"]
    for r in rows:
        tags = [f"dolmetscher::{r['pack']}", "glossar" if r["kind"] == "glossary" else "satz"]
        if r["critical"]:
            tags.append("kritisch")
        lines.append("\t".join((_anki_field(r["en"]), _anki_field(r["th"]), " ".join(tags))))
    return "\n".join(lines) + "\n"


EXPORTERS = {"csv": to_csv, "json": to_json, "anki": to_anki}


# ------------------------------------------------------------------------------------------------------ CLI

def main(argv=None, stdout=None):
    stdout = stdout or sys.stdout
    ap = argparse.ArgumentParser(prog="satzbuch.py", description="Satzbuch exportieren und prüfen")
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check", help="Pakete prüfen")
    c.add_argument("--dir", default=str(DEFAULT_DIR))
    c.add_argument("--strict", action="store_true", help="Warnungen zählen als Fehler")
    c.add_argument("--json", action="store_true", help="Befunde als JSON ausgeben")
    e = sub.add_parser("export", help="Pakete exportieren")
    e.add_argument("format", choices=sorted(EXPORTERS))
    e.add_argument("--dir", default=str(DEFAULT_DIR))
    e.add_argument("-o", "--output", help="Zieldatei (Standard: Standardausgabe)")
    e.add_argument("--pack", action="append", help="nur dieses Paket (mehrfach möglich)")
    e.add_argument("--no-glossary", action="store_true")
    e.add_argument("--critical-only", action="store_true")
    a = ap.parse_args(argv)

    if a.cmd == "check":
        findings = check(a.dir)
        if a.json:
            stdout.write(json.dumps({"summary": summary(findings), "findings": findings},
                                    ensure_ascii=False, indent=1) + "\n")
        else:
            stdout.write(format_findings(findings) + "\n")
        s = summary(findings)
        return 1 if s[ERROR] or (a.strict and s[WARNING]) else 0

    packs, errs = load_dir(a.dir)
    if a.pack:
        unknown = sorted(set(a.pack) - set(packs))
        if unknown:
            sys.stderr.write("unbekannte Pakete: " + ", ".join(unknown) + "\n")
            return 2
    for f in errs:
        sys.stderr.write(f"übersprungen: {f['pack']}: {f['message']}\n")
    text = EXPORTERS[a.format](entries(packs, set(a.pack or ()), not a.no_glossary, a.critical_only))
    if a.output:
        # CSV mit BOM (utf-8-sig): Excel erkennt sonst UTF-8 nicht (Thai als Zeichensalat)
        with open(a.output, "w", encoding="utf-8-sig" if a.format == "csv" else "utf-8", newline="") as fh:
            fh.write(text)
    else:
        stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
