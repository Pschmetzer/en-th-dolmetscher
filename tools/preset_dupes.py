#!/usr/bin/env python3
"""Doppelte Saetze zwischen Paketen melden und per Verweis entschaerfen. Runde 27.

Aufruf:  python3 tools/preset_dupes.py                 (Bericht: Paare mit mindestens --min gemeinsamen Saetzen)
         python3 tools/preset_dupes.py --apply         (haengt an note.de/note.en einen Satz "Siehe auch: ..." an)
         python3 tools/preset_dupes.py --check         (Exitcode 1, wenn --apply noch etwas aendern wuerde)
Die Saetze selbst bleiben in beiden Paketen (jedes Paket muss allein benutzbar sein); der Verweis hilft beim Wechsel
zum thematisch verwandten Paket. Hoechstens zwei Verweise je Paket, nur bei klarer Ueberschneidung, nur wenn die Notiz
danach noch in die Grenze von 500 Zeichen passt. Der Verweis steht vor dem Hinweis auf die maschinelle Uebersetzung.
"""
import argparse
import itertools
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _presetlib import load_packs  # noqa: E402

MARK = {"de": "Siehe auch: ", "en": "See also: "}
TAIL = {"de": " Thai-Sätze maschinell", "en": " Thai lines machine"}
MAX_NOTE = 500


def overlaps(packs, minimum=3):
    """[(gemeinsame Saetze, id_a, id_b)] absteigend; nur Paare ab `minimum`."""
    sent = {}
    for _f, d in packs:
        sent[d["id"]] = {p["en"].strip().lower() for p in d.get("phrases", []) if isinstance(p, dict) and p.get("en")}
    out = [(len(sent[a] & sent[b]), a, b) for a, b in itertools.combinations(sorted(sent), 2)]
    return sorted([o for o in out if o[0] >= minimum], key=lambda o: (-o[0], o[1], o[2]))


def see_also(packs, minimum=3, limit=2):
    """{id: [verwandte ids]} aus den staerksten Ueberschneidungen (je Paket hoechstens `limit`)."""
    rel = {}
    for n, a, b in overlaps(packs, minimum):
        for x, y in ((a, b), (b, a)):
            if len(rel.setdefault(x, [])) < limit:
                rel[x].append(y)
    return rel


def apply_note(note, lang, ref_names):
    """note[lang] mit Verweis; None, wenn schon vorhanden oder zu lang."""
    text = note.get(lang, "")
    if not text or MARK[lang] in text or not ref_names:
        return None
    sentence = MARK[lang] + ", ".join(ref_names) + "."
    pos = text.find(TAIL[lang])
    new = text[:pos] + " " + sentence + text[pos:] if pos >= 0 else text.rstrip() + " " + sentence
    return new if len(new) <= MAX_NOTE else None


def apply(packs, minimum=3, limit=2):
    """Aendert die Notizen in `packs` (Liste [(dateiname, daten)]); gibt die Namen geaenderter Dateien zurueck."""
    by_id = {d["id"]: d for _f, d in packs}
    changed = []
    for pid, refs in see_also(packs, minimum, limit).items():
        d = by_id[pid]
        note = d.get("note")
        if not isinstance(note, dict):
            continue
        touched = False
        for lang in ("de", "en"):
            names = [by_id[r]["names"][lang] for r in refs]
            new = apply_note(note, lang, names)
            if new:
                note[lang] = new
                touched = True
        if touched:
            changed.append(pid + ".json")
    return changed


def main(argv=None):
    ap = argparse.ArgumentParser(description="Doppelte Saetze zwischen Paketen melden und per Verweis entschaerfen.")
    ap.add_argument("--dir")
    ap.add_argument("--min", type=int, default=3, help="gemeinsame Saetze ab denen gemeldet wird (Standard 3)")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args(argv)
    packs = load_packs(a.dir)
    if a.apply or a.check:
        changed = apply(packs, a.min)
        if a.check:
            for c in changed:
                print("E %s: Verweis fehlt (python3 tools/preset_dupes.py --apply)" % c)
            return 1 if changed else 0
        folder = pathlib.Path(a.dir) if a.dir else pathlib.Path(__file__).resolve().parent.parent / "presets"
        for fname, d in packs:
            if fname in changed:
                (folder / fname).write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("%d Pakete mit Verweis ergaenzt" % len(changed))
        return 0
    rows = overlaps(packs, a.min)
    for n, x, y in rows[:40]:
        print("%3d  %s  <->  %s" % (n, x, y))
    print("%d Paare mit mindestens %d gemeinsamen Saetzen" % (len(rows), a.min))
    return 0


if __name__ == "__main__":
    sys.exit(main())
