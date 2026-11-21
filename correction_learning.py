"""Aus einer Nutzerkorrektur Vorschläge für Glossar/Profilvokabular ableiten.

Es wird nie etwas gespeichert: die Funktionen liefern nur Vorschläge (Liste von Wörtern)."""
import difflib
import re

from textnorm import name_key

_THAI = re.compile(r"[฀-๿]")
_NUM = re.compile(r"\d")
_UNITS = {"kg", "mg", "km", "cm", "mm", "ml", "kb", "mb", "gb", "tb", "hz", "khz", "mhz", "ghz", "kw",
          "min", "sec", "usd", "eur", "thb", "baht", "บาท", "กก", "กม"}      # Kürzere stehen schon unter len < 3
# Funktionswörter und Höflichkeits-/Satzpartikel sind als persönliches Vokabular wertlos
_STOP = {"the", "and", "you", "for", "are", "was", "but", "not", "with", "that", "this", "have", "from", "they",
         "will", "would", "could", "should", "your", "what", "when", "where", "who", "how", "can", "yes", "please",
         "thank", "thanks", "just", "very", "also", "then", "than", "there", "here", "some", "any", "all",
         "ครับ", "ค่ะ", "คะ", "นะ", "นะคะ", "นะครับ", "ไม่", "ใช่", "และ", "หรือ", "ที่", "ของ", "ได้", "จะ", "แล้ว",
         "มี", "เป็น", "ก็", "ด้วย", "จ้า", "จ้ะ", "สิ", "ละ", "เลย", "อ่ะ", "เหรอ", "ไหม", "มั้ย",
         "ครับผม", "คร้าบ", "เนอะ", "น่ะ", "หรอก", "แหละ", "เถอะ", "จ๊ะ", "นะจ๊ะ", "นะจ๊ะ", "ซิ", "อ่า", "เอ่อ", "อืม"}
# Runde 22: Funktionswörter je Sprache (die englische Liste allein ließ „und/nicht/pour“ als Vokabel durch)
_STOP_LANG = {
    "de": {"und", "oder", "aber", "nicht", "ich", "du", "sie", "wir", "ihr", "der", "die", "das", "den", "dem",
           "ein", "eine", "einen", "mit", "für", "von", "ist", "sind", "war", "bitte", "danke", "ja", "nein",
           "auch", "noch", "schon", "sehr", "wie", "was", "wer", "wo", "wann", "dass", "zum", "zur", "auf"},
    "es": {"que", "los", "las", "una", "uno", "por", "para", "con", "pero", "como", "muy", "más", "sí", "gracias",
           "favor", "del", "est", "está", "son", "fue", "yo", "tú", "usted", "nosotros", "esto", "esta"},
    "fr": {"les", "des", "une", "pour", "avec", "mais", "pas", "oui", "non", "merci", "plaît", "est", "sont",
           "vous", "nous", "elle", "ils", "elles", "que", "qui", "dans", "sur", "très", "aussi", "cette"},
    "it": {"che", "per", "con", "non", "una", "sono", "grazie", "prego", "anche", "molto", "come", "gli", "del"},
    "pt": {"que", "uma", "para", "com", "não", "sim", "obrigado", "obrigada", "favor", "muito", "como", "são"},
    "nl": {"het", "een", "van", "niet", "met", "voor", "dank", "alsjeblieft", "ook", "zijn", "maar", "ja", "nee"},
    "id": {"yang", "dan", "dengan", "tidak", "ini", "itu", "terima", "kasih", "tolong", "ya", "juga", "saya"},
    "vi": {"và", "của", "không", "có", "là", "xin", "cảm", "ơn", "vâng", "tôi", "bạn"},
    "th": {"ขอบคุณ", "สวัสดี", "ขอโทษ", "ผม", "ฉัน", "คุณ", "เรา", "เขา", "นี้", "นั้น", "ที่", "จะ", "ได้", "แล้ว",
           "ยัง", "ก็", "ของ", "ใน", "กับ", "ให้", "ไป", "มา", "อยู่", "ไหม", "มั้ย", "อะไร"},
}
# Wörter aller Schriften mit Leerzeichen (Latein mit Akzenten, Kyrillisch, Arabisch, Devanagari, Hangul …)
_WORD = re.compile(r"[^\W\d_][\w'’\-]*|\d[\d.,:]*\w*", re.U)
# Han/Kana ohne Leerzeichen: zeichenweise vergleichen, geänderte Strecken zusammenfassen
_CJK = re.compile(r"[぀-ヿ㐀-鿿]")
# Sprachen mit Großschreibung aller Substantive: Großbuchstabe mitten im Satz sagt dort nichts über Eigennamen
_CAPITAL_NOUNS = {"de", "lb"}
MAX_SUGGEST = 8
MAX_FALLBACK_RUN = 15      # längster Thai-Lauf, der ohne Tokenizer noch als „Wort“ gilt


def _thai_tokens(text):
    """Thai ohne Leerzeichen: pythainlp, sonst Fallback auf zusammenhängende Thai-Läufe."""
    try:
        from pythainlp.tokenize import word_tokenize
        toks = word_tokenize(text, keep_whitespace=False)
    except Exception:
        # Ohne Wörterbuch ist ein langer Thai-Lauf ein ganzer Satzteil, kein Wort: nicht als Vokabel vorschlagen
        toks = [t for t in re.findall(r"[฀-๿]+|[A-Za-z0-9]+", text) if len(t) <= MAX_FALLBACK_RUN]
    return [t for t in toks if t.strip()]


def _is_cjk(text, lang):
    return lang in ("zh", "ja") or bool(_CJK.search(text or ""))


def tokenize(text, lang):
    if lang == "th" or _THAI.search(text or ""):
        return _thai_tokens(text or "")
    if _is_cjk(text, lang):
        return [c for c in (text or "") if c.strip() and not re.match(r"[\W_]", c)]
    return _WORD.findall(text or "")


def _skip_lang(tok, lang):
    """Funktionswort der jeweiligen Sprache (siehe _STOP_LANG)?"""
    return tok.lower() in _STOP_LANG.get(lang or "", ())


def _skip(tok):
    low = tok.lower()
    if _NUM.search(tok) or low in _UNITS or low in _STOP:
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
    idx = []
    for i, t in cand:                            # "Chiang Mai": nebeneinander stehende Namen = ein Eintrag
        if out and idx[-1] == i - 1:
            out[-1] = f"{out[-1]} {t}"
        else:
            out.append(t)
        idx.append(i)
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
            if tok.lower() in old_low or tok.lower() in seen or _skip_lang(tok, lang) or _skip(tok):
                continue
            seen.add(tok.lower())
            out.append(tok)
    return out[:limit]


# ---------------------------------------------------------------- Verwechslungen und Namen (Runde 23)
MAX_SPAN = 3               # längste Wortstrecke, die als ein Verwechslungspaar gilt
MAX_CONFUSIONS = 500       # Obergrenze der ConfusionMap (seltenste fallen weg)


def confusion_pairs(old, new, lang="en"):
    """Was wurde wofür gehört? [(falsch, richtig)] aus den ersetzten Wortstrecken (gleich lange Strecken Wort für Wort,
    sonst bis MAX_SPAN Wörter als ein Paar). `falsch` klein geschrieben, `richtig` wie getippt; Zahlen und Paare,
    die sich nur durch Groß-/Kleinschreibung unterscheiden, fehlen."""
    old_t, new_t = tokenize(old, lang), tokenize(new, lang)
    glue = "" if (_is_cjk(new, lang) and lang != "th" and not _THAI.search(new or "")) else " "
    sm = difflib.SequenceMatcher(None, [t.lower() for t in old_t], [t.lower() for t in new_t], autojunk=False)
    out = []
    for op, i1, i2, j1, j2 in sm.get_opcodes():
        if op != "replace":
            continue
        if i2 - i1 == j2 - j1:
            pairs = [(old_t[i1 + k], new_t[j1 + k]) for k in range(i2 - i1)]
        elif i2 - i1 <= MAX_SPAN and j2 - j1 <= MAX_SPAN:
            pairs = [(glue.join(old_t[i1:i2]), glue.join(new_t[j1:j2]))]
        else:
            continue
        for w, r in pairs:
            if w.lower() != r.lower() and not _NUM.search(w + r) and w.strip() and r.strip():
                out.append((w.lower(), r))
    return out


class ConfusionMap:
    """Zählt Verwechslungen falsch -> richtig über mehrere Korrekturen. Nur im Speicher; to_dict()/from_dict() geben
    den Stand an den Aufrufer (diese Datei speichert nie etwas)."""

    def __init__(self):
        self.counts = {}

    def add(self, old, new, lang="en"):
        """Korrektur einbuchen -> Anzahl eingebuchter Paare."""
        pairs = confusion_pairs(old, new, lang)
        for p in pairs:
            self.counts[p] = self.counts.get(p, 0) + 1
        if len(self.counts) > MAX_CONFUSIONS:
            keep = sorted(self.counts.items(), key=lambda kv: (-kv[1], kv[0]))[:MAX_CONFUSIONS]
            self.counts = dict(keep)
        return len(pairs)

    def top(self, min_count=2, limit=MAX_SUGGEST):
        """[(falsch, richtig, anzahl)] – häufigste zuerst, nur ab `min_count` Wiederholungen."""
        rows = [(w, r, n) for (w, r), n in self.counts.items() if n >= min_count]
        rows.sort(key=lambda x: (-x[2], x[0], x[1]))
        return rows[:max(0, int(limit))]

    def best(self, wrong, min_count=2):
        """Häufigste Korrektur für ein falsch gehörtes Wort oder None."""
        c = [(n, r) for (w, r), n in self.counts.items() if w == (wrong or "").lower() and n >= min_count]
        return max(c)[1] if c else None

    def apply(self, text, min_count=2):
        """Bekannte Verwechslungen in `text` ersetzen (ganze Wörter, ohne Groß-/Kleinschreibung; Thai: Teilstring)."""
        out = text or ""
        rows = sorted(self.top(min_count, MAX_CONFUSIONS), key=lambda x: -len(x[0]))
        latin = {}
        for w, r, _n in rows:
            if not _THAI.search(w):
                latin.setdefault(w, r)                     # mehrere Korrekturen für ein Wort: die häufigste gewinnt
        if latin:
            # Runde 24: ein Durchlauf, sonst ersetzt das nächste Paar das Ergebnis des vorigen erneut (a->b, b->c)
            rx = re.compile(r"(?<!\w)(?:" + "|".join(re.escape(w) for w in latin) + r")(?!\w)", re.I)
            out = rx.sub(lambda m: latin[m.group(0).lower()], out)
        for w, r, _n in rows:
            if _THAI.search(w):
                out = out.replace(w, r)
        return out

    def to_dict(self):
        return {"pairs": [[w, r, n] for (w, r), n in sorted(self.counts.items())]}

    @classmethod
    def from_dict(cls, d):
        m = cls()
        for row in (d or {}).get("pairs", []):
            if (isinstance(row, (list, tuple)) and len(row) == 3 and isinstance(row[0], str)
                    and isinstance(row[1], str) and isinstance(row[2], int)
                    and not isinstance(row[2], bool) and row[2] > 0 and len(m.counts) < MAX_CONFUSIONS):
                m.counts[(row[0], row[1])] = row[2]
        return m


def name_alignment(old, new, lang="en", min_ratio=0.5):
    """Welcher gehörte Text wurde zu welchem Namen? [(gehört, name)] für die Eigennamen aus proper_names(): die
    ähnlichste gleich lange Wortfolge im Original, die in der Korrektur fehlt ("Chang my" -> "Chiang Mai")."""
    names = proper_names(old, new, lang)
    if not names:
        return []
    old_t = tokenize(old, lang)
    new_low = {t.lower() for t in tokenize(new, lang)}
    out, used = [], set()
    for name in names:
        n = len(name.split())
        best, score = None, min_ratio
        target = name_key(name)
        for w in (n, n + 1, n - 1):                  # ASR trennt Namen oft anders ("sam chi" für "Somchai")
            for i in range(0, len(old_t) - w + 1) if w >= 1 else ():
                span = old_t[i:i + w]
                if any(j in used for j in range(i, i + w)) or all(t.lower() in new_low for t in span):
                    continue
                r = difflib.SequenceMatcher(None, name_key("".join(span)), target).ratio()
                if r > score:
                    best, score = (i, w), r
        if best is not None:
            used.update(range(best[0], best[0] + best[1]))
            out.append((" ".join(old_t[best[0]:best[0] + best[1]]), name))
    return out


# Runde 28: Thai-Namen nach Anrede (Thai kennt keine Großschreibung)
_HONORIFIC = re.compile(r"(?:คุณ|นางสาว|นาง|นาย|ดร\.|อาจารย์|ครู|หมอ|พี่|น้อง)\s*([฀-๿]{2,12})")
_NAME_TAIL = ("ครับผม", "ครับ", "ค่ะ", "คะ", "นะ", "จ้ะ", "จ้า")      # Schlusspartikeln, ohne Regex (kein Backtracking)
_NOT_THAI_NAME = ("ไม่", "ได้", "จะ", "มา", "ไป", "ช่วย", "ขอ", "อยู่", "เป็น", "มี", "ที่", "และ", "ก็", "เรา", "ผม",
                  "ฉัน", "ต้อง", "กำลัง", "แล้ว", "ยัง", "คือ", "ใน", "กับ", "ให้")


def thai_honorific_names(old, new, limit=3):
    """Thai-Namen, die erst die Korrektur enthält: das Wort nach einer Anrede (คุณ, นาย, นาง, ดร., พี่ …) ohne
    Schlusspartikel. "คุณสมชายครับ" -> ["สมชาย"]. Steht der Name schon im Original (oder als Teil davon), kommt er
    nicht mehr vor; Funktionswörter nach der Anrede (คุณไม่ …) zählen nicht. Reine Vorschläge."""
    out = []
    for m in _HONORIFIC.finditer(new or ""):
        name = m.group(1)
        while name.endswith(_NAME_TAIL):
            name = name[:-len(next(t for t in _NAME_TAIL if name.endswith(t)))]
        if len(name) < 2 or name.startswith(_NOT_THAI_NAME) or name in (old or "") or name in out:
            continue
        out.append(name)
    return out[:limit]
