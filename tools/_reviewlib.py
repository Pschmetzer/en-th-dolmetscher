"""Gemeinsame Helfer der Pruefbogen-Werkzeuge (review_export, review_import, review_status). Nur Standardbibliothek."""
import csv
import io
import json
import pathlib
import sys
import unicodedata

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _presetlib import DEFAULT_DIR, load_packs  # noqa: E402,F401

COLUMNS = ["id", "en", "de", "th", "Status", "Korrektur", "Kommentar"]
STATUS_OK = "ok"
STATUS_FIXED = "korrigiert"
STATUS_UNCLEAR = "unklar"
STATUSES = (STATUS_OK, STATUS_FIXED, STATUS_UNCLEAR)
FORMULA_START = ("=", "+", "-", "@", "\t", "\r")
MAX_TEXT = 200
MAX_COMMENT = 500


def row_id(pack_id, index):
    """Zeilen-ID: Paket-ID, Doppelpunkt, 1-basierte Position in der Datei (nicht in der Anzeigereihenfolge)."""
    return "%s:%02d" % (pack_id, index + 1)


def split_id(rid):
    pack, sep, num = str(rid).rpartition(":")
    if not sep or not pack or not num.isdigit():
        return None
    return pack, int(num) - 1


def protect(value):
    """Formel-Schutz fuer Tabellenprogramme: gefaehrliche Anfaenge bekommen ein Hochkomma davor."""
    s = str(value)
    return "'" + s if s.startswith(FORMULA_START) else s


def unprotect(value):
    s = str(value)
    return s[1:] if s.startswith("'") and s[1:].startswith(FORMULA_START) else s


def has_control(text):
    """Steuer- und Formatzeichen (ausser normalem Leerzeichen) sind in Saetzen nicht erlaubt."""
    return any(unicodedata.category(c) in ("Cc", "Cf", "Cs", "Co", "Cn") or c in "  " for c in text)


def md_cell(text):
    return str(text).replace("\\", "\\\\").replace("|", "\\|")


def md_split(line):
    cells, cur, i = [], [], 0
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|") and not line.endswith("\\|"):
        line = line[:-1]
    while i < len(line):
        c = line[i]
        if c == "\\" and i + 1 < len(line) and line[i + 1] in "\\|":
            cur.append(line[i + 1])
            i += 2
            continue
        if c == "|":
            cells.append("".join(cur).strip())
            cur = []
        else:
            cur.append(c)
        i += 1
    cells.append("".join(cur).strip())
    return cells


def read_sheet(path):
    """Liest einen Bogen (.csv oder .md) -> Liste von Dicts je Zeile. Wirft ValueError mit lesbarer Meldung."""
    p = pathlib.Path(path)
    try:
        raw = p.read_bytes()
    except OSError as e:
        raise ValueError("Bogen nicht lesbar: %s" % e)
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        raise ValueError("Bogen ist nicht UTF-8 (in Excel als CSV UTF-8 speichern)")
    if p.suffix.lower() == ".md":
        lines = [ln for ln in text.splitlines() if ln.strip().startswith("|")]
        if len(lines) < 2:
            raise ValueError("keine Markdown-Tabelle gefunden")
        head = md_split(lines[0])
        body = [md_split(ln) for ln in lines[2:]]
    else:
        first = text.split("\n", 1)[0]
        delim = max(",;\t", key=first.count) if any(d in first for d in ",;\t") else ","
        rows = list(csv.reader(io.StringIO(text, newline=""), delimiter=delim))
        rows = [r for r in rows if any(c.strip() for c in r)]
        if not rows:
            raise ValueError("Bogen ist leer")
        head, body = [c.strip() for c in rows[0]], rows[1:]
    missing = [c for c in COLUMNS if c not in head]
    if missing:
        raise ValueError("Spalten fehlen: %s" % ", ".join(missing))
    out = []
    for n, cells in enumerate(body, 2):
        if len(cells) != len(head):
            raise ValueError("Zeile %d: %d Spalten statt %d" % (n, len(cells), len(head)))
        d = dict(zip(head, cells))
        d["_line"] = n
        out.append(d)
    return out


def index_path(directory):
    return pathlib.Path(directory).resolve().parent / "presets-index.json"


def read_index(directory):
    f = index_path(directory)
    if not f.exists():
        return None
    try:
        return json.loads(f.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        sys.exit("%s: nicht lesbar (%s)" % (f.name, e))


def dump_pack(data):
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"
