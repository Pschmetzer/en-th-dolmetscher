"""Text um Sprachmodell-Antworten (Runde 28: aus dolmetscher.py ausgelagert, dort re-exportiert).
Reine Funktionen: umschliessende Anfuehrungszeichen, Namenserkennung, Entschaerfung fremden Texts fuer den Prompt,
`<speech>`-Tag entfernen."""
import re
from typing import Any

_QUOTE_PAIRS = {'"': '"', "“": "”", "„": "“", "«": "»", "‘": "’", "'": "'", "‚": "‘", "‹": "›",
                "「": "」", "『": "』", "＂": "＂", "»": "«"}
_QUOTE_ANY = '"“”„«»‚‹›「」『』＂'


def strip_quotes(text: str) -> str:
    """Umschliessende Anfuehrungszeichen entfernen – nur ein zusammengehoeriges Paar, innen keine weiteren
    (`"Yes," he said, "no."` bleibt unveraendert)."""
    t = text.strip()
    if len(t) >= 2 and _QUOTE_PAIRS.get(t[0]) == t[-1]:
        inner = t[1:-1]
        if not any(q in inner for q in _QUOTE_ANY):
            return inner.strip()
    return t


# Funktionswoerter: "Thank You", "Where Is The Toilet" (Titel-Schreibung) sind keine Namen
NAME_STOP = {"the", "is", "are", "was", "you", "your", "where", "what", "when", "how", "why", "who", "thank",
             "thanks", "please", "a", "an", "to", "of", "in", "on", "at", "do", "does", "can", "i", "me", "my",
             "we", "it", "this", "that", "and", "or", "not", "no", "yes", "sorry", "hello", "excuse", "good",
             "have", "has", "will", "would", "could", "for", "with", "from", "here", "there",
             # Gruss-/Hoeflichkeitswoerter anderer Quellsprachen: "Guten Morgen" ist kein Name
             "guten", "morgen", "abend", "nacht", "danke", "bitte", "hallo", "tschüss", "buenos", "buenas", "gracias",
             "hola", "bonjour", "bonsoir", "merci", "salut", "ciao", "grazie", "obrigado", "obrigada", "dank"}


def looks_like_name(text: str) -> bool:
    """Ein einzelnes Wort oder bis zu 4 gross geschriebene Woerter (Name, Marke, Ort)."""
    words = re.findall(r"[A-Za-zÀ-ÖØ-öø-ÿĀ-ſ][\w'’&-]*", text)         # auch "Café Müller", "Zürich"
    if len(words) > 1 and any(w.lower() in NAME_STOP for w in words):
        return False
    return len(words) == 1 or (0 < len(words) <= 4 and all(w[0].isupper() for w in words))


TAG_LIKE = re.compile(r"</?\s*[A-Za-z_][\w\-]*(?:\s[^<>]{0,80})?/?\s*>")
INVISIBLE = re.compile(r"[\x00-\x1f\x7f\u0085​-‏ -‮⁠-⁩﻿]")
SPEECH_TAG = re.compile(r"</?\s*speech\b[^<>]*>", re.I)


def strip_tags(s: str) -> str:
    """Tags entfernen, bis nichts mehr uebrig ist (verschachtelt: `</spe</speech>ch>` ergaebe sonst `</speech>`)."""
    for _ in range(6):
        n = TAG_LIKE.sub("", s)
        if n == s:
            return s
        s = n
    return s.replace("<", "").replace(">", "")


def neutralize(x: Any, limit: int = 400) -> str:
    """Fremden Text (Glossar, Hinweis, Verlauf, Alternative) fuer den Prompt entschaerfen -> kurzer einzeiliger str."""
    s = strip_tags(INVISIBLE.sub(" ", str(x)))
    return re.sub(r"\s+", " ", s).strip()[:limit]


def unspeech(text: Any) -> str:
    """`<speech>`-Tag aus dem Gesprochenen entfernen, auch verschachtelt/mit Attributen/Leerzeichen."""
    s = str(text)
    for _ in range(8):
        n = SPEECH_TAG.sub("", s)
        if n == s:
            return s
        s = n
    return s.replace("<", "").replace(">", "")
