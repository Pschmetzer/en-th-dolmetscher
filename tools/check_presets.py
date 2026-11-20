#!/usr/bin/env python3
"""Prueft Phrasenpakete: Schema, Dubletten, fehlende Uebersetzungen, Thai-Zeichen, Laenge, Konsistenz.

Aufruf:  python3 tools/check_presets.py [--dir ORDNER] [--pack ID ...] [--strict] [--json]
Fehler (E) -> Exitcode 1. Warnungen (W) -> Exitcode 0, mit --strict ebenfalls 1.
Pruefungen: Schema wie docs/presets.schema.json; Dubletten im Paket; leere/gleiche en/th; Thai-Schrift in th,
keine Hoeflichkeitspartikel/ฉัน/ผม/Satzende-นะ; Laenge (>200 Fehler, >120 Warnung); gleicher englischer Satz mit
verschiedener Thai-Uebersetzung in mehreren Paketen (Warnung).
"""
import argparse
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from _presetlib import is_thai_char, load_packs, norm  # noqa: E402
import presets as engine_presets  # noqa: E402  (Laufzeit-Schema: eine Quelle fuer Felder, hotwords, tuning)

KEYS = {"id", "names", "style", "polite", "voice", "note", "glossary", "phrases", "hotwords", "llm_hint", "tuning"}
STYLES = {"casual", "neutral", "polite"}
PARTICLES = re.compile(r"(ครับ|ค่ะ|คะ)")
PRONOUNS = re.compile(r"(ฉัน|^ผม)")  # ผม mitten im Satz heisst oft "Haar"
NUMBERS = re.compile(r"\d+")        # Notrufnummern, Preise, Uhrzeiten muessen in beiden Sprachen gleich sein
WARN_LEN = 120
MAX_LEN = 200


def _text(v, lo, hi, where, out, level="E"):
    if not isinstance(v, str):
        out.append((level, where, "kein Text"))
    elif not lo <= len(v.strip() if lo else v) <= hi:
        out.append((level, where, "Laenge %d ausserhalb %d-%d" % (len(v), lo, hi)))


def check_schema(fname, d, out):
    for k in sorted(set(d) - KEYS):
        out.append(("E", fname, "unbekanntes Feld '%s'" % k))
    pid = d.get("id")
    if not isinstance(pid, str) or not re.fullmatch(r"[a-z0-9_-]{1,32}", pid):
        out.append(("E", fname, "id ungueltig"))
    elif pid != fname[:-5]:
        out.append(("E", fname, "id '%s' ungleich Dateiname" % pid))
    names = d.get("names")
    if not isinstance(names, dict):
        out.append(("E", fname, "names fehlt"))
    else:
        for lang in ("de", "en", "th"):
            _text(names.get(lang), 1, 40, "%s names.%s" % (fname, lang), out)
    if d.get("style") not in STYLES:
        out.append(("E", fname, "style muss casual, neutral oder polite sein"))
    if "polite" in d and d["polite"] not in ("krub", "ka"):
        out.append(("E", fname, "polite muss krub oder ka sein"))
    note = d.get("note")
    if note is not None:
        if not isinstance(note, dict):
            out.append(("E", fname, "note muss ein Objekt sein"))
        else:
            for lang in ("de", "en"):
                _text(note.get(lang), 1, 500, "%s note.%s" % (fname, lang), out)
            if "th" in note:
                _text(note["th"], 1, 500, "%s note.th" % fname, out)
    for msg in engine_presets.validate(d):        # Laufzeit-Schema der App (hotwords, llm_hint, tuning, Grenzen)
        if "unbekannte Felder" not in msg and not msg.startswith("id ungültig"):
            out.append(("E", fname, "presets.validate: " + msg))
    gl = d.get("glossary", [])
    if not isinstance(gl, list) or len(gl) > 100:
        out.append(("E", fname, "glossary: Liste mit hoechstens 100 Paaren"))
    else:
        for i, g in enumerate(gl):
            if not isinstance(g, dict):
                out.append(("E", fname, "glossary[%d] kein Objekt" % i))
                continue
            for lang in ("en", "th"):
                _text(g.get(lang), 1, 60, "%s glossary[%d].%s" % (fname, i, lang), out)
    ph = d.get("phrases", [])
    if not isinstance(ph, list) or len(ph) > 50:
        out.append(("E", fname, "phrases: Liste mit hoechstens 50 Saetzen"))


def check_phrases(fname, d, out):
    seen_en, seen_th = {}, {}
    ph = d.get("phrases", [])
    if not isinstance(ph, list):
        return
    for i, p in enumerate(ph):
        w = "%s phrases[%d]" % (fname, i)
        if not isinstance(p, dict):
            out.append(("E", w, "kein Objekt"))
            continue
        en, th = p.get("en"), p.get("th")
        if "critical" in p and not isinstance(p["critical"], bool):
            out.append(("E", w, "critical muss true/false sein"))
        if not isinstance(en, str) or not en.strip():
            out.append(("E", w, "englische Fassung fehlt"))
            en = None
        if not isinstance(th, str) or not th.strip():
            out.append(("E", w, "Thai-Uebersetzung fehlt"))
            th = None
        for lang, v in (("en", en), ("th", th)):
            if v is None:
                continue
            if len(v) > MAX_LEN:
                out.append(("E", w, "%s: %d Zeichen (max %d)" % (lang, len(v), MAX_LEN)))
            elif len(v) > WARN_LEN:
                out.append(("W", w, "%s: %d Zeichen, lang fuer Karte/Sprachausgabe" % (lang, len(v))))
        if en is not None:
            if norm(en) in seen_en:
                out.append(("E", w, "Dublette von phrases[%d] (en)" % seen_en[norm(en)]))
            seen_en.setdefault(norm(en), i)
        if th is not None:
            if norm(th) in seen_th:
                out.append(("E", w, "Dublette von phrases[%d] (th)" % seen_th[norm(th)]))
            seen_th.setdefault(norm(th), i)
            if en is not None and norm(en) == norm(th):
                out.append(("E", w, "th ist gleich en (nicht uebersetzt)"))
            if not any(is_thai_char(c) for c in th):
                out.append(("E", w, "th enthaelt keine Thai-Schrift"))
            else:
                core = th.replace("___", "")
                if re.search(r"[A-Za-z]", core):
                    out.append(("W", w, "th enthaelt lateinische Buchstaben"))
                if PARTICLES.search(th):
                    out.append(("E", w, "Hoeflichkeitspartikel in der Datei (Engine ergaenzt sie)"))
                if PRONOUNS.search(th):
                    out.append(("E", w, "Pronomen ฉัน/ผม am Anfang (Subjekt weglassen)"))
                if th.rstrip(" ?!.").endswith("นะ"):
                    out.append(("E", w, "vertrautes นะ am Satzende"))
            if en is not None and ("___" in en) != ("___" in th):
                out.append(("E", w, "Luecke ___ nur in einer Sprache"))
            # Thai darf Zahlen als Wort schreiben (หกโมง): nur pruefen, wenn th Ziffern enthaelt
            if en is not None and NUMBERS.search(th) and sorted(NUMBERS.findall(en)) != sorted(NUMBERS.findall(th)):
                out.append(("W", w, "Zahlen in en und th verschieden (%s / %s)"
                            % (" ".join(NUMBERS.findall(en)) or "-", " ".join(NUMBERS.findall(th)) or "-")))
        if "{p}" in str(en) + str(th):
            out.append(("E", w, "{p}-Platzhalter nicht erlaubt"))


def check_consistency(packs, out):
    by_en = {}
    for fname, d in packs:
        for i, p in enumerate(d.get("phrases", []) if isinstance(d.get("phrases"), list) else []):
            if isinstance(p, dict) and isinstance(p.get("en"), str) and isinstance(p.get("th"), str):
                by_en.setdefault(norm(p["en"]), []).append((fname, i, p["th"]))
    for key in sorted(by_en):
        items = by_en[key]
        if len({norm(t) for _f, _i, t in items}) > 1 and len({f for f, _i, _t in items}) > 1:
            where = ", ".join("%s[%d]" % (f, i) for f, i, _t in items)
            out.append(("W", where, "gleicher englischer Satz '%s' mit unterschiedlicher Thai-Fassung" % key))


def run(packs):
    out = []
    for fname, d in packs:
        check_schema(fname, d, out)
        check_phrases(fname, d, out)
    check_consistency(packs, out)
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description="Phrasenpakete pruefen (Schema, Dubletten, Thai, Laenge, Konsistenz).")
    ap.add_argument("--dir", help="Paket-Ordner (Standard: presets/ im Repo)")
    ap.add_argument("--pack", action="append", default=[], metavar="ID", help="nur dieses Paket (mehrfach moeglich)")
    ap.add_argument("--strict", action="store_true", help="Warnungen zaehlen als Fehler")
    ap.add_argument("--json", action="store_true", help="Ausgabe als JSON")
    a = ap.parse_args(argv)
    packs = load_packs(a.dir, a.pack)
    res = run(packs)
    errors = sum(1 for lv, _w, _m in res if lv == "E")
    warns = len(res) - errors
    if a.json:
        print(json.dumps({"packs": len(packs), "errors": errors, "warnings": warns,
                          "findings": [{"level": lv, "where": w, "message": m} for lv, w, m in res]},
                         ensure_ascii=False, indent=1))
    else:
        for lv, w, m in res:
            print("%s %s: %s" % (lv, w, m))
        print("%d Pakete, %d Fehler, %d Warnungen" % (len(packs), errors, warns))
    return 1 if errors or (a.strict and warns) else 0


if __name__ == "__main__":
    sys.exit(main())
