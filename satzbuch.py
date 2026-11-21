#!/usr/bin/env python3
"""Export- und Prüfwerkzeug für das Satzbuch (presets/*.json, siehe docs/PRESETS.md).

Aufruf im Repo-Ordner:
    python3 satzbuch.py check                      Prüfung, Exitcode 1 bei Fehlern
    python3 satzbuch.py check --strict             auch Warnungen lassen die Prüfung scheitern
    python3 satzbuch.py check --json               Befunde maschinenlesbar
    python3 satzbuch.py check --ignore CODE --pack ID   Befunde filtern
    python3 satzbuch.py report [--json] [-o datei.md]   Bericht nach Code und Paket (mit Zahlen und Unscharf-Prüfung)
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
import difflib
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
    if not folder.is_dir():            # Runde 24: ein falscher --dir meldete früher "0 Fehler" und Exitcode 0
        return packs, [_f(ERROR, str(folder), "dir", "Ordner nicht gefunden")]
    paths = sorted(folder.glob("*.json"))
    if not paths:
        return packs, [_f(ERROR, str(folder), "empty", "keine Paketdateien (*.json) im Ordner")]
    for path in paths:
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


# ------------------------------------------------------------------------- Zahlenformat (Thai) und Fuzzy

THAI_DIGITS = str.maketrans("๐๑๒๓๔๕๖๗๘๙", "0123456789")
_THAI_DIGIT = re.compile(r"[๐-๙]")
_NUM_TOKEN = re.compile(r"[0-9๐-๙][0-9๐-๙.,]*[0-9๐-๙]|[0-9๐-๙]")
_DE_NUMBER = re.compile(r"\d{1,3}(?:\.\d{3})+,\d+")          # 1.000,50 (deutsch) statt 1,000.50 / 1000.50


def ascii_digits(s):
    """Thai-Ziffern (๐-๙) in 0-9 umschreiben."""
    return (s or "").translate(THAI_DIGITS)


def numbers_of(s):
    """Zahlen eines Textes als Ziffernfolgen ohne Tausender-/Dezimalzeichen, Thai-Ziffern umgerechnet.
    "1,500.50 THB" -> ["150050"]; "๓๐ นาที" -> ["30"]."""
    return sorted(re.sub(r"[.,]", "", ascii_digits(m)) for m in _NUM_TOKEN.findall(s or ""))


def check_numbers(stem, d):
    """Zahlenformat-Befunde (Warnungen) je Eintrag: Zahlen in en und th verschieden, Thai- und arabische Ziffern in
    einer Zahl gemischt, Thai-Ziffern überhaupt (üblich sind arabische), deutsches Format 1.000,50."""
    out = []
    for kind in KINDS:
        for i, it in enumerate(_items(d, kind)):
            if not isinstance(it, dict):
                continue
            en, th = it.get("en"), it.get("th")
            if not (isinstance(en, str) and isinstance(th, str)):
                continue
            where = f"{kind}[{i}]"
            if numbers_of(en) != numbers_of(th):
                out.append(_f(WARNING, stem, "numbers", f"Zahlen in en und th verschieden: {en!r} / {th!r}", where))
            for tok in _NUM_TOKEN.findall(th):
                if _THAI_DIGIT.search(tok) and re.search(r"[0-9]", tok):
                    out.append(_f(WARNING, stem, "numbers", f"Thai- und arabische Ziffern gemischt: {tok!r}", where))
            if _THAI_DIGIT.search(th):
                out.append(_f(WARNING, stem, "numbers", "Thai-Ziffern in th (arabische Ziffern sind üblich)", where))
            for lang, val in (("en", en), ("th", th)):
                if _DE_NUMBER.search(val):
                    out.append(_f(WARNING, stem, "numbers", f"{lang}: Zahl im deutschen Format (1.000,50)", where))
    return out


_ZERO_WIDTH = re.compile("[\u200b\u200c\u200d\u2060\ufeff\u00ad]")
_GENDER_PRON = re.compile(r"ดิฉัน|กระผม|(?<![ก-๙])ผม(?!ที่|ยาว|หงอก|ร่วง|สั้น|ดำ|เส้น|ของ)")
_Q_WORD_END = re.compile(r"(ไหม|มั้ย|เหรอ|หรือเปล่า|อะไร|ไหน|ใคร|เท่าไร|เท่าไหร่|เมื่อไร|เมื่อไหร่|ทำไม|อย่างไร|ยังไง)$")


def check_thai(stem, d):
    """Thai-Sprachprüfung (Warnungen, Runde 28): unsichtbare Zero-Width-Zeichen, geschlechtsgebundenes Ich (ผม, ดิฉัน,
    กระผม: Pakete sollen für Frau und Mann passen), Frage mit ค่ะ statt คะ / Aussage mit คะ statt ค่ะ, Leerzeichen
    doppeltes ๆ."""
    out = []
    for kind in KINDS:
        for i, it in enumerate(_items(d, kind)):
            th = it.get("th") if isinstance(it, dict) else None
            if not isinstance(th, str) or not th.strip():
                continue
            where = f"{kind}[{i}]"
            if _ZERO_WIDTH.search(th):
                out.append(_f(WARNING, stem, "thai-zerowidth", f"unsichtbares Zeichen in th: {th!r}", where))
            if kind == "phrases" and _GENDER_PRON.search(th):
                out.append(_f(WARNING, stem, "thai-gender", f"geschlechtsgebundenes Ich in th: {th!r}", where))
            if "ๆๆ" in th:
                out.append(_f(WARNING, stem, "thai-maiyamok", f"ๆ doppelt: {th!r}", where))
            for m in re.finditer(r"ค่ะ|คะ(?!แนน|น้า|นอง|เน|ยั้น|ยอ)", th):
                if th[m.end():m.end() + 1] and "ก" <= th[m.end()] <= "๙":
                    continue
                q = bool(_Q_WORD_END.search(th[:m.start()].rstrip()))
                if q and m.group(0) == "ค่ะ" or (not q and m.group(0) == "คะ"
                                                 and th[:m.start()].endswith(("ขอบคุณ", "ขอโทษ", "สวัสดี"))):
                    out.append(_f(WARNING, stem, "thai-ka", f"{m.group(0)} {'in Frage' if q else 'in Aussage'}: "
                                  f"{th!r}", where))
                    break
    return out


def _fold(s):
    """Vergleichsform für unscharfes Suchen: klein, ohne Satzzeichen und Leerraum (Thai trennt keine Wörter)."""
    return "".join(c for c in ascii_digits(s or "").casefold() if c.isalnum() or "฀" <= c <= "๿")


def similarity(a, b):
    """Ähnlichkeit 0..1 zweier Sätze (difflib auf der Vergleichsform)."""
    fa, fb = _fold(a), _fold(b)
    if not fa or not fb:
        return 0.0
    return difflib.SequenceMatcher(None, fa, fb, autojunk=False).ratio()


def fuzzy_match(query, packs, lang="en", threshold=0.8, limit=5, kind="phrases"):
    """Geprüfte Sätze, die einem gesprochenen/getippten Satz ähneln. -> [{score, pack, index, en, th, critical}],
    beste zuerst (Gleichstand: Paketname, Index). `lang` = Sprache von `query` ("en" oder "th")."""
    if lang not in ("en", "th") or not _fold(query):
        return []
    hits = []
    for stem in sorted(packs):
        d = packs[stem]
        for i, it in enumerate(_items(d, kind)):
            if not isinstance(it, dict) or not isinstance(it.get(lang), str):
                continue
            sc = similarity(query, it[lang])
            if sc >= threshold:
                hits.append({"score": round(sc, 3), "pack": stem, "index": i, "en": it.get("en"), "th": it.get("th"),
                             "critical": bool(it.get("critical"))})
    hits.sort(key=lambda h: (-h["score"], h["pack"], h["index"]))
    return hits[:max(0, int(limit))]


def check_near_duplicates(stem, d, threshold=0.92):
    """Fast gleiche Sätze im Paket (Tippfehler-Varianten, die die exakte Dublettenprüfung nicht findet)."""
    out = []
    for kind in KINDS:
        items = [(i, it) for i, it in enumerate(_items(d, kind)) if isinstance(it, dict)]
        for a in range(len(items)):
            for b in range(a + 1, len(items)):
                for lang in ("en", "th"):
                    x, y = items[a][1].get(lang), items[b][1].get(lang)
                    if not (isinstance(x, str) and isinstance(y, str)) or _norm(x) == _norm(y):
                        continue
                    if similarity(x, y) >= threshold:
                        out.append(_f(WARNING, stem, "near_duplicate",
                                      f"{lang} fast gleich wie {kind}[{items[a][0]}]: {y!r}", f"{kind}[{items[b][0]}]"))
    return out


def check(folder=DEFAULT_DIR, numbers=False, fuzzy=False, thai=False):
    """Alle Befunde für einen Paketordner. numbers=True: auch Zahlenformat-Prüfung, fuzzy=True: auch fast gleiche Sätze
    (beides Warnungen; aus, damit bestehende Aufrufe unverändert bleiben)."""
    packs, findings = load_dir(folder)
    for stem, d in packs.items():
        findings.extend(check_pack(stem, d))
        if isinstance(d, dict):
            if numbers:
                findings.extend(check_numbers(stem, d))
            if fuzzy:
                findings.extend(check_near_duplicates(stem, d))
            if thai:
                findings.extend(check_thai(stem, d))
    findings.extend(check_cross({s: d for s, d in packs.items() if isinstance(d, dict)}))
    return findings


def report(folder=DEFAULT_DIR, numbers=True, fuzzy=True):
    """Prüfbericht (Runde 24): Befunde nach Code und Paket gezählt, dazu Umfang je Paket. -> dict (JSON-fähig)."""
    packs, _errs = load_dir(folder)
    findings = check(folder, numbers=numbers, fuzzy=fuzzy)
    by_code, by_pack = {}, {}
    for f in findings:
        c = by_code.setdefault(f["code"], {"error": 0, "warning": 0})
        c[f["severity"]] += 1
        p = by_pack.setdefault(f["pack"], {"error": 0, "warning": 0})
        p[f["severity"]] += 1
    size = {}
    for stem, d in sorted(packs.items()):
        if isinstance(d, dict):
            ph = [x for x in _items(d, "phrases") if isinstance(x, dict)]
            size[stem] = {"phrases": len(ph), "critical": sum(1 for x in ph if x.get("critical")),
                          "glossary": len(_items(d, "glossary"))}
    return {"summary": summary(findings), "packs": len(packs), "by_code": by_code, "by_pack": by_pack,
            "size": size, "findings": findings}


def format_report(rep):
    """Bericht als Markdown (für CI-Zusammenfassung oder Issue)."""
    s = rep["summary"]
    lines = ["# Satzbuch-Prüfbericht", "",
             f"{rep['packs']} Pakete, {s[ERROR]} Fehler, {s[WARNING]} Warnungen.", ""]
    if rep["by_code"]:
        lines += ["## Nach Code", "", "| Code | Fehler | Warnungen |", "|---|---|---|"]
        for code, c in sorted(rep["by_code"].items(), key=lambda kv: (-(kv[1]["error"] + kv[1]["warning"]), kv[0])):
            lines.append(f"| {code} | {c['error']} | {c['warning']} |")
        lines.append("")
    if rep["by_pack"]:
        worst = sorted(rep["by_pack"].items(), key=lambda kv: (-kv[1]["error"], -kv[1]["warning"], kv[0]))[:10]
        lines += ["## Pakete mit den meisten Befunden", "", "| Paket | Fehler | Warnungen |", "|---|---|---|"]
        lines += [f"| {p} | {c['error']} | {c['warning']} |" for p, c in worst] + [""]
    tot = {k: sum(v[k] for v in rep["size"].values()) for k in ("phrases", "critical", "glossary")}
    lines += ["## Umfang", "",
              f"{tot['phrases']} Sätze ({tot['critical']} kritisch), {tot['glossary']} Glossareinträge."]
    return "\n".join(lines) + "\n"


def summary(findings):
    return {sev: sum(1 for f in findings if f["severity"] == sev) for sev in (ERROR, WARNING)}


def filter_findings(findings, ignore=(), packs=None):
    """Befunde ohne die Codes in `ignore` und (falls `packs` gesetzt) nur aus diesen Paketen."""
    ign = set(ignore or ())
    return [f for f in findings if f["code"] not in ign and (not packs or f["pack"] in set(packs))]


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
    c.add_argument("--numbers", action="store_true", help="auch Zahlenformat (Thai-Ziffern, en/th-Zahlen) prüfen")
    c.add_argument("--thai", action="store_true", help="auch Thai-Sprache prüfen (Zero-Width, Ich-Pronomen, คะ/ค่ะ)")
    c.add_argument("--fuzzy", action="store_true", help="auch fast gleiche Sätze melden")
    c.add_argument("--ignore", action="append", default=[], metavar="CODE", help="Befundcode ausblenden (mehrfach)")
    c.add_argument("--pack", action="append", help="nur Befunde dieses Pakets (mehrfach möglich)")
    r = sub.add_parser("report", help="Prüfbericht (Markdown oder JSON)")
    r.add_argument("--dir", default=str(DEFAULT_DIR))
    r.add_argument("--json", action="store_true")
    r.add_argument("-o", "--output", help="Zieldatei (Standard: Standardausgabe)")
    e = sub.add_parser("export", help="Pakete exportieren")
    e.add_argument("format", choices=sorted(EXPORTERS))
    e.add_argument("--dir", default=str(DEFAULT_DIR))
    e.add_argument("-o", "--output", help="Zieldatei (Standard: Standardausgabe)")
    e.add_argument("--pack", action="append", help="nur dieses Paket (mehrfach möglich)")
    e.add_argument("--no-glossary", action="store_true")
    e.add_argument("--critical-only", action="store_true")
    a = ap.parse_args(argv)

    if a.cmd == "check":
        findings = filter_findings(check(a.dir, numbers=a.numbers, fuzzy=a.fuzzy, thai=a.thai), a.ignore, a.pack)
        if a.json:
            stdout.write(json.dumps({"summary": summary(findings), "findings": findings},
                                    ensure_ascii=False, indent=1) + "\n")
        else:
            stdout.write(format_findings(findings) + "\n")
        s = summary(findings)
        return 1 if s[ERROR] or (a.strict and s[WARNING]) else 0

    if a.cmd == "report":
        rep = report(a.dir)
        text = json.dumps(rep, ensure_ascii=False, indent=1) + "\n" if a.json else format_report(rep)
        if a.output:
            with open(a.output, "w", encoding="utf-8", newline="") as fh:
                fh.write(text)
        else:
            stdout.write(text)
        return 1 if rep["summary"][ERROR] else 0

    packs, errs = load_dir(a.dir)
    if errs and not packs:
        for f in errs:
            sys.stderr.write(f"{f['pack']}: {f['message']}\n")
        return 2
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
