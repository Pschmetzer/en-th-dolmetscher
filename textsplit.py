"""Textteilung fuer Sprachausgabe und Streaming (Runde 25: aus dolmetscher.py ausgelagert, dort re-exportiert).
Reine Funktionen ohne Zustand: erste Teilphrase eines wachsenden Textes, Sprechbarkeit, Teilung langer Texte,
Thai-Schnittgrenzen."""
import re


def _thai_cut_ok(prev, nxt):
    """Darf zwischen zwei Zeichen geschnitten werden? Nicht vor Folgevokalen/Tonzeichen (hängen am Vorgänger) und
    nicht nach Vorderen Vokalen เ แ โ ใ ไ (U+0E40-0E44, gehören zum folgenden Konsonanten)."""
    if "\u0e40" <= prev <= "\u0e44":
        return False
    return not ("\u0e30" <= nxt <= "\u0e4e" and not "\u0e40" <= nxt <= "\u0e44")


FIRST_CLAUSE_MIN = {"th": 8, "zh": 4, "ja": 4}
_CLAUSE_END = re.compile(r"[,;:.!?，；：。！？、…]")


def first_clause(buf, lang=None):
    """Erste vollständige Teilphrase eines wachsenden Textes (für Streaming), sonst None. Die Phrase endet an
    Komma/Satzzeichen und gilt erst, wenn dahinter schon etwas steht (Zeichen nicht mehr unterwegs)."""
    for m in _CLAUSE_END.finditer(buf or ""):
        end = m.end()
        if end < len(buf) and len(buf[:end].strip()) >= FIRST_CLAUSE_MIN.get(lang, 12):
            if (m.group(0) in ".,:" and re.search(r"\d$", buf[:m.start()]) and buf[end:end + 1].isdigit()):
                continue                                    # Dezimalpunkt/-komma 3.5, 3,5, 1,500 und Uhrzeit 10:30
            return buf[:end].strip()
    return None


MAX_SPEAK_CHARS = 300             # längere Teile einer Ausgabe werden geteilt (edge-tts/say: Frist, Abbruchrisiko)


def speakable(text):
    """Gibt es etwas zu sprechen? Nur Satzzeichen/Leerraum würden edge-tts „NoAudioReceived“ werfen lassen
    und `say` ein Klicken sprechen lassen."""
    return any(c.isalnum() for c in text)


def chunk_long(parts, lang, limit=None):
    """Teile über `limit` Zeichen (Satz ohne Satzzeichen, Thai ohne Leerzeichen) an Wort-/Kommagrenzen teilen,
    sonst hart; nichts geht verloren."""
    limit = max(3, int(limit or MAX_SPEAK_CHARS))      # Runde 25: limit 1–2 schnitt an Position 0 -> Endlosschleife
    out = []
    for p in parts:
        while len(p) > limit:
            cut = max(p.rfind(" ", 0, limit), p.rfind(",", 0, limit) + 1, p.rfind("，", 0, limit) + 1,
                      p.rfind("、", 0, limit) + 1)
            if cut < limit // 3:
                cut = limit
                while cut > limit // 3 and not _thai_cut_ok(p[cut - 1], p[cut]):
                    cut -= 1                      # Thai ohne Leerzeichen: nie mitten im Zeichencluster schneiden
            out.append(p[:cut].strip())
            p = p[cut:].strip() if cut != limit or p[cut:cut + 1].isspace() else p[cut:]
        out.append(p)
    return [x for x in out if x]


# Runde 8: Kürzel, nach deren Punkt kein Satz endet ("9 a.m. to 5 p.m.", "ca. 500", "z. B.", "Prof. Brown")
_ABBREV_TH = ("น.", "พ.ศ.", "ค.ศ.", "ดร.", "ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.", "ก.ค.", "ส.ค.", "ก.ย.",
              "ต.ค.", "พ.ย.", "ธ.ค.")                       # Runde 28: Thai-Kürzel (Uhrzeit, Jahr, Monate)
_ABBREV = frozenset(_ABBREV_TH + (
    "ca.", "z.", "b.", "bzw.", "usw.", "approx.", "prof.", "jr.", "sr.", "inc.", "co.", "ltd.", "mt.", "vs.", "u.a.",
    "d.h.", "evtl.", "str.", "dr.", "mr.", "mrs.", "ms.", "st.", "e.g.", "i.e."))
_ABBREV_NUM = frozenset({"no.", "nr.", "tel."})     # enden auch Sätze ("No. I don't."): nur vor einer Ziffer verbinden


def _rejoin_abbrev(parts):
    """Teile wieder verbinden, wenn der Satz nur an einem Kürzel oder vor einem Kleinbuchstaben „endete“."""
    out = []
    for p in parts:
        if out:
            last = out[-1].split()[-1].casefold() if out[-1].split() else ""
            if (last in _ABBREV or (last in _ABBREV_NUM and p[:1].isdigit())
                    or (out[-1].endswith(".") and p[:1].islower() and p[:1].isalpha())):
                out[-1] += " " + p
                continue
        out.append(p)
    return out


# Runde 28: Thai-Sätze ohne Satzzeichen (Whisper trennt sie nur mit Leerzeichen)
_TH_SENT_END = ("ครับผม", "ครับ", "ค่ะ", "คะ", "คร้าบ", "นะ", "จ้ะ", "จ้า", "จ๊ะ", "ไหม", "มั้ย", "เหรอ")


def split_thai_sentences(text):
    """Thai-Text in Sätze teilen: an ? ! … 。 und an Leerzeichen hinter einer Schlusspartikel (ครับ, ค่ะ, นะ, ไหม …);
    die Partikel bleibt beim Satz. Ohne Leerzeichen/Satzzeichen oder bei Zahlen (10 000) bleibt alles ein Satz."""
    out = []
    for part in re.split(r"(?<=[?!？！。…])\s*", text or ""):
        cur = []
        for tok in part.split():
            if cur and cur[-1].endswith(_TH_SENT_END) and not cur[-1].endswith("คะแนน"):
                out.append(" ".join(cur))
                cur = []
            cur.append(tok)
        if cur:
            out.append(" ".join(cur))
    return [x for x in out if x.strip()]
