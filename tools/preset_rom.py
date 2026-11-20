#!/usr/bin/env python3
"""Optionales Feld `rom` (Lautschrift je Satz, phrases[].rom) pflegen. Runde 23.

Aufruf:  python3 tools/preset_rom.py --check [--pack ID ...]   (prueft rom-Felder, Exitcode 1 bei Fehlern)
         python3 tools/preset_rom.py --fill  [--pack ID ...]   (ergaenzt fehlende rom-Felder, braucht pythainlp)
         python3 tools/preset_rom.py --strip [--pack ID ...]   (entfernt alle rom-Felder)
`rom` ist freiwillig: Programme ohne Kenntnis des Feldes ignorieren es, `presets.validate` prueft nur Text und Laenge.
Die Lautschrift wird maschinell erzeugt (pythainlp `romanize`) und ist nur ein Vorschlag als Lesehilfe, keine
geprueften Angaben zur Aussprache; deshalb steht sie nie in `th` und wird von der Engine nicht gesprochen.
"""
import argparse
import json
import pathlib
import re
import sys
import unicodedata

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from _presetlib import load_packs  # noqa: E402
import presets as engine_presets  # noqa: E402

ROM_OK = re.compile(r"^[A-Za-zÀ-ɏ0-9 ,.?!'\-’]+$")  # Lateinische Buchstaben, Ziffern, Satzzeichen


def check_rom(fname, d):
    """Liste von Fehlertexten fuer die rom-Felder eines Pakets."""
    out = []
    for i, p in enumerate(d.get("phrases", [])):
        if not isinstance(p, dict) or "rom" not in p:
            continue
        r = p["rom"]
        w = "%s phrases[%d]" % (fname, i)
        if not isinstance(r, str) or not r.strip():
            out.append("%s: rom leer oder kein Text" % w)
        elif len(r) > engine_presets.MAX_ROM:
            out.append("%s: rom zu lang (%d)" % (w, len(r)))
        elif unicodedata.normalize("NFC", r) != r or r != r.strip() or "  " in r:
            out.append("%s: rom nicht normalisiert (NFC, Leerzeichen)" % w)
        elif not ROM_OK.match(r):
            out.append("%s: rom enthaelt unzulaessige Zeichen: %s" % (w, r))
    return out


def romanizer():
    try:
        from pythainlp.tokenize import word_tokenize  # type: ignore
        from pythainlp.transliterate import romanize  # type: ignore
    except ImportError:
        sys.exit("pythainlp fehlt: pip install pythainlp (nur fuer --fill noetig)")

    def rom(th):   # erst in Woerter zerlegen (ohne Zerlegung kommt Unsinn heraus), Reste mit Thai-Zeichen weglassen
        words = [romanize(w) for w in word_tokenize(th, keep_whitespace=False)]
        text = " ".join(w for w in words if w and not re.search("[฀-๿]", w))
        return " ".join(re.sub(r"[^A-Za-z0-9 ,.'\-]", "", text).split())
    return rom


def fill(packs, rom_fn, force=False):
    """Ergaenzt rom (rom_fn(th) -> str) in den Daten; gibt die Zahl geaenderter Saetze zurueck."""
    n = 0
    for _fname, d in packs:
        for p in d.get("phrases", []):
            if isinstance(p, dict) and isinstance(p.get("th"), str) and (force or "rom" not in p):
                r = " ".join(str(rom_fn(p["th"])).split())
                if r:
                    p["rom"] = r
                    n += 1
    return n


def strip(packs):
    n = 0
    for _fname, d in packs:
        for p in d.get("phrases", []):
            if isinstance(p, dict) and "rom" in p:
                del p["rom"]
                n += 1
    return n


def save(packs, directory=None):
    folder = pathlib.Path(directory) if directory else pathlib.Path(__file__).resolve().parent.parent / "presets"
    for fname, d in packs:
        (folder / fname).write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Optionales Feld rom (Lautschrift) pruefen, ergaenzen oder entfernen.")
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--fill", action="store_true")
    mode.add_argument("--strip", action="store_true")
    ap.add_argument("--dir")
    ap.add_argument("--pack", action="append", default=[], metavar="ID")
    ap.add_argument("--force", action="store_true", help="mit --fill auch vorhandene rom-Felder ersetzen")
    a = ap.parse_args(argv)
    packs = load_packs(a.dir, a.pack)
    if a.check:
        errs = [e for fname, d in packs for e in check_rom(fname, d)]
        for e in errs:
            print("E " + e)
        print("%d Pakete, %d Fehler" % (len(packs), len(errs)))
        return 1 if errs else 0
    n = fill(packs, romanizer(), a.force) if a.fill else strip(packs)
    save(packs, a.dir)
    print("%d Saetze geaendert" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
