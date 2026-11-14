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
    # Eigenname: Großbuchstabe mitten im Satz (am Satzanfang nicht unterscheidbar)
    if not sentence_start and tok[0].isupper() and not tok.isupper():
        return True
    return False


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
