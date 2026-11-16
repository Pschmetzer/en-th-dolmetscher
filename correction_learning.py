"""Aus einer Nutzerkorrektur Vorschläge für Glossar/Profilvokabular ableiten.

Es wird nie etwas gespeichert: die Funktionen liefern nur Vorschläge (Liste von Wörtern)."""
import difflib
import re

_THAI = re.compile(r"[฀-๿]")
_NUM = re.compile(r"\d")
_UNITS = {"kg", "g", "mg", "km", "m", "cm", "mm", "l", "ml", "kb", "mb", "gb", "tb", "hz", "khz",
          "mhz", "ghz", "w", "kw", "v", "a", "s", "h", "min", "sec", "am", "pm", "usd", "eur",
          "thb", "baht", "บาท", "กก", "กม"}
_WORD = re.compile(r"[A-Za-zÀ-ɏ][\w'’\-]*|\d[\d.,:]*\w*", re.U)
MAX_SUGGEST = 8


def _thai_tokens(text):
    """Thai ohne Leerzeichen: pythainlp, sonst Fallback auf zusammenhängende Thai-Läufe."""
    try:
        from pythainlp.tokenize import word_tokenize
        toks = word_tokenize(text, keep_whitespace=False)
    except Exception:
        toks = re.findall(r"[฀-๿]+|[A-Za-z0-9]+", text)
    return [t for t in toks if t.strip()]


def tokenize(text, lang):
    if lang == "th" or _THAI.search(text or ""):
        return _thai_tokens(text or "")
    return _WORD.findall(text or "")


def _skip(tok, sentence_start):
    low = tok.lower()
    if _NUM.search(tok) or low in _UNITS:
        return True
    if _THAI.search(tok):
        return len(tok) < 2                      # einzelne Zeichen sind kein Wort
    if len(tok) < 3:
        return True
    # Nr. 209: Eigennamen (Großbuchstabe mitten im Satz) bleiben drin – sie sind als Vokabel am wertvollsten
    return False


# Kein Eigenname, obwohl großgeschrieben (Wochentage, Monate, Anreden, Pronomen)
_NOT_NAMES = {"i", "i'm", "i'll", "i've", "i'd", "monday", "tuesday", "wednesday", "thursday", "friday",
              "saturday", "sunday", "january", "february", "march", "april", "may", "june", "july", "august",
              "september", "october", "november", "december", "mr", "mrs", "ms", "dr", "ok", "okay",
              "english", "thai", "god"}


def proper_names(old, new, lang="en", limit=3):
    """Eigennamen, die erst durch die Korrektur dazukamen (Großbuchstabe mitten im Satz, lateinische
    Schrift, im Original in keiner Schreibweise vorhanden). Kandidaten fürs Glossar („Name“ = unverändert
    lassen). Thai hat keine Großschreibung: dort nie etwas. Wörter am Satzanfang sind nicht unterscheidbar."""
    if lang == "th" or _THAI.search(new or ""):
        return []
    old_low = {t.lower() for t in tokenize(old, lang)}
    out, seen = [], set()
    starts = {0}
    toks = _WORD.findall(new or "")
    # Satzanfänge: erstes Wort und Wörter nach . ! ?
    pos = 0
    for i, t in enumerate(toks):
        j = (new or "").find(t, pos)
        if i and re.search(r"[.!?]\s*$", (new or "")[pos:j]):
            starts.add(i)
        pos = j + len(t)
    for i, t in enumerate(toks):
        low = t.lower()
        if (i in starts or not t[0].isupper() or t.isupper() or len(t) < 2 or _NUM.search(t)
                or low in _NOT_NAMES or low in old_low or low in seen):
            continue
        seen.add(low)
        out.append(t)
    return out[:limit]


def suggest_vocab(old, new, lang="en", limit=MAX_SUGGEST):
    """Wörter aus `new`, die der Nutzer ersetzt/ergänzt hat. Leere Liste, wenn nichts Sinnvolles."""
    old_t, new_t = tokenize(old, lang), tokenize(new, lang)
    old_low = {t.lower() for t in old_t}
    out, seen = [], set()
    sm = difflib.SequenceMatcher(None, [t.lower() for t in old_t], [t.lower() for t in new_t],
                                 autojunk=False)
    for op, _, _, j1, j2 in sm.get_opcodes():
        if op not in ("replace", "insert"):
            continue
        for j in range(j1, j2):
            tok = new_t[j]
            if tok.lower() in old_low or tok.lower() in seen or _skip(tok, j == 0):
                continue
            seen.add(tok.lower())
            out.append(tok)
    return out[:limit]
