"""Zahlen als Thai-Wörter (Runde 25: aus dolmetscher.py ausgelagert, dort re-exportiert).
Reine Funktionen ohne Zustand: Zahl -> Thai-Wörter (350 -> สามร้อยห้าสิบ) und Zahlen im Thai-Text vorlesbar machen."""
import re

_TH_DIG = ("ศูนย์", "หนึ่ง", "สอง", "สาม", "สี่", "ห้า", "หก", "เจ็ด", "แปด", "เก้า")
_TH_POS = ("", "สิบ", "ร้อย", "พัน", "หมื่น", "แสน")


def _th_chunk(n, higher):
    """0 < n < 1 000 000 als Thai-Wörter; higher: davor steht schon ein Millionen-Teil (dann „เอ็ด“ statt „หนึ่ง“)."""
    ds = str(n)
    out, L = [], len(ds)
    for i, ch in enumerate(ds):
        dgt, pos = int(ch), L - 1 - i
        if dgt == 0:
            continue
        if pos == 0:
            out.append("เอ็ด" if dgt == 1 and (L > 1 or higher) else _TH_DIG[dgt])
        elif pos == 1:
            out.append("สิบ" if dgt == 1 else "ยี่สิบ" if dgt == 2 else _TH_DIG[dgt] + "สิบ")
        else:
            out.append(_TH_DIG[dgt] + _TH_POS[pos])
    return "".join(out)


def thai_number_words(n):
    """Ganze Zahl 0 … 999 999 999 999 als Thai-Wörter (350 -> สามร้อยห้าสิบ, 21 -> ยี่สิบเอ็ด); sonst None."""
    if not isinstance(n, int) or isinstance(n, bool) or n < 0 or n >= 10 ** 12:
        return None
    if n == 0:
        return _TH_DIG[0]
    parts, higher = [], False
    millions = []
    while n:
        millions.append(n % 1_000_000)
        n //= 1_000_000
    for idx in range(len(millions) - 1, -1, -1):
        c = millions[idx]
        if c:
            parts.append(_th_chunk(c, higher))
            higher = True
        if idx:
            parts.append("ล้าน")
    return "".join(parts)


_TH_DIGIT_MAP = str.maketrans("๐๑๒๓๔๕๖๗๘๙", "0123456789")


def thai_digits_to_ascii(text):
    """Thai-Ziffern ๐-๙ in 0-9 umschreiben (Zahlen, Datum, Cache-Schlüssel); alles andere bleibt."""
    return text.translate(_TH_DIGIT_MAP) if text else text


_NUM_KEEP_BEFORE = re.compile(r"(?:ห้อง|เบอร์|โทร|โทรศัพท์|รหัส|หมายเลข|เลขที่|ไปรษณีย์|แท็กซี่|ชั้น|บัตร|บัญชี)\s*$")
# Runde 25: Uhrzeit „10.30 น.“ / „9.05 โมง“ (Punkt als Trenner) bleibt Ziffernfolge; „10 000“ (Leerzeichen
# als Tausendertrenner) wird nicht in „สิบ 000“ zerlegt
_TIME_AFTER = re.compile(r"\s*(?:น(?:\.|(?![ก-๙]))|นาฬิกา|โมง|นาที)")
_SPACE_GROUP = re.compile(r"[ \u00a0\u202f]\d{3}(?!\d)")
_SPEAK_NUM = re.compile(r"(?<![\w.,:/\-+#])(\d{1,3}(?:,\d{3})+|\d{1,9})(?:\.(\d{1,6}))?(%)?(?![\w:/\-]|[.,]\d)")


def speak_numbers_th(text):
    """Zahlen in Thai-Text als Wörter lesbar machen (die TTS liest Ziffern uneinheitlich): 350 -> สามร้อยห้าสิบ,
    3.5 -> สามจุดห้า. Nummern (Zimmer, Telefon, Konto), führende Nullen, Uhrzeiten und Datum bleiben Ziffern."""
    text = thai_digits_to_ascii(text)                          # Runde 28: ๓๐๐ wie 300 vorlesen

    def one(m):
        raw, frac, pct = m.group(1), m.group(2), m.group(3)
        digits = raw.replace(",", "")
        if len(digits) > 1 and (digits[0] == "0" or _NUM_KEEP_BEFORE.search(text[:m.start()])):
            return m.group(0)
        if frac and len(frac) == 2 and "," not in raw and int(raw) <= 24 and int(frac) < 60 \
                and _TIME_AFTER.match(text, m.end()):
            return m.group(0)                                   # Uhrzeit mit Punkt, keine Dezimalzahl
        if (_SPACE_GROUP.match(text, m.end()) or (len(digits) == 3 and not frac
                                                  and re.search(r"\d[ \u00a0\u202f]$", text[:m.start()]))):
            return m.group(0)                                   # „10 000“: Gruppen mit Leerzeichen nicht zerreißen
        words = thai_number_words(int(digits))
        if words is None:
            return m.group(0)
        if frac:
            words += "จุด" + "".join(_TH_DIG[int(c)] for c in frac)
        return words + (" เปอร์เซ็นต์" if pct else "")
    return _SPEAK_NUM.sub(one, text)


# Runde 28: Gegenrichtung (STT schreibt Zahlen oft als Wörter) und Ziffernfolgen einzeln lesen
_W_DIGIT = {w: i for i, w in enumerate(_TH_DIG)}
_W_POS = {"สิบ": 10, "ร้อย": 100, "พัน": 1000, "หมื่น": 10000, "แสน": 100000}
_NUM_TOK = re.compile(r"ศูนย์|หนึ่ง|สอง|สาม|สี่|ห้า|หก|เจ็ด|แปด|เก้า|ยี่|เอ็ด|สิบ|ร้อย|พัน|หมื่น|แสน|ล้าน")


def _words_chunk(toks, higher=False):
    """Tokens unterhalb einer Million -> Zahl (oder None bei ungültiger Folge)."""
    total, digit, last_pos = 0, None, 10 ** 6
    for i, t in enumerate(toks):
        if t in ("ศูนย์", "ล้าน"):
            return None
        if t in _W_POS:
            pos = _W_POS[t]
            if pos >= last_pos:
                return None
            total += (digit if digit is not None else 1) * pos
            digit, last_pos = None, pos
        elif t == "ยี่":
            if i + 1 >= len(toks) or toks[i + 1] != "สิบ" or digit is not None:
                return None
            digit = 2
        else:                                              # Ziffernwort oder เอ็ด
            if digit is not None:
                return None
            if t == "เอ็ด" and i == 0 and not (higher and len(toks) == 1):
                return None
            digit = 1 if t == "เอ็ด" else _W_DIGIT[t]
            if t == "เอ็ด" and i != len(toks) - 1:
                return None
    if digit is not None:
        if last_pos == 1:
            return None
        total += digit
    return total


def thai_words_to_number(s):
    """Thai-Zahlwörter als ganze Zahl (สามร้อยห้าสิบ -> 350, ยี่สิบเอ็ด -> 21, สองล้านห้าแสน -> 2500000); die
    Umkehrung von thai_number_words. Ungültiges, Gemischtes und leere Eingaben -> None."""
    s = re.sub(r"\s+", "", s or "")
    if not s:
        return None
    toks = _NUM_TOK.findall(s)
    if "".join(toks) != s:
        return None
    if toks == ["ศูนย์"]:
        return 0
    groups, cur = [], []
    for t in toks:
        if t == "ล้าน":
            groups.append(cur)
            cur = []
        else:
            cur.append(t)
    groups.append(cur)
    total = 0
    for i, g in enumerate(groups):
        if not g:
            if i == len(groups) - 1 and len(groups) > 1 and groups[i - 1]:
                continue                                   # „… ล้าน“ am Ende: die Zahl davor ist der Wert
            return None
        v = _words_chunk(g, higher=i > 0)
        if v is None:
            return None
        total = total * 1_000_000 + v
    if not groups[-1] and len(groups) > 1:
        total *= 1_000_000
    return total


def speak_digits_th(s):
    """Ziffernfolge einzeln lesen (Telefon, Zimmer, Konto): „081-234“ -> „ศูนย์แปดหนึ่ง สองสามสี่“. Gruppen an
    -, Leerzeichen, Punkt; Nicht-Ziffern innerhalb einer Gruppe werden übersprungen."""
    groups = re.split(r"[\s\-./]+", thai_digits_to_ascii(s or ""))
    out = ["".join(_TH_DIG[int(c)] for c in g if c.isdigit() and c.isascii()) for g in groups]
    return " ".join(x for x in out if x)
