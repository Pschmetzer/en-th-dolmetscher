"""Textnormalisierung (Runde 27: aus dolmetscher.py ausgelagert, dort re-exportiert).
Reine Funktionen ohne Zustand: Cache-Schlüssel eines Satzes (`_norm`) und Kürzen von Wiederholungsschleifen."""
import functools
import re

from thaiparticles import thai_stretch

_TH_RX = re.compile(r"[\u0e00-\u0e7f]")
_NORM_SEP = re.compile(r"(?:[\s。]|(?<!\d)[.,]|[.,](?!\d))+")
_NORM_QMARK = re.compile(r"\s*([?!])[\s?!]*")


_NORM_QUOTES = str.maketrans({"’": "'", "‘": "'", "ʼ": "'", "`": "'", "´": "'", "“": '"', "”": '"', "„": '"',
                              "‐": "-", "‑": "-", "–": "-", "—": "-"})


_TH_GAP = re.compile(r"(?<=[ก-๛])\s+(?=[ก-๛])")                 # Thai trennt Wörter nur nach Gusto mit Leerzeichen
_ZERO_WIDTH = re.compile("[\u200b\u200c\u200d\u2060\ufeff\u00ad]")      # LLM/Whisper streuen Zero-Width-Zeichen ein
_TH_DIGITS = str.maketrans("๐๑๒๓๔๕๖๗๘๙", "0123456789")


@functools.lru_cache(maxsize=2048)
def _norm(s):
    """Cache-Schlüssel: Groß/klein, Leerraum, . , 。 egal – ? und ! bleiben (Frage ≠ Aussage). Thai: Leerzeichen
    zwischen Thai-Zeichen und Dehnungen (ครับบบ) zählen nicht."""
    s = _ZERO_WIDTH.sub("", s).translate(_TH_DIGITS)               # Runde 28: ๓ = 3, Zero-Width zählt nicht
    s = s.lower().replace("？", "?").replace("！", "!")
    if _TH_RX.search(s):
        s = thai_stretch(_TH_GAP.sub("", s))
    s = s.translate(_NORM_QUOTES)                              # "It’s" = "It's" (Whisper wechselt zwischen beiden)
    s = _NORM_SEP.sub(" ", s)                                  # "1.5"/"1,5" bleiben (≠ "1 5")
    s = _NORM_QMARK.sub(r"\1", s)                              # "geht's ? !" -> "geht's?"
    return s.strip()


def squash_repeats(text):
    """Wiederholungsschleifen kürzen statt den ganzen Satz zu verlieren:
    'สติ๊กฮ่าาาาาาา' -> 'สติ๊กฮ่าาา', 'ha ha ha ha ha ha' -> 'ha ha ha'."""
    text = re.sub(r"(\D)\1{3,}", r"\1\1\1", text)
    # Ziffernfolgen (Telefon "0808080808", Zimmer "11111111") nie kürzen – nur Schleifen mit Buchstaben;
    # ohne Leerzeichen geschrieben (Thai/Chinesisch "ฮ่าฮ่าฮ่าฮ่า") bleibt die Schleife ohne Leerzeichen
    text = re.sub(r"(.{2,12}?)(?:\s*\1){3,}",
                  lambda m: (f"{m.group(1)}{' ' if re.search(chr(92) + 's', m.group(0)) else ''}" * 3).rstrip()
                  if re.search(r"[^\W\d_]", m.group(1)) else m.group(0), text, flags=re.I)   # "Ja ja ja ja" auch
    return text


# Runde 28: Füllwörter am Satzanfang (Whisper schreibt sie oft mit) und Vergleichsschlüssel für Namen
_TH_FILLER = re.compile(r"^\s*(?:(?:เอ่อ|เอ้อ|เออ|เอิ่ม|อืม|อึม|อ่า|อ้า|เอ่อม|หืม)(?:ๆ)*(?![ก-๙])[\s,.…\-]*)+")


def strip_thai_fillers(text):
    """Füllwörter (เอ่อ, อืม, อ่า …) am Anfang eines Thai-Satzes entfernen, bevor er übersetzt wird. Nur wenn kein
    Thai-Zeichen direkt folgt (เอ่อล้น, อ่านหนังสือ sind Wörter); besteht der Satz nur aus Füllwörtern -> ""."""
    if not text:
        return text
    return _TH_FILLER.sub("", text).strip() if _TH_FILLER.match(text) else text


_NAME_FOLD = (("ph", "p"), ("kh", "k"), ("th", "t"), ("ck", "k"), ("ee", "i"), ("oo", "u"), ("w", "v"), ("y", "i"),
              ("j", "c"), ("ch", "c"), ("q", "k"))


def name_key(name):
    """Vergleichsschlüssel für lateinisch geschriebene (Thai-)Namen: ohne Akzente, Leerzeichen, Bindestriche und
    Doppelbuchstaben; ph/kh/th wie p/k/t. "Chiang Mai" = "Chiangmai" = "Chiang-Mai", "Phuket" = "Puket",
    "Sukhumvit" = "Sukumvit". Für Abgleiche, nicht zum Anzeigen."""
    import unicodedata
    s = unicodedata.normalize("NFKD", (name or "").lower())
    s = re.sub(r"[^a-z0-9]", "", "".join(c for c in s if not unicodedata.combining(c)))
    for a, b in _NAME_FOLD:
        s = s.replace(a, b)
    return re.sub(r"(.)\1+", r"\1", s)
