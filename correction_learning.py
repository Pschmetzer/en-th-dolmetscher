"""Aus einer Nutzerkorrektur Vorschläge für Glossar/Profilvokabular ableiten.

Es wird nie etwas gespeichert: die Funktionen liefern nur Vorschläge (Liste von Wörtern)."""
import difflib
import re

_THAI = re.compile(r"[฀-๿]")
_NUM = re.compile(r"\d")
_UNITS = {"kg", "g", "mg", "km", "m", "cm", "mm", "l", "ml", "kb", "mb", "gb", "tb", "hz", "khz",
          "mhz", "ghz", "w", "kw", "v", "a", "s", "h", "min", "sec", "am", "pm", "usd", "eur",
          "thb", "baht", "บาท", "กก", "กม"}
# Wörter aller Schriften mit Leerzeichen (Latein mit Akzenten, Kyrillisch, Arabisch, Devanagari, Hangul …)
_WORD = re.compile(r"[^\W\d_][\w'’\-]*|\d[\d.,:]*\w*", re.U)
# Han/Kana ohne Leerzeichen: zeichenweise vergleichen, geänderte Strecken zusammenfassen
_CJK = re.compile(r"[぀-ヿ㐀-鿿]")
# Sprachen mit Großschreibung aller Substantive: Großbuchstabe mitten im Satz sagt dort nichts über Eigennamen
_CAPITAL_NOUNS = {"de", "lb"}
MAX_SUGGEST = 8


def _thai_tokens(text):
    """Thai ohne Leerzeichen: pythainlp, sonst Fallback auf zusammenhängende Thai-Läufe."""
    try:
        from pythainlp.tokenize import word_tokenize
        toks = word_tokenize(text, keep_whitespace=False)
    except Exception:
        toks = re.findall(r"[฀-๿]+|[A-Za-z0-9]+", text)
    return [t for t in toks if t.strip()]


def _is_cjk(text, lang):
    return lang in ("zh", "ja") or bool(_CJK.search(text or ""))


def tokenize(text, lang):
    if lang == "th" or _THAI.search(text or ""):
        return _thai_tokens(text or "")
    if _is_cjk(text, lang):
        return [c for c in (text or "") if c.strip() and not re.match(r"[\W_]", c)]
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
    if lang == "th" or _THAI.search(new or "") or lang in _CAPITAL_NOUNS or _is_cjk(new, lang):
        return []
    old_low = {t.lower() for t in tokenize(old, lang)}
    out, seen = [], set()
    cand = []
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
        cand.append((i, t))
    out.extend(t for _, t in cand)
    return out[:limit]


def suggest_vocab(old, new, lang="en", limit=MAX_SUGGEST):
    """Wörter aus `new`, die der Nutzer ersetzt/ergänzt hat. Leere Liste, wenn nichts Sinnvolles."""
    old_t, new_t = tokenize(old, lang), tokenize(new, lang)
    cjk = _is_cjk(new, lang) and lang != "th" and not _THAI.search(new or "")
    old_low = {t.lower() for t in old_t}
    out, seen = [], set()
    sm = difflib.SequenceMatcher(None, [t.lower() for t in old_t], [t.lower() for t in new_t],
                                 autojunk=False)
    for op, _, _, j1, j2 in sm.get_opcodes():
        if op not in ("replace", "insert"):
            continue
        if cjk:                                  # geänderte Zeichenstrecke als ein Wort (mind. 2 Zeichen)
            run = "".join(new_t[j1:j2])
            if len(run) >= 2 and run not in seen and not _NUM.search(run):
                seen.add(run)
                out.append(run)
            continue
        for j in range(j1, j2):
            tok = new_t[j]
            if tok.lower() in old_low or tok.lower() in seen or _skip(tok, j == 0):
                continue
            seen.add(tok.lower())
            out.append(tok)
    return out[:limit]
