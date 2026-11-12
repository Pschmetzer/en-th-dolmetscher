#!/usr/bin/env python3
"""Hands-free EN <-> TH Dolmetscher.

Hört dauerhaft aufs Mikrofon, erkennt selbst ob Englisch oder Thai gesprochen
wird, übersetzt und spricht die Übersetzung sofort laut aus.

Start:  python3 dolmetscher.py   (benötigt: pip install faster-whisper, ffmpeg)
Optionen: --model small|medium|base  --mic 0  --polite krub|ka  --json
          --lang auto|en|th  --tts edge|say  --file test.wav  --mute
          --barge-in (nur mit Kopfhörer)  --log-text/--no-log-text
          --rate N --volume F --silence S --sensitivity low|normal|high --denoise
          --voice-en/--voice-th NAME --llm [--llm-model ID] --earcons --meter --list-mics
Protokoll Engine <-> App: docs/PROTOKOLL.md
"""
import argparse, collections, functools, http.client, itertools, json, logging, logging.handlers, os, queue, re, \
    shutil, signal, subprocess, sys, tempfile, threading, time, urllib.error, urllib.parse, urllib.request
import numpy as np
from faster_whisper import WhisperModel

SR = 16000
SILENCE_END = 0.7                 # s Stille = Satzende (--silence, live änderbar)
MIN_UTT = 0.3                     # s, kürzer wird ignoriert (Log: leise Wörter mit 0,32 s gingen verloren)
MAX_UTT = 10.0                    # s, länger wird an der leisesten Stelle geteilt – der erste Teil wird
                                  # schon übersetzt, während noch gesprochen wird
MIN_LANG_P = 0.35                 # en+th zusammen mindestens so wahrscheinlich, sonst ignorieren
# unsicherere Transkripte gelten als Rauschen/Halluzination; Thai bekommt systematisch
# schlechtere log-probs (Log: echte Thai-Sätze bis −0.99), deshalb eine eigene Schwelle
MIN_LOGPROB = {"en": -1.0, "th": -1.3}
SENSITIVITY = {"low": (0.55, 0.35), "normal": (0.4, 0.25), "high": (0.3, 0.18)}   # VAD START, KEEP
VAD = {"start": 0.4, "keep": 0.25}
# Leises/entferntes Thai erkennt Whisper oft als eine andere asiatische Sprache (Log: ja 0,66 / zh 0,72,
# th 0,01). Diese Wahrscheinlichkeiten zählen deshalb zu Thai; europäische Sprachen bleiben gefiltert.
ASIAN_AS_TH = ("zh", "yue", "ja", "ko", "vi", "lo", "km", "my", "bo", "si")   # nur nicht-lateinische Schriften
FOLDED_TH_LOGPROB = -0.6          # strenger, wenn Thai nur über diesen Umweg zustande kam (Rauschen)
_IDS = itertools.count(1)


def new_id():
    return f"u{next(_IDS)}"
VOICE = {"th": "Kanya", "en": "Samantha"}
THAI_MODEL = "Vinxscribe/biodatlab-whisper-th-medium-faster"   # CTranslate2-Version von biodatlab/whisper-th-medium-combined
TARGET = {"en": "th", "th": "en"}
# Weckwort nur am Satzanfang: "Translator, pause" / "Hey translator resume"
WAKE = re.compile(r"^\W*(?:hey|hi|ok|okay)?\W*translat(?:or|er)\b\W*(.*)$", re.I | re.S)
# unscharf ("Translate or pause", "Translate to a pulse") – zählt nur, wenn ein Befehl folgt
WAKE_FUZZY = re.compile(r"^\W*(?:hey|hi|ok|okay)?\W*tr\w*nsl\w*\W*(?:(?:or|to|a|the|uh|um)\b\W*)*(.*)$",
                        re.I | re.S)
HOTWORDS = ("Translator pause resume repeat slower faster louder quieter Thai only English only "
            "auto female voice male voice clear help")
# Schlüsselwörter je Befehl (inkl. typischer Verhörer aus echten Logs)
COMMANDS = [
    ("pause", ["pause", "stop", "sleep", "be quiet", "mute", "post", "pulse", "pose", "paws",
               "pours", "pals", "pass", "porsche", "paul's", "pores"]),
    ("resume", ["resume", "continue", "start", "wake up", "go on", "unpause", "presume", "rezoom"]),
    ("repeat", ["repeat", "again", "say that", "re-peat", "repeats"]),
    ("slower", ["slower", "slow down", "slowly"]),
    ("faster", ["faster", "speed up", "quicker"]),
    ("louder", ["louder", "volume up", "lauder", "lower it up"]),
    ("quieter", ["quieter", "softer", "volume down", "quiet"]),
    ("female", ["female", "woman", "women", "girl", "lady", "she"]),
    ("male", ["male", "man", "men", "guy", "he"]),
    ("clear", ["clear", "delete", "reset", "clean"]),
    ("both_on", ["translate both", "both ways", "both directions", "everything"]),
    ("help", ["help", "commands", "what can you do"]),
]


def parse_command(cmd):
    """Befehl erkennen -> Schlüssel oder None. Leerer Text = nur das Weckwort."""
    import difflib
    c = cmd.lower().strip(" .,!?")
    if not c:
        return "wake"
    has = lambda *w: any(re.search(rf"\b{re.escape(x)}\b", c) for x in w)
    thai_w = ("thai", "tie", "ty", "tai", "thigh", "time", "type")
    if has("off", "don't translate", "do not translate", "no translation", "keep"):
        if has(*thai_w): return "th_off"
        if has("english", "inglish"): return "en_off"
    if has("on") and not has("only"):
        if has(*thai_w): return "th_on"
        if has("english", "inglish"): return "en_on"
    if has("only", "mode"):
        if has("thai", "tie", "ty", "tai", "thigh", "time", "type"):
            return "thai"
        if has("english", "inglish"):
            return "english"
    if has("translate both", "both ways", "both directions", "translate everything"):
        return "both_on"
    if has("auto", "automatic", "both", "otto"):
        return "auto"
    for key, words in COMMANDS:
        if has(*words):
            return key
    # Ähnlichkeit als letzte Rettung (kurze Befehle)
    vocab = {w: k for k, ws in COMMANDS for w in ws if len(w) > 3}
    hit = difflib.get_close_matches(c.split()[0] if c.split() else c, list(vocab), n=1, cutoff=0.75)
    return vocab[hit[0]] if hit else None
# Neural-Stimmen: Thai passend zu ครับ (Mann) / ค่ะ (Frau)
NEURAL = {"th": {"krub": "th-TH-NiwatNeural", "ka": "th-TH-PremwadeeNeural"},
          "en": {"en": "en-US-AvaMultilingualNeural"}}
VOICES = {"en": ["en-US-AvaMultilingualNeural", "en-US-AndrewMultilingualNeural", "en-US-EmmaMultilingualNeural",
                 "en-GB-SoniaNeural"],
          "th": ["th-TH-NiwatNeural", "th-TH-PremwadeeNeural", "th-TH-AcharaNeural"]}
# typische Whisper-Halluzinationen bei Stille/Rauschen (nur wenn sie den ganzen Satz ausmachen)
JUNK = {"thank you for watching", "thanks for watching", "subtitles by", "ขอบคุณที่รับชม",
        "thank you very much for watching", "please subscribe",
        "like and subscribe", "subtitles by the amara.org community",
        "ขอบคุณครับ ที่รับชม", "ฝากกดติดตาม", "กดติดตามด้วยนะคะ", "สวัสดีครับ ยินดีต้อนรับสู่ช่อง",
        "ซับไตเติ้ลโดย", "[music]", "(music)", "[เพลง]"}
JUNK_IF_SHORT = {"thank you", "you", "bye", "ขอบคุณครับ", "ขอบคุณค่ะ"}   # nur bei sehr leiser/kurzer Aufnahme
FFMPEG = os.environ.get("DOLMETSCHER_FFMPEG") or shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
SAY = "/usr/bin/say"

C = {"en": "\033[1;34m", "th": "\033[1;33m", "dim": "\033[2m", "off": "\033[0m"}
JSON = False


_EMIT_LOCK = threading.RLock()     # RLock: der Signal-Handler (Stopp) darf auch emit aufrufen


def emit(event, **kw):
    with _EMIT_LOCK:                   # Mikrofon- und Arbeits-Thread schreiben beide
        _emit(event, **kw)


def _emit(event, **kw):
    if JSON:
        print(json.dumps({"event": event, **kw}, ensure_ascii=False), flush=True)
    elif event in ("loading", "ready", "calibrating", "error"):
        print(f"{C['dim']}{kw.get('msg', event)}{C['off']}", flush=True)
    elif event == "listening":
        print("\n🎙  Sprich einfach – Englisch oder Thai. (Strg+C beendet)\n", flush=True)
    elif event == "utt":
        flag = "🇬🇧 EN" if kw["lang"] == "en" else "🇹🇭 TH"
        print(f"\n{C['dim']}{flag}: {kw['text']}{C['off']}")
        print(f"{C[kw['to']]}➜ {kw['out']}{C['off']}  {C['dim']}(STT {kw['stt']:.1f}s, "
              f"Übers. {kw['tr']:.1f}s){C['off']}", flush=True)


LOGFILE = os.environ.get("DOLMETSCHER_LOG") or os.path.expanduser("~/Library/Logs/Dolmetscher/engine.log")
LOG_TEXT = False                  # --log-text: gesprochene/übersetzte Texte ins Log (Standard: aus)
_TEXT_KEYS = ("text", "alt_text", "alts", "out", "would_say", "cmd_retry", "command", "reply")
_LOGGER = None


def _logger():
    """engine.log rotiert bei ~1 MB, es bleiben 2 Dateien (engine.log + engine.log.1)."""
    global _LOGGER
    if _LOGGER is None:
        os.makedirs(os.path.dirname(LOGFILE), exist_ok=True)
        h = logging.handlers.RotatingFileHandler(LOGFILE, maxBytes=1_000_000, backupCount=1,
                                                 encoding="utf-8")
        h.setFormatter(logging.Formatter("%(asctime)s %(message)s", "%H:%M:%S"))
        lg = logging.getLogger("dolmetscher")
        lg.setLevel(logging.INFO)
        lg.propagate = False
        lg.addHandler(h)
        _LOGGER = lg
    return _LOGGER


def log(d):
    try:
        if not LOG_TEXT:
            d = {k: (f"<{len(v)} Zeichen>" if k in _TEXT_KEYS and isinstance(v, str) else
                      [f"<{len(x)} Zeichen>" for x in v] if k in _TEXT_KEYS and isinstance(v, (list, tuple)) else v)
                 for k, v in d.items()}
        _logger().info(json.dumps(d, ensure_ascii=False))
    except Exception:
        pass


class KeepAlive:
    """HTTPS-GET über eine offene Verbindung je Host (spart TLS-Handshake pro Satz, ~0,2–0,5 s)."""

    def __init__(self):
        self.conns, self.lock = {}, threading.Lock()

    def get_json(self, url, timeout):
        u = urllib.parse.urlsplit(url)
        path = u.path + ("?" + u.query if u.query else "")
        with self.lock:
            for attempt in (0, 1):                     # tote Verbindung: einmal neu aufbauen
                c = self.conns.get(u.netloc)
                if c is None:
                    c = self.conns[u.netloc] = http.client.HTTPSConnection(u.netloc, timeout=timeout)
                c.timeout = timeout
                if c.sock is not None:
                    c.sock.settimeout(timeout)
                try:
                    c.request("GET", path, headers={"User-Agent": "Mozilla/5.0", "Connection": "keep-alive"})
                    r = c.getresponse()
                    body = r.read()
                except (http.client.HTTPException, ConnectionError, OSError) as e:
                    c.close()
                    self.conns.pop(u.netloc, None)
                    if attempt or isinstance(e, TimeoutError):
                        raise urllib.error.URLError(e) from e
                    continue
                if r.status >= 400:
                    raise urllib.error.HTTPError(url, r.status, r.reason, r.headers, None)
                return json.loads(body)


HTTP = KeepAlive()


def _get_json(url, timeout):
    return HTTP.get_json(url, timeout)


_CACHE = collections.OrderedDict()           # (text, src, dst, provider-art) -> Übersetzung
_CACHE_MAX = 300


def _norm(s):
    return re.sub(r"[\s.,!?。]+", " ", s.lower()).strip()


def warm_translate():
    """TLS-Aufbau zu Google vorab, damit der erste Satz ihn nicht zahlt. Fehler still ignoriert."""
    try:
        _get_json("https://translate.googleapis.com/translate_a/single?client=gtx&dt=t&sl=en&tl=th&q=hi", 4)
    except Exception:
        pass


def google_translate(text, src, dst):
    u = ("https://translate.googleapis.com/translate_a/single?client=gtx&dt=t"
         f"&sl={src}&tl={dst}&q={urllib.parse.quote(text)}")
    out = "".join(p[0] for p in _get_json(u, 6)[0] if p and p[0])
    if not out.strip():
        raise ValueError("leere Antwort von Google")
    if dst == "th" and re.search(r"[A-Za-z]{3}", text) and not re.search(r"[฀-๿]", out):
        raise ValueError("Google gab den Text unübersetzt zurück")
    if dst == "en" and re.search(r"[฀-๿]", out) and len(re.findall(r"[฀-๿]", out)) > len(out) / 2:
        raise ValueError("Google gab Thai statt Englisch zurück")
    return out


def mymemory_translate(text, src, dst, e1=None):
    try:
        d = _get_json(f"https://api.mymemory.translated.net/get?q={urllib.parse.quote(text)}"
                      f"&langpair={src}|{dst}", 8)
    except urllib.error.URLError as e2:
        if (isinstance(e1, urllib.error.URLError) and not isinstance(e1, urllib.error.HTTPError)
                and not isinstance(e2, urllib.error.HTTPError)):
            raise RuntimeError("offline – keine Internetverbindung") from e2
        raise RuntimeError(f"MyMemory nicht erreichbar ({e2})") from e2
    out = ((d.get("responseData") or {}).get("translatedText") or "").strip()
    status = str(d.get("responseStatus", ""))
    # MyMemory meldet Kontingent/Fehler als Text in translatedText – nie vorlesen
    if (status != "200" or d.get("quotaFinished") or not out
            or re.match(r"(MYMEMORY WARNING|QUERY LENGTH LIMIT|INVALID|PLEASE SELECT)", out, re.I)):
        raise RuntimeError(f"MyMemory-Fehler {status or '?'}: {(d.get('responseDetails') or out)[:120]}")
    return out


LLM = {"on": False, "model": "claude-haiku-5-5", "client": None, "err": None, "skip_until": 0.0}
LLM["context"] = 8                 # so viele letzte Sätze (Verlauf) gehen als Kontext an Claude
LLM_BACKOFF = 60.0                 # s ohne Claude nach einem Fehler (dann direkt Google)
KEYFILE = os.path.expanduser("~/Library/Application Support/Dolmetscher/anthropic_key")


def llm_client():
    """Anthropic-Client, wenn das SDK installiert ist und ein Schlüssel vorliegt (Umgebung oder Datei)."""
    if LLM["client"] is None:
        import anthropic
        key = os.environ.get("ANTHROPIC_API_KEY")
        if not key and os.path.exists(KEYFILE):
            with open(KEYFILE, encoding="utf-8") as f:
                key = f.read().strip() or None
        LLM["client"] = anthropic.Anthropic(api_key=key, timeout=5.0, max_retries=0) if key else \
            anthropic.Anthropic(timeout=5.0, max_retries=0)
    return LLM["client"]


def llm_available():
    try:
        import anthropic  # noqa: F401
    except ImportError:
        return False
    return bool(os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN")
                or (os.path.exists(KEYFILE) and os.path.getsize(KEYFILE) > 0))


LLM_SYSTEM = (
    "You are a live consecutive interpreter between English and Thai in a face-to-face conversation. "
    "The input comes from automatic speech recognition and can contain misheard words: Thai near-homophones "
    "(e.g. ม่วงนอน or ยุ่งนอน is almost certainly ง่วงนอน 'sleepy'), missing tone marks, wrong spacing, "
    "English words written in Thai script. Use the recent conversation and the alternative hypotheses to infer "
    "what the speaker most likely meant, then translate that meaning naturally, the way a person would say it. "
    "Ignore filler words (um, uh, like, you know, เอ่อ) and idioms: translate the meaning, never word by word. "
    "Thai often drops subjects; restore them in English from context. Keep names, numbers, prices and times exact. "
    "{setting} "
    "Thai particles (นะ, จ้า, จ๊ะ, อ่ะ, เนอะ, ค่ะ/ครับ) carry tone, not words: render the feeling, not a literal word. "
    "Thai slang and short replies (ใช่, โอเค, จริงดิ, ไม่เป็นไร) get short natural English. "
    "Into Thai: casual, friendly spoken Thai between partners, matching the speaker's register; no stiff or "
    "formal wording (no ท่าน, no written-language phrasing). "
    "Reply with the translation only: no quotes, no notes, no romanization, no alternatives.")


GLOSSARY_FILE = os.path.expanduser("~/Library/Application Support/Dolmetscher/glossary.txt")
GLOSSARY = []                      # [(Wort, Übersetzung oder None = unverändert lassen)]


def load_glossary(text=None):
    """Eigene Wörter: je Zeile `Wort => Übersetzung` oder nur `Name` (nicht übersetzen).
    `text=None` liest die Datei; sonst wird der Text übernommen und gespeichert."""
    if text is None:
        try:
            with open(GLOSSARY_FILE, encoding="utf-8") as f:
                text = f.read()
        except OSError:
            text = ""
    else:
        try:
            os.makedirs(os.path.dirname(GLOSSARY_FILE), exist_ok=True)
            with open(GLOSSARY_FILE, "w", encoding="utf-8") as f:
                f.write(text)
        except OSError as e:
            log({"glossary": "speichern fehlgeschlagen", "err": repr(e)[:120]})
    items = []
    for line in text.splitlines():
        a, sep, b = line.partition("=>")
        a, b = a.strip(), b.strip()
        if a:
            items.append((a, b if sep and b else None))
    GLOSSARY[:] = items[:200]
    _CACHE.clear()                     # alte Übersetzungen kennen die neuen Einträge nicht


def glossary_hits(text):
    low = text.lower()
    return [(a, b) for a, b in GLOSSARY if a.lower() in low]


PRONOUNCE_FILE = os.path.expanduser("~/Library/Application Support/Dolmetscher/pronounce.txt")
PRONOUNCE = []                     # [(Text, gesprochen)] – nur für die Sprachausgabe, Anzeige bleibt


def load_pronounce(path=None):
    """Aussprache-Ersetzungen: je Zeile `Text => gesprochen`. Gilt nur für TTS."""
    try:
        with open(path or PRONOUNCE_FILE, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        text = ""
    items = []
    for line in text.splitlines():
        a, sep, b = line.partition("=>")
        a, b = a.strip(), b.strip()
        if a and sep and b:
            items.append((a, b))
    PRONOUNCE[:] = items[:200]


def apply_pronounce(text):
    for a, b in PRONOUNCE:
        text = re.sub(re.escape(a), lambda m: b, text, flags=re.I)
    return text


STYLES = {
    "casual": ("Setting: a private, relaxed conversation at home between two people who are dating. Translate "
               "the way they would actually talk to each other: warm, casual, natural, never formal or textbook-like."),
    "neutral": ("Setting: an everyday conversation between two adults. Translate in a natural, friendly, "
                "neutral register: neither slangy nor stiff."),
    "polite": ("Setting: a polite conversation with a stranger or service staff (shop, restaurant, taxi, hotel). "
               "Translate courteously and clearly; use polite forms, no slang."),
}
LLM_PRICE = {"claude-haiku-5-5": (0.10, 0.50), "claude-sonnet-5-5": (2.0, 10.0), "claude-opus-5-5": (4.0, 20.0)}
LLM["style"] = "casual"
LLM["usd"] = 0.0


def claude_translate(text, src, dst, history=(), alts=(), polite="krub"):
    client = llm_client()
    names = {"en": "English", "th": "Thai"}
    ctx = "\n".join(f"[{names[l]}] {t}  =>  {o}" for l, t, o in list(history)[-LLM["context"]:])
    parts = []
    if ctx:
        parts.append(f"Recent conversation (original => translation):\n{ctx}")
    hits = glossary_hits(text)
    if hits:
        parts.append("Glossary (use exactly these; a word without arrow stays unchanged):\n" + "\n".join(
            f"- {a} => {b}" if b else f"- {a} (keep as is)" for a, b in hits))
    if alts:
        parts.append("Other recognition hypotheses for the same audio:\n" + "\n".join(f"- {a}" for a in alts))
    if dst == "th":
        parts.append(f"The person speaking Thai output is {'male: use ครับ/ผม' if polite == 'krub' else 'female: use ค่ะ/คะ/ฉัน'}"
                     " where a polite particle fits.")
    parts.append(f"Translate this {names[src]} speech into {names[dst]}:\n{text}")
    r = client.messages.create(model=LLM["model"], max_tokens=4096, output_config={"effort": "low"},
                               system=LLM_SYSTEM.replace("{setting}", STYLES.get(LLM["style"], STYLES["casual"])),
                               messages=[{"role": "user", "content": "\n\n".join(parts)}])
    pin, pout = LLM_PRICE.get(LLM["model"], (4.0, 20.0))
    u = getattr(r, "usage", None)
    if u is not None:                               # Kosten mitzählen (Schätzung nach Preisliste)
        LLM["usd"] += ((getattr(u, "input_tokens", 0) or 0) * pin + (getattr(u, "output_tokens", 0) or 0) * pout) / 1e6
        emit("llm_cost", usd=round(LLM["usd"], 4))
    if r.stop_reason != "end_turn":                    # refusal, max_tokens, … -> nie halbe Sätze vorlesen
        raise RuntimeError(f"Claude: stop_reason {r.stop_reason}")
    out = "".join(b.text for b in r.content if b.type == "text").strip().strip('"“”')
    if not out:
        raise RuntimeError("leere Antwort von Claude")
    return out


LAUGH = {"th": re.compile(r"(?<!\d)5{3,}(?!\d)|(?:ฮ่า\s*){2,}ๆ*|ฮ่า\s*ๆ+|(?:คิก\s*){2,}|คิก\s*ๆ+"),
         "en": re.compile(r"\b(?:a?ha(?:ha)+h?|lol|lmao|hehe(?:he)*)\b", re.I)}
LAUGH_OUT = {"th": "555", "en": "haha"}


FILLERS = {
    # nur eigenständige Zögerlaute und Einschübe zwischen Kommas ("It's, you know, good"); "As you know,"
    # oder "Would you like, a coffee" bleiben unberührt
    "en": re.compile(r"(?:(?<=\s)|^)(?:u+m+|u+h+|e+r+m*|h+m+|m+h+m+)\b[,]?(?=\s|[.!?]|$)"
                     r"|(?<=\w),\s*(?:you know|i mean|like|sort of|kind of)\s*,(?=\s)", re.I),
    # nur als eigenes Wort (sonst würde "อ่า" aus "อ่าน" gerissen)
    "th": re.compile(r"(?:(?<=\s)|^)(?:เอ่อ|เออ|อืม|อ่า|เอ๊ะ)(?=\s|$)"),
}


def strip_fillers(text, lang):
    """Füllwörter (um, uh, ", you know,", เอ่อ) vor der Übersetzung entfernen – sie verwirren Google
    und kosten Claude Zeit. Bleibt nichts Sinnvolles übrig, gilt der Originaltext."""
    rx = FILLERS.get(lang)
    if not rx:
        return text
    out = rx.sub(lambda m: "," if m.group(0).lstrip().startswith(",") else " ", text)
    out = re.sub(r"\s{2,}", " ", out)
    out = re.sub(r"\s+([.,!?])", r"\1", out).strip(" ,")
    return out if re.search(r"\w", out) else text


def translate(text, src, dst, history=(), alts=(), polite="krub", meta=None):
    """Lachen (555, ฮ่าๆ, haha, lol) nicht übersetzen lassen – Google macht daraus "555" oder Unsinn –,
    sondern als Lachen der Zielsprache anhängen. Rest wie _translate."""
    text = strip_fillers(text, src)
    rx = LAUGH.get(src)
    if rx and rx.search(text):
        rest = rx.sub(" ", text).strip(" ,.!")
        if not rest:
            if meta is not None:
                meta.update(provider="none")
            return LAUGH_OUT[dst]
        return _translate(rest, src, dst, history, alts, polite, meta).rstrip() + " " + LAUGH_OUT[dst]
    return _translate(text, src, dst, history, alts, polite, meta)


def _translate(text, src, dst, history=(), alts=(), polite="krub", meta=None):
    """Claude (wenn an und verfügbar) → Google (gtx) → MyMemory. Wirft eine Exception statt eine
    Fehlermeldung zu liefern. `meta` (dict) bekommt provider und cached."""
    meta = meta if meta is not None else {}
    use_llm = LLM["on"] and time.time() >= LLM["skip_until"] and llm_available()
    key = (_norm(text), src, dst, ("llm:" + LLM["model"] + ":" + LLM["style"]) if use_llm else "mt",
           polite if dst == "th" else "")
    if key in _CACHE and not (use_llm and history):        # mit Verlauf ist der Kontext jedes Mal anders
        _CACHE.move_to_end(key)
        meta.update(provider=_CACHE[key][1], cached=True)
        return _CACHE[key][0]
    out, e1 = None, None
    if use_llm:
        try:
            out = claude_translate(text, src, dst, history, alts, polite)
            meta["provider"] = "claude"
            LLM["err"] = None
        except Exception as e:
            LLM["err"] = repr(e)[:200]
            LLM["skip_until"] = time.time() + LLM_BACKOFF
            log({"translate": "claude-fehler", "err": LLM["err"]})
    if out is None:
        try:
            out = google_translate(text, src, dst)
            meta["provider"] = "google"
        except Exception as e:
            e1 = e
            log({"translate": "google-fehler", "err": repr(e)[:200]})
            out = mymemory_translate(text, src, dst, e1)
            meta["provider"] = "mymemory"
    if use_llm and meta["provider"] != "claude":         # Google-Ersatz nicht als Claude-Ergebnis merken
        key = key[:3] + ("mt",) + key[4:]
    _CACHE[key] = (out, meta["provider"])
    if len(_CACHE) > _CACHE_MAX:
        _CACHE.popitem(last=False)
    return out


_TH_RX = re.compile(r"[\u0e00-\u0e7f]")


_THAINLP = {"missing": False}


@functools.lru_cache(maxsize=512)
def thai_latin(text):
    """Lesbare Umschrift (RTGS, Wort für Wort getrennt) für Thai-Text; None ohne pythainlp oder bei
    Fehlern – die App nimmt dann ihre eigene Umschrift."""
    if not _TH_RX.search(text or "") or _THAINLP["missing"]:
        return None
    try:
        from pythainlp.tokenize import word_tokenize
        from pythainlp.transliterate import romanize
        words = []
        for w in word_tokenize(text):
            if not w.strip():
                continue
            r = romanize(w, engine="royin") if w != "ก็" else "ko"
            words.append(_TH_RX.sub("", r))                  # übrig gebliebene Thai-Zeichen/Marken weglassen
        out = " ".join(x for x in words if x)
    except ImportError:
        _THAINLP["missing"] = True                     # einmal merken, nicht für jeden Satz neu versuchen
        return None
    except Exception as e:
        log({"translit": "fehler", "err": type(e).__name__})   # kein Text im Log
        return None
    out = re.sub(r"\s+", " ", out).strip()
    return out or None


_NUM = re.compile(r"\d+(?:[.,:]\d+)*")
_THAI_DIGITS = str.maketrans("๐๑๒๓๔๕๖๗๘๙", "0123456789")


def _numbers(s):
    out = (re.sub(r"[.,:]", "", x) for x in _NUM.findall(s.translate(_THAI_DIGITS)))
    return sorted(x for x in out if not re.fullmatch(r"5{3,}", x))      # 555 = Lachen, keine Zahl


def numbers_differ(a, b):
    """True, wenn Ziffern im Original und in der Übersetzung nicht übereinstimmen (Preise, Zeiten)."""
    na, nb = _numbers(a), _numbers(b)
    return bool(na and nb) and na != nb


def fix_thai(s, polite):
    """Google liefert 'ครับ/ค่ะ' – eine Form wählen, sonst liest Kanya den Schrägstrich vor."""
    male = polite == "krub"
    s = re.sub(r"ครับ\s*/\s*ค่ะ|ค่ะ\s*/\s*ครับ", "ครับ" if male else "ค่ะ", s)
    s = re.sub(r"ครับ\s*/\s*คะ|คะ\s*/\s*ครับ", "ครับ" if male else "คะ", s)
    s = re.sub(r"ผม\s*/\s*ฉัน|ฉัน\s*/\s*ผม", "ผม" if male else "ฉัน", s)
    s = re.sub(r"คุณ\s*/\s*ท่าน|ท่าน\s*/\s*คุณ", "คุณ", s)
    if not male:   # Frage endet mit คะ (hoher Ton), Aussage mit ค่ะ
        s = re.sub(r"((?:ไหม|มั้ย|หรือ(?:เปล่า)?|อะไร|ที่ไหน|ไหน|เมื่อไหร่|เมื่อไร|ทำไม|ยังไง|อย่างไร|กี่\S*|ใคร)\s*)ค่ะ"
                   r"(?=\s*[?？]?\s*$|\s)", r"\1คะ", s)
    return s


def pick_voice(lang):
    v = VOICE[lang]
    out = subprocess.run([SAY, "-v", "?"], capture_output=True, text=True).stdout
    loc = "th_TH" if lang == "th" else "en_US"
    for line in out.splitlines():                      # bessere Stimmen bevorzugen
        if loc in line and re.search(r"Premium|Enhanced|Erweitert", line):
            return line.split(loc)[0].strip()
    if v not in out:
        loc = "th_TH" if lang == "th" else "en_US"
        for line in out.splitlines():
            if loc in line:
                return line.split(loc)[0].strip()
    return v


def apply_profile_prior(probs, pe, pt, plang):
    """Sprache einer erkannten Person als Entscheidungshilfe – aber nie gegen eine klar
    erkannte dritte Sprache (z. B. Deutsch), damit 'nur Englisch und Thai' gilt."""
    top_lang, top_p = probs[0] if probs else ("", 0.0)
    if top_lang not in ("en", "th") and top_p >= 0.6:
        return pe, pt                                    # eindeutig andere Sprache -> Filter greift
    if max(pe, pt) < 0.8 or pe + pt < MIN_LANG_P:        # unsicher -> Sprache der Person
        if plang == "th":
            pt = max(pt, pe + 0.01, MIN_LANG_P)
        else:
            pe = max(pe, pt + 0.01, MIN_LANG_P)
    return pe, pt


def _warm(m):
    """Probelauf: der erste echte Satz ist sonst spürbar langsamer."""
    m.detect_language(audio=np.zeros(SR, dtype=np.float32))
    list(m.transcribe(np.zeros(SR, dtype=np.float32), language="en")[0])


def _wm(model, **kw):
    """Modell von der Platte laden, ohne bei jedem Start beim Hub nachzufragen (Modelle liegen
    nach dem ersten Mal im Cache). Nur wenn es lokal fehlt: herunterladen."""
    try:
        return WhisperModel(model, local_files_only=True, **kw)
    except Exception as e:
        log({"model": model, "download": True, "err": repr(e)[:200]})
        return WhisperModel(model, **kw)


def load_model(model, device):
    """Apple-GPU (MPS) wenn möglich – ca. 2-4x schneller –, sonst CPU."""
    if device in ("auto", "mps"):
        try:
            m = _wm(model, device="mps", compute_type="float16")
            _warm(m)
            return m, "mps"
        except Exception as e:
            log({"mps": "nicht verfügbar", "err": repr(e)[:200]})
            if device == "mps":
                raise
    m = _wm(model, device="cpu", compute_type="int8")
    try:
        _warm(m)
    except Exception as e:
        log({"warmup": "fehler", "err": repr(e)[:200]})
    return m, "cpu"


def normalize(audio, target_rms=0.06, max_gain=10.0, peak=0.95):
    """RMS-Normalisierung mit Obergrenze: hebt leise Sprecher an, ohne Rauschen beliebig zu verstärken."""
    if not audio.size:
        return audio, 0.0
    rms = float(np.sqrt(np.mean(audio ** 2)))
    pk = float(np.max(np.abs(audio)))
    if rms <= 1e-5 or pk <= 0:
        return audio, pk
    g = min(target_rms / rms, max_gain, peak / pk)
    return (audio * g if g > 1.0 else audio), pk


def split_sentences(s, lang, min_len=60):
    """Lange Ausgaben satzweise vorlesen: der erste Satz klingt früher, der Rest wird vorab geladen."""
    s = s.strip()
    if len(s) < min_len:
        return [s]
    if lang == "th":   # Thai trennt Sätze/Phrasen mit Leerzeichen
        parts = re.split(r"(?<=[฀-๿\d])\s+(?=[฀-๿])", s)
    else:
        parts = re.split(r"(?<=[.!?;])\s+", s)
    out, cur = [], ""
    for p in parts:                     # zu kurze Stücke zusammenfassen (natürlicher Klang)
        cur = f"{cur} {p}".strip() if cur else p
        if len(cur) >= min_len // 2:
            out.append(cur)
            cur = ""
    if cur:
        if out and len(cur) < min_len // 3:
            out[-1] += " " + cur
        else:
            out.append(cur)
    return out or [s]


def squash_repeats(text):
    """Wiederholungsschleifen kürzen statt den ganzen Satz zu verlieren:
    'สติ๊กฮ่าาาาาาา' -> 'สติ๊กฮ่าาา', 'ha ha ha ha ha ha' -> 'ha ha ha'."""
    text = re.sub(r"(\D)\1{3,}", r"\1\1\1", text)
    text = re.sub(r"(.{2,12}?)(?:\s*\1){3,}", r"\1 \1 \1", text)
    return text


def looks_hallucinated(text, dur, segs):
    """Typische Whisper-Halluzination: Wiederholungsschleife oder unmöglich viele Zeichen pro Sekunde."""
    if any(getattr(s, "compression_ratio", 0) > 2.6 for s in segs):
        return "wiederholung"
    chars = len(re.sub(r"\s", "", text))
    if dur > 0 and chars / dur > 30:                    # selbst schnelles Thai hat < ~20 Zeichen/s
        return "zu schnell"
    return None


NULL_AUDIO = bool(os.environ.get("DOLMETSCHER_NULL_AUDIO"))


class Player:
    """Eigene Sprachausgabe (afplay/say/ffmpeg): merkt sich den Kindprozess, damit Stopp und
    Barge-in ihn sofort beenden können, und sperrt das Mikrofon, solange er läuft (+ Nachhall)."""
    TAIL = 0.3                         # s Nachhall nach Ende der Ausgabe

    def __init__(self):
        self.lock = threading.Lock()
        self.procs = {}                # Popen -> Startzeit
        self.killed = set()
        self.spans = []                # vergangene Ausgaben (start, ende)
        self.interrupted = False       # durch Barge-in/Stopp abgebrochen

    def start(self, cmd, **kw):
        if NULL_AUDIO:                 # Tests: kompletter Ausgabe-Pfad, aber ohne Ton
            cmd = ["/bin/sleep", "1"] if cmd[0].endswith("afplay") else ["/bin/cat"]
        p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **kw)
        with self.lock:
            self.procs[p] = time.time()
        return p

    def wait(self, p):
        try:
            p.wait()
        finally:
            with self.lock:
                start = self.procs.pop(p, None)
                self.killed.discard(p)
                if start is not None:
                    self.spans = (self.spans + [(start, time.time())])[-20:]
                    log({"play_span": [round(start % 1000, 2), round(time.time() % 1000, 2)]})

    def run(self, cmd):
        self.wait(self.start(cmd))

    def playing(self):
        return bool(self.procs)

    def gated(self, t=None):
        """Konnte zum Aufnahmezeitpunkt t unsere eigene Stimme (oder ihr Nachhall) im Mikrofon
        landen? t ist die Aufnahme- und nicht die Lesezeit (der Leser kann hinterherhinken)."""
        if t is None:
            t = time.time()
        with self.lock:
            if any(st - 0.05 <= t for st in self.procs.values()):
                return True
            return any(st - 0.05 <= t <= en + self.TAIL for st, en in self.spans)

    def stop(self, tail=True):
        with self.lock:
            procs = [p for p in self.procs if p not in self.killed]
            self.killed.update(procs)
            if procs:
                self.interrupted = True
            if not tail:
                self.spans = []
        for p in procs:
            try:
                p.kill()
            except OSError:
                pass
        return bool(procs)


PLAYER = Player()
HEARING = threading.Event()            # Mikrofon-Thread: gerade läuft eine Äußerung
BARGE_IN = False
DEBUG = bool(os.environ.get("DOLMETSCHER_DEBUG"))


CANCEL = {"gen": 0}                    # Stopp/Barge-in/Stumm erhöhen -> laufende Ausgabe bricht ab


def wait_quiet(limit=5.0, cancelled=None):
    """Nicht in eine laufende Äußerung hineinsprechen (sonst würde sie abgeschnitten)."""
    t = time.time()
    while HEARING.is_set() and time.time() - t < limit and not BARGE_IN and not (cancelled and cancelled()):
        time.sleep(0.03)
    return time.time() - t


HEDGE = 0.8                            # s ohne Ton bis zum zweiten TTS-Versuch (Log: 1. Ton oft erst nach ~2 s)
FIRST_DEADLINE = 3.0                   # s ohne Ton -> macOS-Stimme übernimmt (vorher 6 s)
_TTS_LOOP = None
_TTS_LOCK = threading.Lock()
NET = {"translate": True, "tts": True}


def net_state(what, ok):
    """Online/Offline-Wechsel einmal melden (App zeigt dann ein Symbol)."""
    if NET.get(what) != ok:
        NET[what] = ok
        emit("net", ok=ok, what=what)


def tts_loop():
    """Ein dauerhafter asyncio-Loop in eigenem Thread statt asyncio.run() je Satz."""
    global _TTS_LOOP
    with _TTS_LOCK:
        if _TTS_LOOP is None:
            import asyncio
            _TTS_LOOP = asyncio.new_event_loop()
            threading.Thread(target=_TTS_LOOP.run_forever, name="tts", daemon=True).start()
        return _TTS_LOOP


def tts_warmup():
    """Import, DNS und TLS vorab – zwei Verbindungen, weil der Aufbau gelegentlich hängt
    (Log: in ~50 % der Sätze griff der zweite Versuch)."""
    def run(i):
        t = time.time()
        try:
            import asyncio, edge_tts

            async def go():
                async for _ in edge_tts.Communicate("Hi.", NEURAL["en"]["en"]).stream():
                    pass
            asyncio.run_coroutine_threadsafe(go(), tts_loop()).result(timeout=15)
            log({"tts_warmup_s": round(time.time() - t, 2), "n": i})
        except Exception as e:
            log({"tts_warmup": "fehler", "err": repr(e)[:200]})
    for i in range(2):
        threading.Thread(target=run, args=(i,), name="tts-warmup", daemon=True).start()


_PIPE_PLAYER = None


def pipe_player(volume):
    """mp3 von stdin sofort abspielen: ffmpeg -> AudioToolbox, sonst ffplay, sonst None."""
    global _PIPE_PLAYER
    if _PIPE_PLAYER is None:
        try:
            dev = subprocess.run([FFMPEG, "-hide_banner", "-devices"], capture_output=True,
                                 text=True, timeout=5).stdout
        except Exception:
            dev = ""
        ffplay = shutil.which("ffplay") or (os.path.join(os.path.dirname(FFMPEG), "ffplay")
                                            if os.path.exists(os.path.join(os.path.dirname(FFMPEG), "ffplay")) else None)
        _PIPE_PLAYER = "at" if "audiotoolbox" in dev else (ffplay or "")
    fast = ["-probesize", "32", "-analyzeduration", "0", "-fflags", "nobuffer", "-f", "mp3"]
    if _PIPE_PLAYER == "at":
        return [FFMPEG, "-hide_banner", "-nostats", "-loglevel", "quiet", *fast, "-i", "pipe:0",
                "-af", f"volume={volume:.2f}", "-f", "audiotoolbox", "-"]
    if _PIPE_PLAYER:
        return [_PIPE_PLAYER, "-nodisp", "-autoexit", "-loglevel", "quiet", *fast,
                "-af", f"volume={volume:.2f}", "-i", "pipe:0"]
    return None


TTS_CACHE = collections.OrderedDict()  # (Stimme, Tempo, Text) -> mp3: kurze, häufige Sätze sofort
TTS_CACHE_MAX, TTS_CACHE_CHARS = 64, 120
TTS_RACE = 1.4                         # s: kommt die Neural-Stimme nicht, spricht die vorbereitete macOS-Stimme


class EdgeStream:
    """edge-tts-Anfrage, die sofort startet (Vorab-Laden, während noch etwas anderes spricht).
    Abgespielt wird später mit edge_play(). Bereits gehörte kurze Sätze kommen aus dem Cache."""

    def __init__(self, text, voice, rate):
        self.text, self.voice, self.rate = text, voice, rate
        self.key = (voice, rate, text)
        self.t0 = time.time()
        self.stop = threading.Event()
        self.hedged = False
        self.futs = []
        self.cached = TTS_CACHE.get(self.key)
        if self.cached is not None:
            q = queue.Queue()
            q.put(self.cached)
            q.put(None)
            self.qs, self.hedged = [q], True      # kein zweiter Versuch nötig
        else:
            self.qs = [self._request()]

    def _request(self):
        import asyncio, edge_tts
        q = queue.Queue()
        stop = self.stop

        async def produce():
            try:
                async for c in edge_tts.Communicate(self.text, self.voice, rate=self.rate).stream():
                    if stop.is_set() or getattr(q, "lost", False):
                        break
                    if c["type"] == "audio" and c["data"]:
                        q.put(c["data"])
            except Exception as e:
                q.put(e)
                return
            q.put(None)
        self.futs.append(asyncio.run_coroutine_threadsafe(produce(), tts_loop()))
        return q

    def first(self, deadline=None):
        """Erster Audioblock (mit zweitem Versuch nach HEDGE s). Wirft, wenn bis zur Frist nichts kam."""
        deadline = FIRST_DEADLINE if deadline is None else deadline
        t_wait = time.time()
        errs = []
        while time.time() - t_wait < deadline:
            # zuerst nachsehen (vorab Geladenes liegt schon bereit), erst dann ggf. zweiter Versuch
            for cand in list(self.qs):
                try:
                    x = cand.get(timeout=0.02)
                except queue.Empty:
                    continue
                if x is None or isinstance(x, Exception):
                    errs.append(x)
                    self.qs.remove(cand)
                else:
                    for other in self.qs:
                        if other is not cand:
                            other.lost = True
                    return x, cand
            if not self.hedged and (not self.qs or time.time() - self.t0 > HEDGE):
                self.qs.append(self._request())     # zweiter Versuch: nach HEDGE s oder sofort bei Fehler
                self.hedged = True
            if not self.qs:
                break
        self.cancel()
        raise (errs[-1] if errs and errs[-1] else RuntimeError("edge-tts lieferte keine Audiodaten"))

    def cancel(self):
        self.stop.set()
        for q in self.qs:
            q.lost = True
        for f in self.futs:                     # hängende Websockets wirklich beenden
            f.cancel()


def edge_play(stream, volume, on_start=None, cancelled=None, deadline=None):
    """Vorab gestartete edge-tts-Anfrage abspielen, ab dem ersten Block. Gibt Kennzahlen zurück;
    wirft nur, wenn noch kein Ton kam (dann übernimmt 'say', ohne Doppelung)."""
    t0 = time.time()
    first, q = stream.first(deadline)
    got, complete = [], False
    stats = {"first_chunk_s": round(time.time() - t0, 2), "since_request_s": round(time.time() - stream.t0, 2),
             "hedged": stream.hedged}
    stats["waited_s"] = round(wait_quiet(cancelled=cancelled), 2)
    cmd = pipe_player(volume)
    if cancelled and cancelled():
        stream.cancel()
        stats["interrupted"] = True
        return stats
    try:
        if cmd:
            p = PLAYER.start(cmd, stdin=subprocess.PIPE)
            stats["play_start_s"] = round(time.time() - t0, 2)
            if on_start:
                on_start(stats["play_start_s"])
            chunk = first
            try:
                while chunk is not None:
                    if isinstance(chunk, Exception):
                        stats["err"] = repr(chunk)[:120]
                        break
                    if cancelled and cancelled():
                        break
                    p.stdin.write(chunk)
                    got.append(chunk)
                    chunk = q.get(timeout=6)
                complete = chunk is None
            except (BrokenPipeError, OSError, queue.Empty) as e:  # abgebrochen oder Netz weg
                if not (cancelled and cancelled()):
                    stats["err"] = repr(e)[:120]
            finally:
                try:
                    p.stdin.close()
                except OSError:
                    pass
                PLAYER.wait(p)
        else:                                   # kein Pipe-Player: puffern, dann afplay
            parts, chunk = [first], q.get(timeout=6)
            while chunk is not None and not isinstance(chunk, Exception):
                parts.append(chunk)
                chunk = q.get(timeout=6)
            fd, mp3 = tempfile.mkstemp(prefix="dolmetscher_tts_", suffix=".mp3")
            try:
                with os.fdopen(fd, "wb") as f:
                    f.write(b"".join(parts))
                stats["play_start_s"] = round(time.time() - t0, 2)
                if on_start:
                    on_start(stats["play_start_s"])
                PLAYER.run(["/usr/bin/afplay", "-v", f"{volume:.2f}", mp3])
            finally:
                os.remove(mp3)
    finally:
        stream.cancel()
    stats["cached"] = stream.cached is not None
    if complete and stream.cached is None and len(stream.text) <= TTS_CACHE_CHARS:
        TTS_CACHE[stream.key] = b"".join(got)
        if len(TTS_CACHE) > TTS_CACHE_MAX:
            TTS_CACHE.popitem(last=False)
    stats["interrupted"] = bool(cancelled and cancelled())
    return stats


def edge_say(text, voice, rate, volume, on_start=None):
    """edge-tts streamen und ab dem ersten Block abspielen (ohne Vorab-Laden)."""
    return edge_play(EdgeStream(text, voice, rate), volume, on_start)


EARCON = "/System/Library/Sounds/Tink.aiff"


class LocalVoice:
    """macOS-Stimme im Hintergrund vorab rendern (say -o), damit sie sofort einspringen kann,
    wenn die Neural-Stimme hängt. Wird nur abgespielt, wenn edge-tts die Frist verpasst."""

    def __init__(self, text, voice, rate_pct):
        self.done = threading.Event()
        fd, self.path = tempfile.mkstemp(prefix="dolmetscher_race_", suffix=".aiff")
        os.close(fd)
        os.remove(self.path)
        self.voice = voice

        def run():
            try:
                subprocess.run([SAY, "-v", voice, "-r", str(int(185 * (1 + rate_pct / 100))), "-o", self.path, text],
                               capture_output=True, timeout=20)
            except Exception as e:
                log({"tts": "lokal-vorab-fehler", "err": repr(e)[:200]})
            self.done.set()
        threading.Thread(target=run, name="say-prerender", daemon=True).start()

    def ready_path(self, timeout=6.0):
        self.done.wait(timeout)
        return self.path if os.path.exists(self.path) and os.path.getsize(self.path) > 0 else None

    def cleanup(self):
        def rm():
            self.done.wait(20)
            try:
                os.remove(self.path)
            except OSError:
                pass
        threading.Thread(target=rm, daemon=True).start()


class Speaker:
    """Eigener Thread für die Sprachausgabe: Erkennung und Übersetzung des nächsten Satzes laufen
    weiter, während vorgelesen wird. Jede Ausgabe wird beim Einreihen schon bei edge-tts angefragt
    (Vorab-Laden). Aufhol-Modus: Warten Ausgaben, wird schneller gesprochen; bei großem Rückstand
    wird eine alte Ausgabe übersprungen (die Blase bleibt sichtbar, `speak_done skipped`)."""
    FAST_BOOST = 20                    # % schneller, wenn schon etwas wartet
    SKIP_AT = 3                        # so viele wartende Ausgaben dahinter -> ältere überspringen

    def __init__(self, eng):
        self.eng = eng
        self.items = collections.deque()
        self.cond = threading.Condition()
        self.busy = False
        threading.Thread(target=self._loop, name="speaker", daemon=True).start()

    def pending(self):
        with self.cond:
            return len(self.items) + (1 if self.busy else 0)

    def add(self, text, lang, uid, kind="speech", t_end=None):
        eng = self.eng
        with self.cond:
            behind = len(self.items) + (1 if self.busy else 0)
        item = {"id": uid, "lang": lang, "kind": kind, "parts": [], "t_end": t_end}
        if kind == "speech":
            boost = self.FAST_BOOST if behind else 0
            for s in split_sentences(apply_pronounce(text), lang):
                stream, local = None, None
                if eng.tts == "edge" and not eng.mute:
                    try:
                        stream = EdgeStream(s, eng.voice_for(lang), f"{5 + eng.rate + boost:+d}%")
                    except Exception as e:
                        log({"tts": "vorab-fehler", "err": repr(e)[:200]})
                    if TTS_RACE > 0 and stream is not None and stream.cached is None:
                        local = LocalVoice(s, eng.voice[lang], eng.rate + boost)
                item["parts"].append((s, stream))
                item.setdefault("local", []).append(local)
            item["boost"] = boost
        with self.cond:
            self.items.append(item)
            self.cond.notify_all()
        report_queue()

    def flush(self):
        """Alle wartenden Ausgaben verwerfen (Stopp, Barge-in, 'stop_speaking')."""
        with self.cond:
            dropped = list(self.items)
            self.items.clear()
            CANCEL["gen"] += 1
            playing = self.busy
        PLAYER.stop(tail=True)
        for it in dropped:
            for _, st in it["parts"]:
                if st:
                    st.cancel()
            emit("speak_done", id=it["id"], skipped=True, interrupted=True)
        report_queue()
        return bool(dropped) or playing

    def wait_idle(self, timeout=120):
        t = time.time()
        with self.cond:
            while (self.items or self.busy) and time.time() - t < timeout:
                self.cond.wait(0.1)

    def _loop(self):
        while True:
            with self.cond:
                while not self.items:
                    self.cond.wait()
                it = self.items.popleft()
                behind = len(self.items)
                self.busy = True
            try:
                if it["kind"] == "speech" and behind >= self.SKIP_AT:
                    for _, st in it["parts"]:
                        if st:
                            st.cancel()
                    log({"tts": "übersprungen", "id": it["id"], "behind": behind})
                    emit("speak_done", id=it["id"], skipped=True, interrupted=False)
                    continue
                self._play(it)
            except Exception as e:
                log({"speaker": "fehler", "err": repr(e)[:200]})
                emit("speak_done", id=it["id"], skipped=False, interrupted=True)
            finally:
                with self.cond:
                    self.busy = False
                    self.cond.notify_all()
                report_queue()

    def _play(self, it):
        eng, uid = self.eng, it["id"]
        if it["kind"] == "earcon":
            wait_quiet()
            emit("speaking", id=uid, first_s=0.0)
            PLAYER.run(["/usr/bin/afplay", "-v", f"{eng.volume:.2f}", EARCON])
            emit("speak_done", id=uid, skipped=False, interrupted=False)
            return
        started = {"v": False}
        g = CANCEL["gen"]

        def cancelled():
            return CANCEL["gen"] != g or self.eng.mute

        def on_start(first_s):
            if not started["v"]:
                started["v"] = True
                lat = round(time.time() - it["t_end"], 2) if it.get("t_end") else None
                emit("speaking", id=uid, first_s=first_s, latency_s=lat)
                log({"latency": {"id": uid, "end_to_sound_s": lat}})
        interrupted = False
        locals_ = it.get("local") or [None] * len(it["parts"])
        try:
            for (text, stream), local in zip(it["parts"], locals_):
                if cancelled():
                    interrupted = CANCEL["gen"] != g
                    break
                eng.speak(text, it["lang"], stream=stream, on_start=on_start, boost=it.get("boost", 0),
                          cancelled=cancelled, local=local)
        finally:
            for local in locals_:
                if local:
                    local.cleanup()
        if CANCEL["gen"] != g:
            interrupted = True
        for _, st in it["parts"]:
            if st:
                st.cancel()
        emit("speak_done", id=uid, skipped=False, interrupted=interrupted)


_QSTATE = {"stt": 0, "tts": 0, "last": None, "stt_q": None, "speaker": None}
_QLOCK = threading.RLock()


def report_queue():
    """Rückstand (wartende Äußerungen / Ausgaben) an die App melden, nur bei Änderung."""
    with _QLOCK:
        q, sp = _QSTATE["stt_q"], _QSTATE["speaker"]
        cur = (q.qsize() if q else 0, sp.pending() if sp else 0)
        if cur != _QSTATE["last"]:
            _QSTATE["last"] = cur
            emit("queue", stt=cur[0], tts=cur[1])


class Engine:
    def __init__(self, model, polite, lock="auto", tts="edge", device="auto", voices=None):
        self.lock, self.tts = lock, tts
        t = time.time()
        emit("loading", msg=f"Lade Whisper-Modell '{model}' …")
        # "best": medium für Erkennung + Thai, large-v3-turbo für Englisch (Akzente)
        self.m, self.device = load_model("medium" if model == "best" else model, device)
        # Spracherkennung mit small: 0,2–0,3 s statt 0,5–1,9 s (gemessen, M4 Pro/MPS), bei Thai
        # sogar sicherer. Allgemeines STT (Rückfall, zweite Lesart) bleibt beim größeren Modell.
        self.m_det = self.m
        if model != "small":
            try:
                self.m_det = load_model("small", self.device)[0]
            except Exception as e:
                log({"detect_model": "small nicht geladen", "err": repr(e)[:200]})
        if model == "best":
            emit("loading", msg="Lade Englisch-Modell large-v3-turbo …")
        self.m_en = load_model("large-v3-turbo", self.device)[0] if model == "best" else None
        # Thai: auf Thai trainiertes Whisper (biodatlab, MIT) – ~30 % weniger Fehler bei leiser/entfernter Sprache
        self.m_th = None
        if model != "small":
            try:
                emit("loading", msg="Lade Thai-Modell …")
                self.m_th = load_model(THAI_MODEL, self.device)[0]
            except Exception as e:
                log({"thai_model": "nicht geladen", "err": repr(e)[:200]})
        # Beam 1: gemessen (MPS, Thai-Modell) 1,45 s statt 2,5 s (Beam 3/5) bei gleichem Text; der
        # Decoder dominiert, weil Thai viele Tokens braucht.
        self.beam = int(os.environ.get("DOLMETSCHER_BEAM", "1"))   # Benchmark: Beam-Vergleich
        log({"model": model, "device": self.device, "load_s": round(time.time() - t, 1)})
        self.voice = {k: pick_voice(k) for k in VOICE}
        self.voices = {"en": None, "th": None, **(voices or {})}   # gewählte Neural-Stimmen (None = Standard)
        self.polite = polite
        self.paused, self.rate, self.volume = False, 0, 1.0     # rate in %, volume 0.2..2
        self.translate_dir = {"en": True, "th": True}          # Richtung einzeln abschaltbar
        self.last, self.awake_until, self.mute = None, 0.0, False
        self.earcons = False
        self.history = collections.deque(maxlen=8)             # (lang, text, out) – Kontext für Claude
        self.texts = {}                                        # id -> (lang, text) für Korrekturen
        self.spk = None
        self.two_person = True                 # "Englisch = ich, andere Stimme = Thai" (braucht ein EN-Profil)
        self.reload_profiles()
        self.speaker = Speaker(self)
        _QSTATE["speaker"] = self.speaker
        emit("ready", msg=f"bereit ({time.time()-t:.1f}s, {model} auf {self.device})", device=self.device,
             llm=bool(LLM["on"] and llm_available()))

    def reload_profiles(self):
        """Stimmprofile (neu) laden – auch nach dem Anlegen/Löschen in der App, ohne Neustart."""
        try:
            import profiles
            if profiles.list_profiles():
                if self.spk is None:
                    self.spk = profiles.SpeakerID()
                else:
                    self.spk.reload()
                log({"profiles": [p["name"] for p in self.spk.profiles]})
            else:
                self.spk = None
        except Exception as e:
            self.spk = None
            log({"profiles": "aus", "err": repr(e)[:200]})
        me = self.spk.me() if self.spk else None
        emit("roles", me=me["name"] if me else None, on=self.two_person and me is not None)

    def voice_for(self, lang):
        return self.voices.get(lang) or NEURAL[lang][self.polite if lang == "th" else "en"]

    def speak(self, text, lang, stream=None, on_start=None, boost=0, cancelled=None, local=None):
        """Natürliche Microsoft-Neural-Stimme (edge-tts, gestreamt), sonst macOS-Stimme. Blockiert
        bis zum Ende der Ausgabe – wird vom Speaker-Thread aufgerufen, nicht von der Erkennung."""
        if self.mute:
            log({"would_say": text})
            if stream:
                stream.cancel()
            return
        t = time.time()
        if self.tts == "edge":
            try:
                if stream is None:
                    stream = EdgeStream(text, self.voice_for(lang), f"{5 + self.rate + boost:+d}%")
                st = edge_play(stream, self.volume, on_start, cancelled,
                               deadline=TTS_RACE if (local and TTS_RACE > 0) else None)
                net_state("tts", True)
                log({"tts": "edge", "voice": stream.voice, **st, "secs": round(time.time() - t, 2)})
                return
            except Exception as e:
                log({"tts": "edge-fehler" if not local else "edge-zu-langsam", "err": repr(e)[:200]})
                if not local:
                    net_state("tts", False)
            if local:                            # Wettlauf verloren: vorbereitete macOS-Stimme sofort
                path = local.ready_path()
                if path and not (cancelled and cancelled()):
                    wait_quiet(cancelled=cancelled)
                    if cancelled and cancelled():
                        return
                    log({"tts": "lokal", "voice": local.voice, "after_s": round(time.time() - t, 2)})
                    if on_start:
                        on_start(round(time.time() - t, 2))
                    PLAYER.run(["/usr/bin/afplay", "-v", f"{self.volume:.2f}", path])
                    return
        fd, aiff = tempfile.mkstemp(prefix="dolmetscher_say_", suffix=".aiff")
        os.close(fd)
        try:
            os.remove(aiff)                        # nie eine alte Datei abspielen
            log({"tts": "say", "voice": self.voice[lang]})
            subprocess.run([SAY, "-v", self.voice[lang], "-r", str(int(185 * (1 + (self.rate + boost) / 100))),
                            "-o", aiff, text])
            if os.path.exists(aiff) and not (cancelled and cancelled()):
                wait_quiet(cancelled=cancelled)
                if cancelled and cancelled():
                    return
                if on_start:
                    on_start(round(time.time() - t, 2))
                PLAYER.run(["/usr/bin/afplay", "-v", f"{self.volume:.2f}", aiff])
        finally:
            if os.path.exists(aiff):
                os.remove(aiff)

    def reply(self, text):
        """Bestätigung eines Sprachbefehls: gesprochen oder als Signalton (--earcons)."""
        if self.earcons:
            self.speaker.add("", "en", "cmd", kind="earcon")
        else:
            self.speaker.add(text, "en", "cmd")

    def stop_speaking(self):
        flushed = self.speaker.flush()
        return PLAYER.stop(tail=True) or flushed

    def command(self, cmd):
        """Sprachbefehl ausführen. Gibt die gesprochene Bestätigung zurück."""
        key = parse_command(cmd)
        state = {}
        if key == "wake":
            self.awake_until = time.time() + 6
            reply = "Yes?"
        elif key == "pause":
            self.paused = True; reply = "Paused. Say translator, resume."
        elif key == "resume":
            self.paused = False; reply = "I'm listening."
        elif key == "repeat":
            if self.last:
                self.emit_state(cmd, "")
                self.speaker.add(self.last[0], self.last[1], "cmd")
                return None
            reply = "Nothing to repeat yet."
        elif key == "slower":
            self.rate = max(self.rate - 15, -50); reply = "Slower."
        elif key == "faster":
            self.rate = min(self.rate + 15, 50); reply = "Faster."
        elif key == "louder":
            self.volume = min(self.volume * 1.4, 2.0); reply = "Louder."
        elif key == "quieter":
            self.volume = max(self.volume / 1.4, 0.2); reply = "Quieter."
        elif key == "thai":
            self.lock = "th"; reply = "Okay, Thai only."
        elif key == "english":
            self.lock = "en"; reply = "Okay, English only."
        elif key == "auto":
            self.lock = "auto"; reply = "Okay, automatic."
        elif key == "female":
            self.polite = "ka"; reply = "Okay, female voice."
        elif key == "male":
            self.polite = "krub"; reply = "Okay, male voice."
        elif key in ("en_off", "th_off", "en_on", "th_on", "both_on"):
            if key == "both_on":
                self.translate_dir = {"en": True, "th": True}
            else:
                self.translate_dir[key[:2]] = key.endswith("_on")
            name = {"en": "English", "th": "Thai"}
            reply = ("Okay, translating both ways." if all(self.translate_dir.values()) else
                     " ".join(f"{name[k]} {'will be translated' if v else 'stays as it is'}."
                              for k, v in self.translate_dir.items()))
        elif key == "clear":
            state["clear"] = True; reply = "Cleared."
            self.history.clear()
        elif key == "help":
            reply = ("Say translator, then: pause, resume, repeat, slower, faster, louder, quieter, "
                     "Thai only, English only, auto, male or female voice, clear.")
        else:
            reply = "Sorry?"
        if key != "wake":
            self.awake_until = 0.0
        self.emit_state(cmd, reply, **state)
        log({"command": cmd, "key": key, "reply": reply})
        return reply

    def emit_state(self, cmd, reply, **extra):
        emit("command", text=cmd, reply=reply, paused=self.paused, lang=self.lock,
             tr_en=self.translate_dir["en"], tr_th=self.translate_dir["th"],
             polite=self.polite, rate=self.rate, volume=round(self.volume, 2),
             voice_en=self.voices.get("en") or "", voice_th=self.voices.get("th") or "", **extra)

    def _stt(self, audio, lang, hotwords=None, model=None, quick=False):
        """Text, mittlere log-prob, Segmente.
        - Token-Grenze nach Dauer (~14 Tokens/s + Reserve): lange Sätze passen ganz hinein (früher
          bei 160 abgeschnitten), aber eine Wiederholungsschleife auf fremdem Audio endet schnell.
        - temperature=0: keine Temperatur-Wiederholungen. Bei einer Halluzination rechnete Whisper
          sonst bis zu 6x neu (Log: 2 s Audio -> 60 s Rechenzeit, danach Stau von 7 Sätzen).
        - Thai: keine Wiederholungs-Sperren (มากๆ, ไม่ไม่ sind echtes Thai), keine zweite VAD.
        - quick: Gegenprobe in der anderen Sprache mit Beam 1 (nur der log-prob-Vergleich zählt)."""
        mdl = model or (self.m_en if (lang == "en" and self.m_en) else
                        self.m_th if (lang == "th" and self.m_th) else self.m)
        dur = audio.size / SR
        cap = int(min(440, 24 + 14 * dur))
        if lang == "th":
            kw = dict(repetition_penalty=1.0, no_repeat_ngram_size=0, vad_filter=False)
        else:
            kw = dict(repetition_penalty=1.1, no_repeat_ngram_size=4,
                      vad_filter=True, vad_parameters={"threshold": 0.1})
        segs, _ = mdl.transcribe(audio, language=lang, beam_size=1 if quick else self.beam, hotwords=hotwords,
                                 condition_on_previous_text=False, temperature=0.0,
                                 max_new_tokens=cap, **kw)
        segs = list(segs)
        if lang == "th":
            # Thai-Modell setzt Leerzeichen zwischen Wörter – Thai schreibt man ohne. Leerzeichen
            # zwischen Segmenten bleiben (sie trennen Phrasen und helfen der Übersetzung).
            parts = [re.sub(r"(?<=[฀-๿]) (?=[฀-๿])", "", s.text.strip()) for s in segs]
            text = " ".join(p for p in parts if p).strip()
        else:
            text = " ".join(s.text.strip() for s in segs).strip()
        lp = float(np.mean([s.avg_logprob for s in segs])) if segs else -9.0
        return text, lp, segs

    def _drop(self, info, reason, uid, emit_reason=None):
        info["drop"] = reason
        log(info)
        emit("dropped", reason=emit_reason or reason, id=uid)
        emit("listening")
        return None

    def process(self, audio, speak=True, rms=None, uid=None, t_end=None, version=None):
        uid = uid or new_id()
        emit("thinking", id=uid)
        t0 = time.time()
        EARLY_END.pop(uid, None)
        memo = PRE.pop(uid, None)
        if memo is not None and memo["version"] != version:
            memo = None                                # nach der Vorab-Erkennung wurde weitergesprochen

        def stt(a, lang, hotwords=None, model=None, quick=False):
            """_stt mit Wiederverwendung der Vorab-Erkennung (gleiche Sprache und Parameter)."""
            key = (lang, hotwords, quick)
            if memo is not None and model is None and key in memo["stt"]:
                return memo["stt"][key]
            return self._stt(a, lang, hotwords=hotwords, model=model, quick=quick)

        audio, peak = normalize(audio)                 # leise Sprecher anheben (RMS, mit Obergrenze)
        info = {"id": uid, "dur": round(audio.size / SR, 2), "rms": rms, "peak": round(peak, 3),
                "pre": memo is not None}
        times = {}
        if memo is not None:
            probs = memo["probs"]
        else:
            _, _, probs = self.m_det.detect_language(audio=audio, language_detection_segments=2)
        times["detect"] = round(time.time() - t0, 2)
        p = dict(probs)
        pe, pt_raw = p.get("en", 0.0), p.get("th", 0.0)
        pt, folded = pt_raw, False
        asian = sum(p.get(k, 0.0) for k in ASIAN_AS_TH)
        pt_all = pt_raw + asian                  # für die Sprach-Sperre „nur Englisch“
        if self.lock != "en":
            if asian > 0 and pt_raw < 0.3 and asian > pe:
                folded = True
            pt = pt_all
        # für den Profil-Prior: asiatische Labels zählen als Thai (sonst greift „klar andere Sprache“)
        probs = [("th" if k in ASIAN_AS_TH and self.lock != "en" else k, v) for k, v in probs]
        info.update(p_en=round(pe, 3), p_th=round(pt_raw, 3), p_th_eff=round(pt, 3), folded=folded,
                    top=[(k, round(v, 3)) for k, v in sorted(p.items(), key=lambda x: -x[1])[:3]])
        # --- Stimmprofil: wer spricht? Sprache des Profils hilft bei unsicherer Erkennung
        who, hot = None, None
        if self.spk:
            try:
                who, sim, scores = self.spk.identify(audio)
                info.update(speaker=who["name"] if who else None, spk_scores=scores)
            except Exception as e:
                log({"speaker": "fehler", "err": repr(e)[:200]})
        if who:
            hot = " ".join(who.get("vocab", [])) or None
            pe2, pt2 = apply_profile_prior(probs, pe, pt, who.get("lang", "en"))
            if (pe2, pt2) != (pe, pt):
                info["prior"] = who.get("lang", "en")
            pe, pt = pe2, pt2
        # --- Zwei-Personen-Modus: Englisch kommt von mir, jede andere Stimme spricht Thai.
        # Hilft genau bei kurzen Sätzen ("ok", "ใช่", "555"), bei denen die Spracherkennung rät.
        role = None
        if getattr(self, "two_person", False) and self.spk and self.lock not in ("en", "th"):
            try:
                role, rsim = self.spk.role(audio)
                info.update(role=role, role_sim=round(rsim, 3))
            except Exception as e:
                log({"role": "fehler", "err": repr(e)[:200]})
            if role == "me" and pt_raw >= 0.8 and audio.size >= SR:
                role = None                         # Erkennung hört klar Thai: nicht erzwingen
                info["role"] = "me?"
            if role == "me":
                pe, pt = max(pe, 0.95), min(pt, 0.05)
            if role == "other" and pe >= 0.9 and audio.size >= SR:
                role = None                         # klar Englisch (z. B. sie spricht Englisch)
                info["role"] = "other?"
            elif role == "other":
                pe, pt = min(pe, 0.05), max(pt, 0.95)
        if pe + pt < MIN_LANG_P:                  # weder Englisch noch Thai -> ignorieren
            return self._drop(info, "andere Sprache", uid, "weder Englisch noch Thai")
        segs = []
        if self.lock in ("en", "th"):
            lang = self.lock
            text, lp, segs = stt(audio, lang)
            info.update(mode="lock")
        else:
            lang = "th" if pt > pe else "en"
            text, lp, segs = stt(audio, lang, hotwords=hot if who and who.get("lang") == lang else None)
            # unklar? beide Sprachen probieren und die sicherere nehmen
            times["stt"] = round(time.time() - t0 - times["detect"], 2)
            # Gegenprobe in der anderen Sprache nur, wenn es wirklich unklar ist – und nicht bei Stau
            busy = _QSTATE["stt_q"] is not None and _QSTATE["stt_q"].qsize() >= 2
            unsure = (not text or lp < -0.8) if role else (
                (lang == "en" and pt > 0.2) or (lang == "th" and pe > 0.2) or not text
                or max(pe, pt) < 0.5 or lp < -0.8)
            if not busy and unsure:
                other = "th" if lang == "en" else "en"
                ta = time.time()
                t2, lp2, segs2 = stt(audio, other, quick=True)
                times["alt"] = round(time.time() - ta, 2)
                info.update(alt=other, alt_text=t2, alt_lp=round(lp2, 3), lp=round(lp, 3))
                if t2 and (lp2 > lp or not text) and not looks_hallucinated(t2, audio.size / SR, segs2):
                    lang, text, lp, segs = other, t2, lp2, segs2
        info.update(lang=lang, text=text, lp=round(lp, 3))

        # --- Sprachbefehle: "Translator, ..." (oder Folgesatz nach bloßem "Translator")
        en_text = text if lang == "en" else (stt(audio, "en")[0] if pe > pt else "")
        if re.match(r"^\W*(?:hey|hi|ok|okay)?\W*tr\w*nsl", en_text, re.I):
            # Befehlskandidat: einmal mit Befehls-Vokabular nachhören
            hw = stt(audio, "en", hotwords=HOTWORDS)[0]
            info["cmd_retry"] = hw
            en_text = hw or en_text
        m = WAKE.match(en_text)
        fz = None if m else WAKE_FUZZY.match(en_text)
        if fz and parse_command(fz.group(1)) not in (None, "wake"):
            m = fz                              # "Translate or pause" -> Befehl
        if m or (time.time() < self.awake_until and en_text):
            cmd = m.group(1) if m else en_text
            info["command"] = cmd
            log(info)
            emit("dropped", reason="befehl", id=uid)
            reply = self.command(cmd.strip(" .,!?"))
            if reply and speak:
                self.reply(reply)
            emit("listening")
            return None
        other = {"en": "th", "th": "en"}.get(self.lock)
        if other and {"en": pe, "th": pt_all}[other] > 0.5:     # Sprach-Sperre: die andere Sprache ignorieren
            return self._drop(info, "gesperrt", uid, "nur " + ("Thai" if self.lock == "th" else "Englisch") + " aktiv")
        if self.paused:
            return self._drop(info, "pausiert", uid)

        min_lp = FOLDED_TH_LOGPROB if (lang == "th" and folded) else MIN_LOGPROB[lang]
        if text and lp < min_lp:
            info["drop"] = "unsicher"
            text = ""
        if text:
            if lang == "th":
                text = re.sub(r"(?:ห้า\s*){3,}", "555", text)   # gesprochenes 555 = Lachen
            sq = squash_repeats(text)
            if sq != text:
                info["squashed"] = True
                text = sq
            hall = looks_hallucinated(text, audio.size / SR, segs)
            if hall == "wiederholung" and info.get("squashed"):
                hall = None                             # Schleife schon gekürzt, Rest ist echter Text
            if hall:
                info["drop"] = f"halluzination ({hall})"
                text = ""
        low = text.lower().strip(" .!?")
        if text and (low in JUNK or (low in JUNK_IF_SHORT and (rms or 1) < 0.01 and audio.size / SR < 1.5)):
            info["drop"] = "floskel"
            text = ""
        if not text:
            return self._drop(info, info.get("drop", "nichts erkannt"), uid)
        # Thai mit Claude: Hypothese des allgemeinen Modells als zweite Lesart mitschicken
        alts = []
        if LLM["on"] and lang == "th" and self.m_th is not None and lp < -0.25 and llm_available():
            try:
                a = stt(audio, "th", model=self.m)[0]
                if a and a != text:
                    alts.append(a)
            except Exception as e:
                log({"alt": "fehler", "err": repr(e)[:200]})
        info["alts"] = alts
        info["times"] = times
        log(info)
        return self.deliver(uid, lang, text, lp, time.time() - t0, speak=speak, t_end=t_end,
                            speaker=who["name"] if who else None, alts=alts,
                            role=role if role in ("me", "other") else None)

    def _guess_lang(self, probs):
        p = dict(probs)
        pe = p.get("en", 0.0)
        pt = p.get("th", 0.0) + (sum(p.get(k, 0.0) for k in ASIAN_AS_TH) if self.lock != "en" else 0.0)
        return self.lock if self.lock in ("en", "th") else ("th" if pt > pe else "en")

    def prerecognize(self, uid, version, audio):
        """Vorab-Erkennung nach kurzer Pause: Sprache + Text wie process() sie berechnen würde.
        Wird bei unveränderter Äußerung (nur Stille angehängt) wiederverwendet. Englisch mit
        Satzzeichen am Ende beendet die Äußerung sofort (Thai nicht: ครับ/นะ enden auch Teilsätze)."""
        t = time.time()
        a, _ = normalize(audio)
        _, _, probs = self.m_det.detect_language(audio=a, language_detection_segments=2)
        lang = self._guess_lang(probs)
        res = self._stt(a, lang)
        PRE[uid] = {"version": version, "probs": probs, "stt": {(lang, None, False): res}}
        if len(PRE) > 20:
            PRE.pop(next(iter(PRE)))
        early = (FAST["endpoint"] and lang == "en" and len(res[0].split()) >= 2
                 and re.search(r"[.?!]['\"”]?\s*$", res[0]) is not None and res[1] > -0.6)
        if early:
            EARLY_END[uid] = version
        log({"pre": {"id": uid, "v": version, "lang": lang, "s": round(time.time() - t, 2), "early": early}})

    def partial(self, uid, audio):
        """Vorläufiger Text während des Sprechens (kleines Modell, nur zur Anzeige)."""
        a, _ = normalize(audio)
        _, _, probs = self.m_det.detect_language(audio=a, language_detection_segments=1)
        lang = self._guess_lang(probs)
        text = self._stt(a, lang, model=self.m_det, quick=True)[0]
        if text:
            emit("partial", id=uid, text=text, lang=lang)

    def deliver(self, uid, lang, text, lp=0.0, stt_s=0.0, speak=True, speaker=None, alts=(), t_end=None,
                source="mic", replaces=None, role=None):
        """Übersetzen, Blase melden, vorlesen (asynchron). Gemeinsam für Mikrofon, Schnellsätze und
        Korrekturen."""
        t1 = time.time()
        base = dict(id=uid, lang=lang, text=text, stt=round(stt_s, 2), lp=round(lp, 3), speaker=speaker,
                    source=source)
        if replaces:
            base["replaces"] = replaces
        if alts:
            base["alts"] = list(alts)[:3]
        if role:
            base["role"] = role
        self.texts[uid] = (lang, text)
        if len(self.texts) > 200:
            self.texts.pop(next(iter(self.texts)))
        if not self.translate_dir.get(lang, True):
            # diese Sprache bleibt wie sie ist: nur anzeigen, nicht übersetzen, nicht vorlesen
            emit("utt", to=lang, out=text, tr=0.0, translated=False, provider="none",
                 text_latin=thai_latin(text) if lang == "th" else None, **base)
            emit("listening")
            return lang, text, text
        dst = TARGET[lang]
        meta = {}
        try:
            out = translate(text, lang, dst, history=tuple(self.history), alts=alts, polite=self.polite, meta=meta)
            net_state("translate", True)
        except Exception as e:
            if "offline" in str(e):
                net_state("translate", False)
            emit("dropped", reason="übersetzung fehlgeschlagen", id=uid)
            emit("error", msg=f"Übersetzung fehlgeschlagen: {e}")
            emit("listening")
            return None
        if dst == "th":
            out = fix_thai(out, self.polite)
        self.last = (out, dst, uid)
        self.history.append((lang, text, out))
        tr_s = time.time() - t1
        log({"id": uid, "out": out, "provider": meta.get("provider"), "cached": meta.get("cached", False),
             "tr_s": round(tr_s, 2)})
        if t_end:
            base["ready_s"] = round(time.time() - t_end, 2)    # Äußerungsende -> Übersetzung fertig
        emit("utt", to=dst, out=out, tr=round(tr_s, 2), translated=True, provider=meta.get("provider"),
             text_latin=thai_latin(text) if lang == "th" else None,
             out_latin=thai_latin(out) if dst == "th" else None,
             num_warn=True if numbers_differ(text, out) else None, **base)
        if speak:
            self.speaker.add(out, dst, uid, t_end=t_end)
        emit("listening")
        return lang, text, out

    def say_phrase(self, text, lang):
        """Schnellsatz aus der App: übersetzen und vorlesen wie eine Äußerung."""
        text = (text or "").strip()
        if text and lang in TARGET:
            uid = new_id()
            emit("thinking", id=uid)
            self.deliver(uid, lang, text, lp=0.0, source="phrase")

    def retranslate(self, uid, text, lang):
        """Korrigierter Text aus der App: neu übersetzen und vorlesen; ersetzt die alte Blase."""
        text = (text or "").strip()
        if not text:
            return
        lang = lang if lang in TARGET else (self.texts.get(uid, ("en",))[0])
        new = new_id()
        emit("thinking", id=new)
        self.deliver(new, lang, text, lp=0.0, source="edit", replaces=uid)


def record_one(mic="0", timeout=20.0):
    """Ein gesprochener Satz vom Mikrofon (für das Anlegen von Stimmprofilen)."""
    ff = subprocess.Popen([FFMPEG, "-hide_banner", "-loglevel", "error", "-f", "avfoundation",
                           "-i", f":{mic}", "-af", "highpass=f=80,volume=6dB,alimiter=limit=0.95",
                           "-ar", str(SR), "-ac", "1", "-f", "s16le", "-"], stdout=subprocess.PIPE)
    vad, N = StreamVAD(), StreamVAD.N
    fdur, buf, voiced, silence, speech, pre = N / SR, [], False, 0.0, 0.0, []
    t_end = time.time() + timeout
    try:
        while time.time() < t_end:
            b = ff.stdout.read(N * 2)
            if len(b) < N * 2:
                return None
            f = np.frombuffer(b, dtype=np.int16).astype(np.float32) / 32768
            prob = vad(f)
            if not voiced:
                pre = (pre + [f])[-12:]
                if prob > 0.5:
                    voiced, buf = True, pre[:]
                    emit("hearing")
                continue
            buf.append(f)
            if prob > 0.3: silence = 0.0; speech += fdur
            else: silence += fdur
            if silence >= 1.0:
                return np.concatenate(buf) if speech >= 0.5 else None
        return np.concatenate(buf) if buf else None
    finally:
        ff.terminate()


def profile_cli(a):
    import profiles
    if a.profiles:
        emit("profiles", profiles=[profiles.public(p) for p in profiles.list_profiles()])
    elif a.delete_profile:
        emit("profile_deleted", name=a.delete_profile, ok=profiles.delete_profile(a.delete_profile))
    elif a.vocab is not None:
        p = profiles.set_vocab(a.vocab[0], re.split(r"[,\n]", a.vocab[1]))
        emit("profile_saved", profile=profiles.public(p))
    elif a.enroll:
        emit("loading", msg="Lade Modelle für das Stimmprofil …")
        spk = profiles.SpeakerID()
        # nur die nötigen Modelle: medium (+ Thai-Modell), kein large-v3-turbo
        eng = Engine("small" if a.model == "small" else "medium", a.polite, "auto", a.tts, a.device)

        def stt(audio, lang):
            pk = float(np.max(np.abs(audio))) if audio.size else 0.0
            if 0 < pk < 0.5: audio = audio * (0.5 / pk)
            return eng._stt(audio, lang)[0]
        profiles.enroll(a.enroll, a.enroll_lang, lambda: record_one(a.mic), stt, emit, spk)


def apply_control(eng, d):
    """Eine Steuerzeile aus der App anwenden (siehe docs/PROTOKOLL.md). Gibt eine Aufgabe zurück,
    die außerhalb des Lese-Threads laufen soll (Übersetzen dauert), oder None."""
    global SILENCE_END
    if "tr_en" in d: eng.translate_dir["en"] = bool(d["tr_en"])
    if "tr_th" in d: eng.translate_dir["th"] = bool(d["tr_th"])
    if d.get("lang") in ("auto", "en", "th"): eng.lock = d["lang"]
    if d.get("polite") in ("krub", "ka"): eng.polite = d["polite"]
    if "speak" in d:
        eng.mute = not d["speak"]
        if eng.mute:
            eng.stop_speaking()
    if "paused" in d: eng.paused = bool(d["paused"])
    if "listen" in d and MIC is not None:
        if d["listen"]:
            return MIC.start                   # öffnet ffmpeg – nicht im Lese-Thread blockieren
        MIC.stop()
    if isinstance(d.get("rate"), (int, float)): eng.rate = int(max(-50, min(50, d["rate"])))
    if isinstance(d.get("volume"), (int, float)): eng.volume = float(max(0.2, min(2.0, d["volume"])))
    if isinstance(d.get("silence"), (int, float)): SILENCE_END = float(max(0.4, min(2.0, d["silence"])))
    if d.get("sensitivity") in SENSITIVITY:
        VAD["start"], VAD["keep"] = SENSITIVITY[d["sensitivity"]]
    for k in ("en", "th"):
        if f"voice_{k}" in d:
            v = d[f"voice_{k}"]
            eng.voices[k] = v if v in VOICES[k] else None
    if "glossary" in d:
        load_glossary(str(d["glossary"]))
    if d.get("style") in STYLES:
        LLM["style"] = d["style"]
    if "llm" in d:
        LLM["on"] = bool(d["llm"])
        LLM["client"] = None               # Schlüssel evtl. neu gespeichert -> neu einlesen
    if "earcons" in d: eng.earcons = bool(d["earcons"])
    if "fast_endpoint" in d: FAST["endpoint"] = bool(d["fast_endpoint"])
    if "two_person" in d:
        eng.two_person = bool(d["two_person"])
        eng.reload_profiles()
    if d.get("reload_profiles"):
        eng.reload_profiles()
    if "partial" in d: FAST["partial"] = bool(d["partial"])
    if isinstance(d.get("tts_race"), (int, float)):
        global TTS_RACE
        TTS_RACE = float(max(0.0, min(5.0, d["tts_race"])))
    if d.get("stop_speaking"):
        eng.stop_speaking()
    if isinstance(d.get("say"), dict):
        s = d["say"]
        return lambda: eng.say_phrase(s.get("text", ""), s.get("lang", "en"))
    if isinstance(d.get("retranslate"), dict):
        r = d["retranslate"]
        return lambda: eng.retranslate(str(r.get("id", "")), r.get("text", ""), r.get("lang", ""))
    return None


def control_loop(eng, jobs=None):
    """Einstellungen live aus der App (JSON-Zeilen auf stdin), ohne Neustart. Aufgaben (Schnellsatz,
    Korrektur) laufen in der Arbeits-Warteschlange, damit sie nicht parallel zur Erkennung übersetzen."""
    def run():
        for line in sys.stdin:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if not isinstance(d, dict):
                continue
            try:
                job = apply_control(eng, d)
            except Exception as e:
                log({"control": "fehler", "err": repr(e)[:200]})
                continue
            log({"control": {k: (v if k not in ("say", "retranslate") or LOG_TEXT else "…") for k, v in d.items()}})
            if job:
                if jobs is not None:
                    jobs.put(("job", job))
                else:
                    threading.Thread(target=job, daemon=True).start()
    threading.Thread(target=run, daemon=True).start()


class StreamVAD:
    """Silero-VAD Frame für Frame (512 Samples), Zustand bleibt erhalten.
    Erkennt Sprache unabhängig von der Lautstärke – auch Flüstern/leises Sprechen."""
    N, CTX = 512, 64

    def __init__(self):
        from faster_whisper.vad import get_vad_model
        self.sess = get_vad_model().session
        self.reset()

    def reset(self):
        self.h = np.zeros((1, 1, 128), dtype="float32")
        self.c = np.zeros((1, 1, 128), dtype="float32")
        self.ctx = np.zeros(self.CTX, dtype="float32")

    def __call__(self, frame):
        x = np.concatenate([self.ctx, frame]).astype("float32")[None, :]
        self.ctx = frame[-self.CTX:]
        out, self.h, self.c = self.sess.run(None, {"input": x, "h": self.h, "c": self.c})
        return float(out.reshape(-1)[0])


def quietest_cut(buf, look_back_s=4.0, fdur=StreamVAD.N / SR):
    """Index des leisesten Frames in den letzten look_back_s Sekunden (dort wird ein zu langer
    Abschnitt geteilt, statt mitten im Wort)."""
    n = len(buf)
    lo = max(1, n - int(look_back_s / fdur))
    if lo >= n:
        return n
    energies = [float(np.mean(f ** 2)) for f in buf[lo:n]]
    return lo + int(np.argmin(energies)) + 1


METER = False
PRE_AT = 0.35                   # s Pause bis zur Vorab-Erkennung
PARTIAL_EVERY = 2.0             # s Sprache zwischen zwei Teiltexten
FAST = {"pre": True, "endpoint": True, "partial": False}
EARLY_END = {}                  # uid -> version: Satz ist laut Vorab-Erkennung fertig
PRE = {}                        # uid -> Ergebnis der Vorab-Erkennung


def segmenter(read, utts, sess=0, on_end=None):
    """Mikrofon-Thread: liest laufend, segmentiert per VAD und reiht fertige Äußerungen ein.
    Verworfen wird nur, was während der eigenen Sprachausgabe (+ Nachhall) ankommt.
    Mit --barge-in (Kopfhörer) wird nichts verworfen; Sprechen unterbricht die Ausgabe."""
    N = StreamVAD.N
    vad = StreamVAD()
    BARGE_FRAMES = 6                # ~190 ms durchgehend Sprache unterbricht die Ausgabe
    fdur = N / SR
    buf, voiced, silence, speech, pre, peak_rms = [], False, 0.0, 0.0, [], 0.0
    was_gated, onset, t_cap, t_begin, dbg = False, 0, 0.0, 0.0, []
    meter_n, meter_peak = 0, 0.0
    t_voice = 0.0                   # Aufnahmezeit des letzten Sprach-Frames (für die Latenzmessung)
    uid, version, pre_sent, partial_at = None, 0, False, 0.0

    def put(frames, reason, sp):
        if sp >= MIN_UTT:
            utts.put((np.concatenate(frames), round(peak_rms, 4), time.time(), reason, sess, t_voice or t_cap,
                      uid, version))
            report_queue()
        else:
            log({"drop": "zu kurz", "speech": round(sp, 2), "rms": round(peak_rms, 4)})
            emit("dropped", reason="zu kurz")
            emit("listening")

    def finish(reason):
        nonlocal buf, pre, voiced
        voiced = False
        HEARING.clear()
        log({"segment": {"cut": reason, "start": round(t_begin % 1000, 2), "end": round(t_cap % 1000, 2),
                         "lag_s": round(time.time() - t_cap, 2), "speech": round(speech, 2)}})
        put(buf, reason, speech)
        buf, pre = [], []

    try:
        while True:
            f, t_cap = read()
            if f.size < N:
                break
            if not BARGE_IN and PLAYER.gated(t_cap):
                if voiced:              # Ausgabe beginnt mitten in einer Äußerung: Sauberes behalten
                    finish("gate")
                pre, was_gated = [], True
                continue
            if was_gated:               # eigene Stimme ist vorbei: VAD frisch starten
                vad.reset()
                was_gated = False
            prob = vad(f)
            rms = float(np.sqrt(np.mean(f ** 2)))
            if METER:                   # Pegelanzeige ~7x/s: dBFS -60..0 -> 0..1
                meter_n += 1
                meter_peak = max(meter_peak, rms)
                if meter_n >= 4:
                    db = 20 * np.log10(max(meter_peak, 1e-6))
                    emit("level", rms=round(float(min(1.0, max(0.0, (db + 60) / 60))), 2), voice=voiced)
                    meter_n, meter_peak = 0, 0.0
            if DEBUG:
                dbg = (dbg + [prob])[-31:]
                if len(dbg) == 31:
                    log({"vad_dbg": round(max(dbg), 2), "t": round(t_cap % 1000, 2),
                         "lag": round(time.time() - t_cap, 2)}); dbg = []
            if BARGE_IN and PLAYER.playing():
                onset = onset + 1 if prob > VAD["start"] else 0
                if onset >= BARGE_FRAMES:
                    hit = PLAYER.stop(tail=False)
                    _QSTATE["speaker"] and _QSTATE["speaker"].flush()
                    if hit:
                        log({"barge_in": True})
                        emit("barge_in")
            if not voiced:
                pre = (pre + [f])[-12:]                     # ~380 ms Vorlauf
                if prob > VAD["start"]:
                    voiced, buf, silence, speech, peak_rms = True, pre[:], 0.0, fdur, rms
                    t_voice = t_cap
                    t_begin = t_cap
                    uid, version, pre_sent, partial_at = new_id(), 0, False, 0.0
                    HEARING.set()
                    emit("hearing", id=uid)
                continue
            buf.append(f)
            peak_rms = max(peak_rms, rms)
            if prob > VAD["keep"]:
                silence = 0.0; speech += fdur
                t_voice = t_cap
                if pre_sent:            # weitergesprochen: Vorab-Erkennung gilt nicht mehr
                    version, pre_sent = version + 1, False
            else:
                silence += fdur
            if silence >= SILENCE_END - (min(0.2, SILENCE_END - 0.4) if speech < 1.2 else 0.0):
                finish("vad")      # sehr kurze Äußerung („ja“): Satzende bis 0.2 s früher
            elif silence > 0 and EARLY_END.get(uid) == version:
                finish("früh")          # Vorab-Erkennung: Satz ist eindeutig zu Ende
            elif (FAST["pre"] and not pre_sent and silence >= PRE_AT and SILENCE_END > PRE_AT + 0.1
                  and speech >= MIN_UTT and utts.qsize() == 0):
                # Vorab-Erkennung: nach kurzer Pause schon erkennen; ist der Satz bei SILENCE_END
                # wirklich zu Ende, wird das Ergebnis wiederverwendet
                pre_sent = True
                utts.put(("pre", uid, version, np.concatenate(buf)))
            elif (FAST["partial"] and silence == 0 and utts.qsize() == 0
                  and len(buf) * fdur - partial_at >= PARTIAL_EVERY):
                partial_at = len(buf) * fdur
                utts.put(("partial", uid, np.concatenate(buf)))
            elif len(buf) * fdur >= MAX_UTT:
                # zu lang: an der leisesten Stelle der letzten Sekunden teilen, Rest weiter sammeln
                cut = quietest_cut(buf)
                head, tail = buf[:cut], buf[cut:]
                log({"segment": {"cut": "max", "len_s": round(len(head) * fdur, 2), "rest_s": round(len(tail) * fdur, 2)}})
                put(head, "max", len(head) * fdur)
                buf, speech = tail, len(tail) * fdur
                uid, version, pre_sent, partial_at = new_id(), 0, False, 0.0
                emit("hearing", id=uid)
    finally:
        HEARING.clear()
        if on_end:
            on_end()
        else:
            utts.put(None)              # Ende: Arbeits-Thread beendet sich


def mic_filter(denoise=False):
    """Vorverstärkung + optional Rauschunterdrückung (afftdn) vor der VAD."""
    af = "highpass=f=80,"
    if denoise:
        af += "afftdn=nr=12:nf=-40,"
    return af + "volume=6dB,alimiter=limit=0.95"


DENOISE = False


def list_mics():
    """Audio-Eingänge von AVFoundation (ffmpeg) als [{index, name}]."""
    r = subprocess.run([FFMPEG, "-hide_banner", "-f", "avfoundation", "-list_devices", "true", "-i", ""],
                       capture_output=True, text=True, timeout=10)
    mics, audio = [], False
    for line in (r.stderr or "").splitlines():
        if "audio devices" in line.lower():
            audio = True
            continue
        if "video devices" in line.lower():
            audio = False
            continue
        m = re.search(r"\[(\d+)\]\s+(.+)$", line)
        if audio and m:
            mics.append({"index": m.group(1), "name": m.group(2).strip()})
    return mics


class Mic:
    """Mikrofon-Sitzung, unabhängig von den geladenen Modellen: listen an/aus öffnet bzw. schließt
    nur ffmpeg, Leser und Segmentierer. Der Arbeits-Thread und die Modelle bleiben bestehen."""

    def __init__(self, eng, mic, jobs, idle=False):
        self.eng, self.mic, self.jobs, self.idle = eng, mic, jobs, idle
        self.ff, self.sess, self.on = None, 0, False
        self.lock = threading.Lock()

    def start(self):
        with self.lock:
            if self.on:
                emit("mic", on=True)
                return True
            self.sess += 1
            sess = self.sess
            # DOLMETSCHER_MIC_FILE: Audiodatei in Echtzeit statt Mikrofon (Ende-zu-Ende-Test)
            loop = ["-stream_loop", "-1"] if os.environ.get("DOLMETSCHER_MIC_LOOP") else []
            src = ([*loop, "-re", "-i", os.environ["DOLMETSCHER_MIC_FILE"]] if os.environ.get("DOLMETSCHER_MIC_FILE")
                   else ["-f", "avfoundation", "-i", f":{self.mic}"])
            # leichte Vorverstärkung im ffmpeg, damit leise Stimmen mehr Pegel haben
            ff = subprocess.Popen([FFMPEG, "-hide_banner", "-loglevel", "error", *src, "-af", mic_filter(DENOISE),
                                   "-ar", str(SR), "-ac", "1", "-f", "s16le", "-"], stdout=subprocess.PIPE)
            self.ff = ff
        N = StreamVAD.N
        first = ff.stdout.read(N * 2)
        if not first or sess != self.sess:
            if sess == self.sess:
                emit("error", msg="Mikrofon liefert keine Daten (Mikrofon-Zugriff erlaubt?)")
                self._kill(ff)
                emit("mic", on=False)
                if not self.idle:
                    self.jobs.put(None)
            return False
        frames = queue.Queue()

        def reader():
            """Nur Lesen (kein Rechnen), damit die ffmpeg-Pipe nie vollläuft. Jeder Block bekommt
            seine Aufnahmezeit aus der Sample-Zählung; blockiert das Lesen, sind wir live."""
            n, anchor, b = 0, time.time(), b""
            try:
                while sess == self.sess:
                    t = time.time()
                    b = ff.stdout.read(N * 2)
                    now = time.time()
                    if len(b) < N * 2:
                        break
                    n += N
                    if now - t > N / SR / 2 or anchor + n / SR > now:
                        anchor = now - n / SR          # live bzw. nie in der Zukunft
                    frames.put((b, anchor + n / SR))
            finally:
                frames.put((b"", time.time()))

        def read():
            b, t = frames.get()
            return np.frombuffer(b, dtype=np.int16).astype(np.float32) / 32768, t

        def ended():
            """Segmentierer ist fertig: gewollter Stopp (andere Sitzung) oder Ende der Quelle."""
            if sess == self.sess:              # Quelle endete von selbst (Datei zu Ende, Gerät weg)
                with self.lock:
                    self.on = False
                self._kill(ff)
                emit("mic", on=False)
                if not self.idle:
                    self.jobs.put(None)        # ohne --idle: wie bisher beenden

        with self.lock:
            self.on = True
        threading.Thread(target=reader, name="mic-read", daemon=True).start()
        threading.Thread(target=segmenter, args=(read, self.jobs, sess, ended), name="mic", daemon=True).start()
        emit("mic", on=True)
        emit("listening")
        return True

    @staticmethod
    def _kill(ff):
        if ff and ff.poll() is None:
            ff.terminate()
            try:
                ff.wait(2)
            except subprocess.TimeoutExpired:
                ff.kill()

    def stop(self):
        """Mikrofon zu (Stopp-Knopf). Laufende/wartende Ausgaben brechen ab, Äußerungen dieser
        Sitzung, die noch in der Warteschlange stehen, werden verworfen."""
        with self.lock:
            self.sess += 1
            ff, self.ff, self.on = self.ff, None, False
        self._kill(ff)
        HEARING.clear()
        self.eng.stop_speaking()
        emit("mic", on=False)

    def current(self, item):
        """Gehört eine Äußerung zur laufenden Sitzung? (Alte nach Stopp verwerfen.)"""
        return len(item) < 5 or item[4] == self.sess


MIC = None


def work_loop(eng, utts, speak):
    """Arbeitet die Warteschlange ab: Äußerungen (audio, rms, t_end, reason) und App-Aufgaben
    ("job", fn). Ein Fehler in einem Satz beendet die Engine nicht."""
    while True:
        item = utts.get()
        if item is None:
            break
        if isinstance(item[0], str) and item[0] in ("pre", "partial"):
            if utts.qsize() == 0 or item[0] == "pre":   # Teiltext nur, wenn nichts anderes wartet
                try:
                    if item[0] == "pre":
                        eng.prerecognize(item[1], item[2], item[3])
                    else:
                        eng.partial(item[1], item[2])
                except Exception as e:
                    log({item[0]: "fehler", "err": repr(e)[:200]})
            continue
        if isinstance(item[0], str) and item[0] == "job":   # Schnellsatz/Korrektur aus der App
            try:
                item[1]()
            except Exception as e:
                log({"job": "fehler", "err": repr(e)[:200]})
            continue
        report_queue()
        if MIC is not None and not MIC.current(item):
            continue                            # Äußerung aus einer gestoppten Sitzung
        audio, rms, t_end, reason = item[:4]
        t_speech_end = item[5] if len(item) > 5 else None
        given_uid = item[6] if len(item) > 6 else None
        version = item[7] if len(item) > 7 else None
        t = time.time()
        uid = given_uid or new_id()
        try:
            eng.process(audio, speak=speak, rms=rms, uid=uid, t_end=t_speech_end, version=version)
        except Exception as e:                  # ein kaputter Satz darf die Engine nicht beenden
            log({"process": "fehler", "id": uid, "err": repr(e)[:300]})
            emit("dropped", reason="fehler", id=uid)
            emit("listening")
        log({"pipeline": {"queued_s": round(t - t_end, 2), "process_s": round(time.time() - t, 2),
                          "backlog": utts.qsize(), "tts_pending": eng.speaker.pending(), "cut": reason}})


def shutdown(*_):
    sp = _QSTATE.get("speaker")
    if sp:
        sp.flush()
    PLAYER.stop()                       # laufende Ausgabe (afplay/say/ffmpeg) sofort stumm
    if MIC is not None:
        Mic._kill(MIC.ff)
    sys.exit(0)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="medium", help="small | medium | best (medium + large-v3-turbo für Englisch)")
    ap.add_argument("--device", choices=["auto", "mps", "cpu"], default="auto")
    ap.add_argument("--mic", default="0")
    ap.add_argument("--list-mics", action="store_true", help="Mikrofone als JSON ausgeben")
    ap.add_argument("--polite", choices=["krub", "ka"], default="krub")
    ap.add_argument("--file", nargs="*")
    ap.add_argument("--mute", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--lang", choices=["auto", "en", "th"], default="auto")
    ap.add_argument("--tts", choices=["edge", "say"], default="edge")
    ap.add_argument("--no-en", action="store_true", help="Englisch nicht übersetzen (nur anzeigen)")
    ap.add_argument("--no-th", action="store_true", help="Thai nicht übersetzen (nur anzeigen)")
    ap.add_argument("--profiles", action="store_true", help="Stimmprofile auflisten (JSON)")
    ap.add_argument("--enroll", metavar="NAME", help="Stimmprofil anlegen: 8 Sätze vorlesen")
    ap.add_argument("--enroll-lang", choices=["en", "th"], default="en")
    ap.add_argument("--delete-profile", metavar="NAME")
    ap.add_argument("--vocab", nargs=2, metavar=("NAME", "WÖRTER"), help="eigene Wörter, kommagetrennt")
    ap.add_argument("--barge-in", action="store_true",
                    help="Sprechen unterbricht die Ausgabe (nur mit Kopfhörer!)")
    ap.add_argument("--log-text", action=argparse.BooleanOptionalAction, default=False,
                    help="erkannte/übersetzte Texte ins Log schreiben (Standard: nein)")
    ap.add_argument("--rate", type=int, default=0, help="Sprechtempo in %% (-50..50)")
    ap.add_argument("--volume", type=float, default=1.0, help="Lautstärke 0.2..2.0")
    ap.add_argument("--silence", type=float, default=SILENCE_END, help="s Stille bis Satzende (0.4..2.0)")
    ap.add_argument("--sensitivity", choices=list(SENSITIVITY), default="normal")
    ap.add_argument("--denoise", action="store_true", help="Rauschunterdrückung (afftdn)")
    ap.add_argument("--voice-en", default=None)
    ap.add_argument("--voice-th", default=None)
    ap.add_argument("--llm", action="store_true", help="Übersetzung mit Claude (API-Schlüssel nötig)")
    ap.add_argument("--llm-model", default=LLM["model"])
    ap.add_argument("--style", choices=list(STYLES), default="casual",
                    help="Ton der Claude-Übersetzung: casual (Partner) | neutral | polite (Service)")
    ap.add_argument("--earcons", action="store_true", help="Signalton statt gesprochener Bestätigung")
    ap.add_argument("--meter", action="store_true", help="Pegel-Ereignisse senden")
    ap.add_argument("--no-two-person", action="store_true", help="Zwei-Personen-Modus aus (Englisch = ich, andere Stimme = Thai)")
    ap.add_argument("--no-fast-endpoint", action="store_true", help="kein schnelles Satzende (nur Englisch)")
    ap.add_argument("--no-pre", action="store_true", help="keine Vorab-Erkennung")
    ap.add_argument("--partial", action=argparse.BooleanOptionalAction, default=False,
                    help="Teiltext während des Sprechens (Standard: aus)")
    ap.add_argument("--tts-race", type=float, default=TTS_RACE,
                    help="s bis die vorbereitete macOS-Stimme einspringt (0 = aus)")
    ap.add_argument("--idle", action="store_true",
                    help="Modelle laden, Mikrofon erst mit {\"listen\": true} auf stdin öffnen")
    a = ap.parse_args()
    JSON, BARGE_IN, LOG_TEXT, METER, DENOISE = a.json, a.barge_in, a.log_text, a.meter, a.denoise
    if a.list_mics:
        JSON = True
        emit("mics", mics=list_mics())
        sys.exit(0)
    SILENCE_END = max(0.4, min(2.0, a.silence))
    TTS_RACE = max(0.0, min(5.0, a.tts_race))
    FAST.update(pre=not a.no_pre, endpoint=not a.no_fast_endpoint, partial=a.partial)
    VAD["start"], VAD["keep"] = SENSITIVITY[a.sensitivity]
    LLM["on"], LLM["model"], LLM["style"] = a.llm, a.llm_model, a.style
    load_glossary()
    load_pronounce()
    threading.Thread(target=warm_translate, daemon=True).start()
    threading.Thread(target=thai_latin, args=("สวัสดี",), daemon=True).start()   # Umschrift vorwärmen
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    if a.profiles or a.enroll or a.delete_profile or a.vocab is not None:
        profile_cli(a)
        sys.exit(0)
    if a.tts == "edge" and not a.mute:
        tts_warmup()                            # parallel zum Laden des Modells
    eng = Engine(a.model, a.polite, a.lang, a.tts, a.device)
    apply_control(eng, {"rate": a.rate, "volume": a.volume, "voice_en": a.voice_en, "voice_th": a.voice_th})
    eng.mute = a.mute
    eng.earcons = a.earcons
    if a.no_two_person:
        eng.two_person = False
    if a.no_en: eng.translate_dir["en"] = False
    if a.no_th: eng.translate_dir["th"] = False
    jobs = queue.Queue()
    if a.json and not a.file:
        control_loop(eng, jobs)
    if a.file:
        for f in a.file:   # per ffmpeg dekodieren (unabhängig von der PyAV-Version)
            raw = subprocess.run([FFMPEG, "-loglevel", "error", "-i", f, "-ar", str(SR), "-ac", "1",
                                  "-f", "s16le", "-"], capture_output=True).stdout
            eng.process(np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768, speak=not a.mute)
        eng.speaker.wait_idle()                 # Ausgaben zu Ende spielen, dann beenden
    else:
        MIC = Mic(eng, a.mic, jobs, idle=a.idle)
        _QSTATE["stt_q"] = jobs
        if a.idle:
            emit("mic", on=False)
        else:
            jobs.put(("job", MIC.start))
        # Arbeiten im Haupt-Thread (Signale für Stopp kommen hier an); Äußerungen der Reihe nach.
        # Stummschaltung über eng.mute (live änderbar), Vorlesen im Speaker-Thread.
        work_loop(eng, jobs, speak=True)
