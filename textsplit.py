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
