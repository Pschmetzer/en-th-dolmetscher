"""Szenario-Presets und Phrasenpakete als Daten (presets/*.json, siehe docs/PROTOKOLL.md).

Laden aus dem App-Verzeichnis (neben diesem Modul, `presets/`) und aus dem Nutzer-Verzeichnis
(`$DOLMETSCHER_HOME/presets`, Standard ~/Library/Application Support/Dolmetscher/presets).
Gleiche `id` im Nutzer-Verzeichnis überschreibt das mitgelieferte Preset. Ungültige Dateien werden
übersprungen (kein Absturz), der Grund steht in `last_errors`.
"""
import json
import os
import re
import unicodedata

STYLE_KEYS = ("casual", "neutral", "polite")
ID_RE = re.compile(r"[a-z0-9][a-z0-9_-]{0,31}")
MAX_GLOSSARY, MAX_PHRASES = 100, 50
MAX_NAME, MAX_TERM, MAX_PHRASE, MAX_NOTE = 40, 60, 200, 500
MAX_FILE = 256 * 1024                     # größere Preset-Dateien werden nicht gelesen (Schutz vor Riesendateien)
MAX_HOTWORDS, MAX_HINT = 30, 300          # Nr. 243: eigene Whisper-Hotwords und Ton-Hinweis für Claude
# Runde 7: tuning = {silence, sensitivity, let_finish, catch_up, rate} je Szenario (Bereiche wie die Steuerfelder)
TUNING_RANGES = {"silence": (0.4, 2.0), "let_finish": (0.0, 5.0), "rate": (-50, 50),
                 "sensitivity": ("low", "normal", "high"), "catch_up": ("skip", "fast", "off")}
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
    if not (isinstance(d.get("id"), str) and ID_RE.fullmatch(d["id"])):
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
    tun = d.get("tuning")                 # Runde 7: optionale Szenario-Einstellungen
    if "tuning" in d:
        ok = isinstance(tun, dict) and set(tun) <= set(TUNING_RANGES)
        for k, v in (tun.items() if isinstance(tun, dict) else ()):
            rng = TUNING_RANGES.get(k)
            if rng and isinstance(rng[0], (int, float)):
                ok = ok and isinstance(v, (int, float)) and not isinstance(v, bool) and rng[0] <= v <= rng[1]
            elif rng:
                ok = ok and isinstance(v, str) and v in rng
        if not ok:
            err.append("tuning ungültig (erlaubt: " + ", ".join(sorted(TUNING_RANGES)) + ")")
    extra = set(d) - {"id", "names", "style", "polite", "voice", "note", "glossary", "phrases", "hotwords",
                      "llm_hint", "tuning"}
    if extra:
        err.append("unbekannte Felder: " + ", ".join(sorted(extra)))
    return err


_LOAD_CACHE = {"sig": None, "val": None}


def _signature():
    """(Pfad, mtime, Größe) aller Preset-Dateien: ändert sich nichts, muss nicht neu gelesen werden
    (parse_spoken ruft load_all() bei jedem kurzen Sprachbefehl)."""
    sig = []
    for folder in (app_dir(), user_dir()):
        try:
            names = sorted(f for f in os.listdir(folder) if f.endswith(".json"))
        except OSError:
            sig.append((folder, None))
            continue
        for fn in names:
            path = os.path.join(folder, fn)
            try:
                st = os.stat(path)
                sig.append((path, st.st_mtime_ns, st.st_size))
            except OSError:
                sig.append((path, None, None))
    return tuple(sig)


def load_all():
    """{id: preset}. Nutzer-Verzeichnis überschreibt das App-Verzeichnis. Ergebnis wird zwischengespeichert,
    solange sich keine Datei ändert."""
    sig = _signature()
    if _LOAD_CACHE["sig"] == sig and _LOAD_CACHE["val"] is not None:
        return dict(_LOAD_CACHE["val"])
    out = _load_all_uncached()
    _LOAD_CACHE["sig"], _LOAD_CACHE["val"] = sig, dict(out)
    return out


def _load_all_uncached():
    out, seen = {}, {}
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
                if os.path.getsize(path) > MAX_FILE:
                    last_errors[path] = f"Datei größer als {MAX_FILE // 1024} KB"
                    continue
                with open(path, encoding="utf-8") as f:
                    d = json.load(f)
            except (OSError, ValueError) as e:
                last_errors[path] = "lesen: " + repr(e)[:100]
                continue
            err = validate(d)
            if err:
                last_errors[path] = "; ".join(err)
                continue
            if d["id"] in seen.get(folder, {}):          # gleiche id in zwei Dateien desselben Ordners
                last_errors[path] = f"id '{d['id']}' doppelt (schon in {seen[folder][d['id']]})"
                continue
            seen.setdefault(folder, {})[d["id"]] = fn
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


def _norm(text):
    """Vergleichsform für Namen und Sprachbefehle: NFC, klein, nur Buchstaben/Zeichen/Ziffern (Unicode L, M, N –
    Thai-Tonzeichen und Vokale bleiben), alles andere (Bindestrich, Schrägstrich, Klammern) wird zum Leerzeichen."""
    s = unicodedata.normalize("NFC", text or "").casefold()
    s = "".join(c if unicodedata.category(c)[0] in "LMN" else " " for c in s)
    return " ".join(s.split())


def find(spoken, presets=None):
    """Gesprochenen Namen (id oder Name in de/en/th, ohne Klammerzusatz) -> id oder None.
    Name und Eingabe laufen durch dieselbe Normalisierung („Reise-Notfälle“, „Police / theft“, Thai mit Tonzeichen)."""
    s = _norm(spoken)
    if not s:
        return None
    for pid, p in (presets if presets is not None else load_all()).items():
        names = {_norm(pid), *(_norm(re.sub(r"\s*\(.*?\)", "", v)) for v in p["names"].values())}
        if s in names:
            return pid
    return None


class PresetState:
    """Merkt den Zustand vor dem ersten Preset und stellt ihn bei „kein Preset“ wieder her."""

    def __init__(self):
        self.active = None
        self.saved = None
        self.hotwords, self.hint = [], None      # Nr. 243: aus dem aktiven Preset
        self.applied = {}                        # was das Preset gesetzt hat (Rückstellen nur, wenn unverändert)

    def activate(self, pid, presets, glossary, llm, eng, glossary_limit=200, voices=None):
        """Preset anwenden (pid=None/"none": zurück). Gibt das Preset oder None zurück.
        Unbekannte id -> KeyError, Zustand bleibt unverändert.
        voices: {Sprache: [gültige Stimmen]} – eine Preset-Stimme, die dort fehlt, wird ignoriert (Tippfehler im
        Nutzer-Preset ließe sonst jeden Satz in den Timeout laufen)."""
        p = None
        if pid not in (None, "", "none"):
            p = presets[pid]
        if self.saved is not None:                       # erst alten Zustand wiederherstellen
            ap = self.applied or {}
            # nur, was noch den Preset-Wert hat: eine Änderung des Nutzers währenddessen bleibt erhalten
            if "style" not in ap or llm["style"] == ap["style"]:
                llm["style"] = self.saved["style"]
            if "polite" not in ap or eng.polite == ap["polite"]:
                eng.polite = self.saved["polite"]
            for k, v in self.saved["voices"].items():
                if k not in ap.get("voices", {}) or eng.voices.get(k) == ap["voices"][k]:
                    eng.voices[k] = v                    # None = Standardstimme (Engine-Konvention)
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
        self.applied = {"style": p["style"], "voices": {}}
        if p.get("polite"):
            eng.polite = p["polite"]
            self.applied["polite"] = p["polite"]
        for k, v in p.get("voice", {}).items():
            if voices is not None and v not in voices.get(k, ()):
                continue                                 # unbekannte Stimme: Standard behalten
            eng.voices[k] = v
            self.applied["voices"][k] = v
        own = {a.lower() for a, _ in glossary}               # eigene Einträge haben Vorrang
        extra = [(a, b) for a, b in glossary_entries(p) if a.lower() not in own]
        glossary[:] = (list(glossary) + extra)[:glossary_limit]
        return p


OFF_WORDS = (["off"], ["none"], ["clear"], ["reset"], ["aus"], ["ohne"])
THAI_MODE = "โหมด"          # „โหมดโรงแรม“ (ohne Leerzeichen) oder „โหมด โรงแรม“


def parse_spoken(cmd, presets=None):
    """Sprachbefehl „hotel mode“ / „preset hotel“ / „preset off“ (auch „Notfall-Modus“, „Szenario Hotel“,
    „โหมดโรงแรม“) -> "preset:<id>" oder None. Nur kurze Äußerungen (höchstens 5 Wörter); sonst None."""
    n = _norm(cmd)
    if n.startswith(THAI_MODE) and len(n) > len(THAI_MODE):    # Thai trennt keine Wörter: Präfix abschneiden
        pid = find(n[len(THAI_MODE):].strip(), presets)
        return f"preset:{pid}" if pid else None
    words = n.split()
    if not 2 <= len(words) <= 5:
        return None
    if words[0] in ("preset", "szenario"):
        rest = words[1:]
        if rest in OFF_WORDS:
            return "preset:none"
    elif words[-1] in ("mode", "modus"):
        rest = words[:-1]
    else:
        return None
    pid = find(" ".join(rest), presets)
    return f"preset:{pid}" if pid else None
