#!/usr/bin/env python3
# ruff: noqa: E501
"""Sprachliche Pruefung der Thai-Saetze (Runde 25), ergaenzt check_presets.py um typische maschinelle Fehler.

Aufruf:  python3 tools/preset_lint.py [--pack ID ...] [--strict]
Regeln (alle ohne Woerterbuch, nur Muster; Treffer sind Hinweise fuer eine Durchsicht, kein Urteil eines Muttersprachlers):
  register  unhoefliche oder vertraute Wortformen (เธอ, มึง, กู, ข้าพเจ้า, จ้ะ, อ่ะ, ป่าว), ฉัน, Satzende-นะ
  clunky    doppelte Bitten im selben Satz (ช่วย ... ช่วย, ขอให้ ... ให้ ... ให้), „จนกว่า ... ก่อน“, „ขอให้ปล่อยให้“
  digits    Notrufnummern passen zum Dienst im englischen Satz: Rettungsdienst 1669, Polizei 191, Touristenpolizei 1155, Feuerwehr 199
  question  englische Frage, aber Thai ohne Fragewort und ohne Bitte (ขอ/ช่วย): vermutlich fehlt ไหม o. ae.
  names     Eigennamen einheitlich: ไวไฟ (nicht ไวฟาย), แท็กซี่ (nicht แท็กซี), วีซ่า (nicht วีซา)
Exitcode 1 bei Fehlern (E); Hinweise (W) zaehlen mit --strict.
"""
import argparse
import re
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _presetlib import load_packs  # noqa: E402

REGISTER = re.compile(r"(?:^|\s)(?:เธอ|มึง|กู|ข้าพเจ้า)(?:\s|$)|จ้ะ|จ๊ะ|อ่ะ|ป่าว|ฉัน|นะ\s*$")
CLUNKY = [
    (re.compile(r"ขอให้ปล่อยให้"), "ขอให้ ... ให้ doppelt"),
    (re.compile(r"จนกว่า.*ก่อน"), "จนกว่า und ก่อน zugleich"),
    (re.compile(r"^ช่วย[^ ]*ช่วย(?!ชีวิต|เหลือ|ด้วย)"), "zwei ช่วย im selben Satzteil"),
    (re.compile(r"ด้วย\s*หน่อย$|หน่อย\s*ด้วย$"), "ด้วย und หน่อย zugleich am Satzende"),
]
QUESTION_WORDS = re.compile(r"ไหม|หรือ|ไหน|อะไร|เท่าไร|เท่าไหร่|กี่|ใคร|อย่างไร|ยังไง|เมื่อไร|เมื่อไหร่|ทำไม|มั้ย|บ้าง|แค่ไหน|เท่าใด|นานเท่า|ใช่|ใด")
REQUEST = re.compile(r"(?:^|\s)(?:ขอ|ช่วย)")
VARIANTS = {"ไวฟาย": "ไวไฟ", "แท็กซี(?!่)": "แท็กซี่", "วีซา": "วีซ่า"}
SERVICES = [("tourist police", "1155"), ("ambulance", "1669"), ("fire brigade", "199"), ("police", "191")]
NUM = re.compile(r"(?<!\d)(1669|1155|191|199)(?!\d)")


def lint_phrase(en, th):
    """Liste (Stufe, Regel, Text) fuer einen Satz."""
    out = []
    if REGISTER.search(th):
        out.append(("E", "register", "vertraute oder unhoefliche Form"))
    for rx, why in CLUNKY:
        if rx.search(th):
            out.append(("W", "clunky", why))
    low = en.lower()
    svc = next((n for key, n in SERVICES if key in low), None)
    for num in sorted(set(NUM.findall(en) + NUM.findall(th))):
        if svc and num != svc:
            out.append(("E", "digits", "Nummer %s passt nicht zum Dienst im englischen Satz (erwartet %s)" % (num, svc)))
        elif not svc:
            out.append(("W", "digits", "Nummer %s ohne passenden Dienst im englischen Satz" % num))
    if en.rstrip().endswith("?") and not QUESTION_WORDS.search(th) and not REQUEST.search(th):
        out.append(("W", "question", "englische Frage ohne Fragewort im Thai"))
    for bad, good in VARIANTS.items():
        if re.search(bad, th):
            out.append(("W", "names", "%s besser %s" % (bad.split("(")[0], good)))
    return out


def lint(packs):
    res = []
    for fname, d in packs:
        for i, p in enumerate(d.get("phrases", [])):
            if isinstance(p, dict) and isinstance(p.get("en"), str) and isinstance(p.get("th"), str):
                for lv, rule, msg in lint_phrase(p["en"], p["th"]):
                    res.append((lv, "%s phrases[%d]" % (fname, i), "%s: %s | %s" % (rule, msg, p["th"])))
    return res


def main(argv=None):
    ap = argparse.ArgumentParser(description="Thai-Saetze der Phrasenpakete sprachlich pruefen.")
    ap.add_argument("--pack", action="append", default=[], metavar="ID")
    ap.add_argument("--dir")
    ap.add_argument("--strict", action="store_true", help="Hinweise zaehlen als Fehler")
    a = ap.parse_args(argv)
    packs = load_packs(a.dir, a.pack)
    res = lint(packs)
    for lv, where, msg in res:
        print("%s %s: %s" % (lv, where, msg))
    errors = sum(1 for lv, _w, _m in res if lv == "E")
    print("%d Pakete, %d Fehler, %d Hinweise" % (len(packs), errors, len(res) - errors))
    return 1 if errors or (a.strict and res) else 0


if __name__ == "__main__":
    sys.exit(main())
