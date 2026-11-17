"""Szenario-Presets und Phrasenpakete als Daten (presets/*.json, siehe docs/PROTOKOLL.md).

Laden aus dem App-Verzeichnis (neben diesem Modul, `presets/`) und aus dem Nutzer-Verzeichnis
(`$DOLMETSCHER_HOME/presets`, Standard ~/Library/Application Support/Dolmetscher/presets).
Gleiche `id` im Nutzer-Verzeichnis überschreibt das mitgelieferte Preset. Ungültige Dateien werden
übersprungen (kein Absturz), der Grund steht in `last_errors`.
"""
import json
import os
import re

STYLE_KEYS = ("casual", "neutral", "polite")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,31}$")
MAX_GLOSSARY, MAX_PHRASES = 100, 50
MAX_NAME, MAX_TERM, MAX_PHRASE, MAX_NOTE = 40, 60, 200, 500
MAX_HOTWORDS, MAX_HINT = 30, 300          # Nr. 243: eigene Whisper-Hotwords und Ton-Hinweis für Claude
last_errors = {}                          # Dateipfad -> Fehlertext des letzten load_all()
overridden = []                           # ids, die ein Nutzer-Preset beim letzten load_all() ersetzt hat


def home():
    return os.environ.get("DOLMETSCHER_HOME") or os.path.expanduser("~/Library/Application Support/Dolmetscher")


def app_dir():
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "presets")


def user_dir():
    return os.path.join(home(), "presets")


def _text(v, limit):
    return isinstance(v, str) and 0 < len(v.strip()) <= limit


def validate(d):
    """Liste von Fehlertexten (leer = gültig)."""
    if not isinstance(d, dict):
        return ["kein Objekt"]
    err = []
    if not (isinstance(d.get("id"), str) and ID_RE.match(d["id"])):
        err.append("id ungültig (a-z, 0-9, _ -, max. 32)")
    names = d.get("names")
    if not isinstance(names, dict) or not all(_text(names.get(k), MAX_NAME) for k in ("de", "en", "th")):
        err.append(f"names braucht de/en/th (1-{MAX_NAME} Zeichen)")
    if d.get("style") not in STYLE_KEYS:
        err.append("style muss casual, neutral oder polite sein")
    if "polite" in d and d["polite"] not in ("krub", "ka"):
        err.append("polite muss krub oder ka sein")
    if "voice" in d and not (isinstance(d["voice"], dict) and set(d["voice"]) <= {"en", "th"}
                             and all(_text(v, 64) for v in d["voice"].values())):
        err.append("voice muss {en?, th?} mit Stimmnamen sein")
    for key, limit, mx in (("glossary", MAX_TERM, MAX_GLOSSARY), ("phrases", MAX_PHRASE, MAX_PHRASES)):
        items = d.get(key, [])
        if not isinstance(items, list) or len(items) > mx:
            err.append(f"{key} muss eine Liste mit höchstens {mx} Einträgen sein")
            continue
        for i, it in enumerate(items):
            if not (isinstance(it, dict) and _text(it.get("en"), limit) and _text(it.get("th"), limit)):
                err.append(f"{key}[{i}] braucht en und th (1-{limit} Zeichen)")
            elif key == "phrases" and "critical" in it and not isinstance(it["critical"], bool):
                err.append(f"phrases[{i}].critical muss true oder false sein")
    note = d.get("note")                  # optional: Kultur-/Sicherheitshinweis {de, en, th?}
    if "note" in d and not (isinstance(note, dict) and set(note) <= {"de", "en", "th"}
                            and all(_text(note.get(k), MAX_NOTE) for k in ("de", "en"))
                            and all(_text(v, MAX_NOTE) for v in note.values())):
        err.append(f"note muss {{de, en, th?}} mit Texten (1-{MAX_NOTE} Zeichen) sein")
    hw = d.get("hotwords", [])
    if not (isinstance(hw, list) and len(hw) <= MAX_HOTWORDS and all(_text(w, MAX_TERM) for w in hw)):
        err.append(f"hotwords muss eine Liste mit höchstens {MAX_HOTWORDS} Begriffen (1-{MAX_TERM} Zeichen) sein")
    if "llm_hint" in d and not _text(d["llm_hint"], MAX_HINT):
        err.append(f"llm_hint muss ein Text mit 1-{MAX_HINT} Zeichen sein")
    extra = set(d) - {"id", "names", "style", "polite", "voice", "note", "glossary", "phrases", "hotwords",
                      "llm_hint"}
    if extra:
        err.append("unbekannte Felder: " + ", ".join(sorted(extra)))
    return err


def load_all():
    """{id: preset}. Nutzer-Verzeichnis überschreibt das App-Verzeichnis."""
    out = {}
    last_errors.clear()
    overridden.clear()
    for folder in (app_dir(), user_dir()):
        try:
            files = sorted(f for f in os.listdir(folder) if f.endswith(".json"))
        except OSError:
            continue
        for fn in files:
            path = os.path.join(folder, fn)
            try:
                with open(path, encoding="utf-8") as f:
                    d = json.load(f)
            except (OSError, ValueError) as e:
                last_errors[path] = "lesen: " + repr(e)[:100]
                continue
            err = validate(d)
            if err:
                last_errors[path] = "; ".join(err)
                continue
            if d["id"] in out and folder == user_dir():
                overridden.append(d["id"])
            out[d["id"]] = d
    return out


def app_fields(preset):
    """Felder für die App im `preset`-Ereignis: Kulturhinweis `note` ({de, en, th?} oder None) und die
    Schnellsätze `phrases` [{en, th, critical}] – kritische Sätze (Notfall, Allergie …) hebt die App hervor."""
    if not preset:
        return {"note": None, "phrases": []}
    note = preset.get("note")
    return {"note": dict(note) if isinstance(note, dict) else None,
            "phrases": [{"en": ph["en"], "th": ph["th"], "critical": bool(ph.get("critical"))}
                        for ph in preset.get("phrases", [])]}


def glossary_entries(preset):
    """Glossar-Paare (Wort, Übersetzung) in beide Richtungen EN⇄TH."""
    items = []
    for g in preset.get("glossary", []):
        items.append((g["en"], g["th"]))
        items.append((g["th"], g["en"]))
    return items


def find(spoken, presets=None):
    """Gesprochenen Namen (id oder Name in de/en/th, ohne Klammerzusatz) -> id oder None."""
    s = re.sub(r"[^\w\s]", " ", (spoken or "").lower()).strip()
    s = re.sub(r"\s+", " ", s)
    if not s:
        return None
    for pid, p in (presets if presets is not None else load_all()).items():
        names = {pid, *(re.sub(r"\s*\(.*?\)", "", v).lower() for v in p["names"].values())}
        if s in names:
            return pid
    return None


class PresetState:
    """Merkt den Zustand vor dem ersten Preset und stellt ihn bei „kein Preset“ wieder her."""

    def __init__(self):
        self.active = None
        self.saved = None
        self.hotwords, self.hint = [], None      # Nr. 243: aus dem aktiven Preset

    def activate(self, pid, presets, glossary, llm, eng, glossary_limit=200):
        """Preset anwenden (pid=None/"none": zurück). Gibt das Preset oder None zurück.
        Unbekannte id -> KeyError, Zustand bleibt unverändert."""
        p = None
        if pid not in (None, "", "none"):
            p = presets[pid]
        if self.saved is not None:                       # erst alten Zustand wiederherstellen
            llm["style"] = self.saved["style"]
            eng.polite = self.saved["polite"]
            eng.voices.update(self.saved["voices"])
            glossary[:] = self.saved["glossary"]
            self.saved = None
        self.active = None
        self.hotwords, self.hint = [], None
        if p is None:
            return None
        self.hotwords = [w.strip() for w in p.get("hotwords", [])]
        self.hint = p["llm_hint"].strip() if p.get("llm_hint") else None
        self.saved = {"style": llm["style"], "polite": eng.polite, "glossary": list(glossary),
                      "voices": {k: eng.voices.get(k) for k in ("en", "th")}}
        self.active = pid
        llm["style"] = p["style"]
        if p.get("polite"):
            eng.polite = p["polite"]
        for k, v in p.get("voice", {}).items():
            eng.voices[k] = v
        own = {a.lower() for a, _ in glossary}               # eigene Einträge haben Vorrang
        extra = [(a, b) for a, b in glossary_entries(p) if a.lower() not in own]
        glossary[:] = (list(glossary) + extra)[:glossary_limit]
        return p


def parse_spoken(cmd, presets=None):
    """Sprachbefehl „hotel mode“ / „preset hotel“ / „preset off“ -> "preset:<id>" oder None.
    Nur kurze Äußerungen (höchstens 5 Wörter); alles andere bleibt unberührt."""
    words = re.findall(r"[\w'-]+", (cmd or "").lower())
    if not 2 <= len(words) <= 5:
        return None
    if words[0] == "preset":
        rest = words[1:]
    elif words[-1] == "mode":
        rest = words[:-1]
    else:
        return None
    if words[0] == "preset" and rest in (["off"], ["none"], ["clear"], ["reset"]):
        return "preset:none"
    pid = find(" ".join(rest), presets)
    return f"preset:{pid}" if pid else None
