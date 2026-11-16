#!/usr/bin/env python3
"""Erzeugt zu den Korpus-Sätzen (tests/corpus/*.json) Sprachaufnahmen mit macOS `say` – nur bei Bedarf und
nicht eingecheckt (*.wav steht in .gitignore; die Stimmen-Ausgabe ist nicht frei weiterverteilbar).

    python3 tests/corpus/make_audio.py                 # alle Quellsätze -> tests/corpus/audio/<id>.wav
    python3 tests/corpus/make_audio.py --ids en-th-01,en-th-09 --out /tmp/korpus

Format: WAV, 16 kHz, mono, 16 Bit – direkt für den Datei-Modus der Engine (DOLMETSCHER_MIC_FILE) und den
Benchmark nutzbar. Stimme je Sprache aus der Sprachtabelle der Engine (LANGS[...]["say"]); fehlt die Stimme
auf dem Rechner, wird der Fall mit Hinweis übersprungen. Nur „gute“ Fälle (ohne expect) bekommen Audio."""
import argparse
import json
import pathlib
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent))


def load_cases():
    """Alle Korpusfälle als Liste von dicts (mit src/dst aus dem Paar der Datei ergänzt)."""
    out = []
    for f in sorted(HERE.glob("*.json")):
        data = json.loads(f.read_text(encoding="utf-8"))
        pair = data.get("pair")
        for c in data["cases"]:
            c = dict(c, file=f.name)
            if pair:
                c.setdefault("dst", pair[1] if c["src"] == pair[0] else pair[0])
            out.append(c)
    return out


def say_cmd(voice, text, path):
    """say-Aufruf: WAV 16 kHz mono 16 Bit; `--` schützt Texte, die mit '-' beginnen."""
    return ["say", "-v", voice, "--file-format=WAVE", "--data-format=LEI16@16000", "-o", str(path), "--", text]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--ids", default="", help="nur diese IDs, kommagetrennt")
    ap.add_argument("--out", default=str(HERE / "audio"))
    a = ap.parse_args(argv)
    if not shutil.which("say"):
        sys.exit("braucht macOS `say`")
    import dolmetscher as d
    installed = subprocess.run(["say", "-v", "?"], capture_output=True, text=True).stdout
    ids = {x for x in a.ids.split(",") if x}
    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    n = 0
    for c in load_cases():
        if c.get("expect") or (ids and c["id"] not in ids):
            continue
        voice = d.LANGS[c["src"]]["say"]
        if not any(line.split("  ")[0].strip() == voice for line in installed.splitlines()):
            print(f"übersprungen {c['id']}: Stimme {voice} fehlt", file=sys.stderr)
            continue
        subprocess.run(say_cmd(voice, c["text"], out / f"{c['id']}.wav"), check=True)
        n += 1
    print(f"{n} Dateien in {out}")


if __name__ == "__main__":
    main()
