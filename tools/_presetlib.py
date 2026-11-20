"""Gemeinsame Helfer der Paket-Werkzeuge (export_phrasebook, check_presets, preset_stats). Nur Standardbibliothek."""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_DIR = ROOT / "presets"


def load_packs(directory=None, ids=None):
    """Liest Pakete sortiert nach Dateiname. Gibt [(dateiname, daten)] zurueck.
    Defekte Dateien werden alle gesammelt und gemeinsam gemeldet (Exit 2), nicht nur die erste."""
    folder = pathlib.Path(directory) if directory else DEFAULT_DIR
    if not folder.is_dir():
        sys.exit("Ordner nicht gefunden: %s" % folder)
    packs, broken = [], []
    for f in sorted(folder.glob("*.json")):
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            broken.append("%s: nicht lesbar (%s)" % (f.name, e))
            continue
        if not isinstance(data, dict):
            broken.append("%s: kein JSON-Objekt" % f.name)
            continue
        if ids and data.get("id", f.stem) not in ids and f.stem not in ids:
            continue
        packs.append((f.name, data))
    if broken:
        sys.exit("\n".join(broken))
    if ids:
        known = {d.get("id", n[:-5]) for n, d in packs} | {n[:-5] for n, _ in packs}
        missing = sorted(set(ids) - known)
        if missing:
            sys.exit("Unbekannte Paket-ID: %s" % ", ".join(missing))
    return packs


def phrases_of(data):
    """Saetze mit kritischen zuerst (stabil), wie die Apps sie zeigen."""
    ph = [p for p in data.get("phrases", []) if isinstance(p, dict)]
    return sorted(ph, key=lambda p: not p.get("critical"))


def norm(text):
    return " ".join(str(text).split()).casefold()


def is_thai_char(ch):
    return "฀" <= ch <= "๿"
