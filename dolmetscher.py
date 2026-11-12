#!/usr/bin/env python3
"""Hands-free EN <-> TH Dolmetscher.

Hört dauerhaft aufs Mikrofon, erkennt selbst ob Englisch oder Thai gesprochen
wird, übersetzt und spricht die Übersetzung sofort laut aus.

Start:  python3 dolmetscher.py   (benötigt: pip install faster-whisper, ffmpeg)
Optionen: --model small|medium|base  --mic 0  --polite krub|ka  --json
          --lang auto|en|th  --tts edge|say  --file test.wav  --mute
"""
import argparse, json, os, re, shutil, signal, subprocess, sys, time, urllib.parse, urllib.request
import numpy as np
from faster_whisper import WhisperModel

SR = 16000
SILENCE_END = 0.8                 # s Stille = Satzende
MIN_UTT = 0.4                     # s, kürzer wird ignoriert
MAX_UTT = 20.0
MIN_LANG_P = 0.35                 # en+th zusammen mindestens so wahrscheinlich, sonst ignorieren
MIN_LOGPROB = -1.0                # unsicherere Transkripte gelten als Rauschen/Halluzination
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
JUNK = {"thank you for watching", "thanks for watching", "subtitles by", "ขอบคุณที่รับชม"}
FFMPEG = os.environ.get("DOLMETSCHER_FFMPEG") or shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
SAY = "/usr/bin/say"

C = {"en": "\033[1;34m", "th": "\033[1;33m", "dim": "\033[2m", "off": "\033[0m"}
JSON = False
FF = None


def emit(event, **kw):
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


LOGFILE = os.path.expanduser("~/Library/Logs/Dolmetscher/engine.log")


def log(d):
    try:
        os.makedirs(os.path.dirname(LOGFILE), exist_ok=True)
        with open(LOGFILE, "a") as f:
            f.write(time.strftime("%H:%M:%S ") + json.dumps(d, ensure_ascii=False) + "\n")
    except OSError:
        pass


def translate(text, src, dst):
    try:
        u = ("https://translate.googleapis.com/translate_a/single?client=gtx&dt=t"
             f"&sl={src}&tl={dst}&q={urllib.parse.quote(text)}")
        with urllib.request.urlopen(u, timeout=6) as r:
            return "".join(p[0] for p in json.load(r)[0])
    except Exception:
        u = f"https://api.mymemory.translated.net/get?q={urllib.parse.quote(text)}&langpair={src}|{dst}"
        with urllib.request.urlopen(u, timeout=8) as r:
            return json.load(r)["responseData"]["translatedText"]


def fix_thai(s, polite):
    """Google liefert 'ครับ/ค่ะ' – eine Form wählen, sonst liest Kanya den Schrägstrich vor."""
    male = polite == "krub"
    s = re.sub(r"ครับ\s*/\s*ค่ะ|ค่ะ\s*/\s*ครับ", "ครับ" if male else "ค่ะ", s)
    s = re.sub(r"ครับ\s*/\s*คะ|คะ\s*/\s*ครับ", "ครับ" if male else "คะ", s)
    s = re.sub(r"ผม\s*/\s*ฉัน|ฉัน\s*/\s*ผม", "ผม" if male else "ฉัน", s)
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


def load_model(model, device):
    """Apple-GPU (MPS) wenn möglich – ca. 2-4x schneller –, sonst CPU."""
    if device in ("auto", "mps"):
        try:
            m = WhisperModel(model, device="mps", compute_type="float16")
            m.detect_language(audio=np.zeros(SR, dtype=np.float32))     # Probelauf
            list(m.transcribe(np.zeros(SR, dtype=np.float32), language="en")[0])
            return m, "mps"
        except Exception as e:
            log({"mps": "nicht verfügbar", "err": repr(e)[:200]})
            if device == "mps":
                raise
    return WhisperModel(model, device="cpu", compute_type="int8"), "cpu"


class Engine:
    def __init__(self, model, polite, lock="auto", tts="edge", device="auto"):
        self.lock, self.tts = lock, tts
        t = time.time()
        emit("loading", msg=f"Lade Whisper-Modell '{model}' …")
        # "best": medium für Erkennung + Thai, large-v3-turbo für Englisch (Akzente)
        self.m, self.device = load_model("medium" if model == "best" else model, device)
        self.m_en = load_model("large-v3-turbo", self.device)[0] if model == "best" else None
        # Thai: auf Thai trainiertes Whisper (biodatlab, MIT) – ~30 % weniger Fehler bei leiser/entfernter Sprache
        self.m_th = None
        if model != "small":
            try:
                emit("loading", msg="Lade Thai-Modell …")
                self.m_th = load_model(THAI_MODEL, self.device)[0]
            except Exception as e:
                log({"thai_model": "nicht geladen", "err": repr(e)[:200]})
        self.beam = 5 if self.device == "mps" else 1
        log({"model": model, "device": self.device, "load_s": round(time.time() - t, 1)})
        self.voice = {k: pick_voice(k) for k in VOICE}
        self.polite = polite
        self.paused, self.rate, self.volume = False, 0, 1.0     # rate in %, volume 0.2..2
        self.translate_dir = {"en": True, "th": True}          # Richtung einzeln abschaltbar
        self.last, self.awake_until, self.mute = None, 0.0, False
        self.spk = None
        try:                                   # Stimmprofile (optional)
            import profiles
            if profiles.list_profiles():
                self.spk = profiles.SpeakerID()
                log({"profiles": [p["name"] for p in self.spk.profiles]})
        except Exception as e:
            log({"profiles": "aus", "err": repr(e)[:200]})
        emit("ready", msg=f"bereit ({time.time()-t:.1f}s, {model} auf {self.device})", device=self.device)

    def speak(self, text, lang):
        """Natürliche Microsoft-Neural-Stimme (edge-tts), sonst macOS-Stimme."""
        import tempfile
        if self.mute:
            log({"would_say": text})
            return
        t = time.time()
        vol = ["-v", f"{self.volume:.2f}"]
        tmp = tempfile.gettempdir()
        if self.tts == "edge":
            try:
                import asyncio, edge_tts
                voice = NEURAL[lang][self.polite if lang == "th" else "en"]
                mp3 = os.path.join(tmp, "dolmetscher_tts.mp3")
                if os.path.exists(mp3):
                    os.remove(mp3)                     # nie eine alte Datei abspielen
                asyncio.run(asyncio.wait_for(
                    edge_tts.Communicate(text, voice, rate=f"{5 + self.rate:+d}%").save(mp3), timeout=6))
                if os.path.getsize(mp3) > 0:
                    log({"tts": "edge", "voice": voice, "secs": round(time.time() - t, 2)})
                    subprocess.run(["/usr/bin/afplay", *vol, mp3])
                    return
            except Exception as e:
                log({"tts": "edge-fehler", "err": repr(e)[:200]})
        aiff = os.path.join(tmp, "dolmetscher_say.aiff")
        log({"tts": "say", "voice": self.voice[lang]})
        subprocess.run([SAY, "-v", self.voice[lang], "-r", str(int(185 * (1 + self.rate / 100))),
                        "-o", aiff, text])
        subprocess.run(["/usr/bin/afplay", *vol, aiff])

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
                emit("command", text=cmd, reply="", paused=self.paused, lang=self.lock,
                     polite=self.polite, rate=self.rate, volume=round(self.volume, 2))
                emit("speaking"); self.speak(self.last[0], self.last[1])
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
        elif key == "help":
            reply = ("Say translator, then: pause, resume, repeat, slower, faster, louder, quieter, "
                     "Thai only, English only, auto, male or female voice, clear.")
        else:
            reply = "Sorry?"
        if key != "wake":
            self.awake_until = 0.0
        emit("command", text=cmd, reply=reply, paused=self.paused, lang=self.lock,
             tr_en=self.translate_dir["en"], tr_th=self.translate_dir["th"],
             polite=self.polite, rate=self.rate, volume=round(self.volume, 2), **state)
        log({"command": cmd, "key": key, "reply": reply})
        return reply

    def _stt(self, audio, lang, hotwords=None):
        mdl = (self.m_en if (lang == "en" and self.m_en) else
               self.m_th if (lang == "th" and self.m_th) else self.m)
        segs, _ = mdl.transcribe(audio, language=lang, beam_size=self.beam, hotwords=hotwords,
                                 repetition_penalty=1.1, no_repeat_ngram_size=4, max_new_tokens=160, vad_filter=True, vad_parameters={"threshold": 0.25},
                                    condition_on_previous_text=False)
        segs = list(segs)
        text = " ".join(s.text.strip() for s in segs).strip()
        if lang == "th":   # Thai-Modell setzt Leerzeichen zwischen Wörter – Thai schreibt man ohne
            text = re.sub(r"(?<=[\u0E00-\u0E7F]) (?=[\u0E00-\u0E7F])", "", text)
        lp = float(np.mean([s.avg_logprob for s in segs])) if segs else -9.0
        return text, lp

    def process(self, audio, speak=True, rms=None):
        t0 = time.time()
        peak = float(np.max(np.abs(audio))) if audio.size else 0.0
        if 0 < peak < 0.5:                       # leise Sprecher anheben
            audio = audio * (0.5 / peak)
        info = {"dur": round(audio.size / SR, 2), "rms": rms, "peak": round(peak, 3)}
        _, _, probs = self.m.detect_language(audio=audio, language_detection_segments=2)
        p = dict(probs)
        pe, pt = p.get("en", 0.0), p.get("th", 0.0)
        info.update(p_en=round(pe, 3), p_th=round(pt, 3),
                    top=[(k, round(v, 3)) for k, v in probs[:3]])
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
        if pe + pt < MIN_LANG_P:                  # weder Englisch noch Thai -> ignorieren
            info["drop"] = "andere Sprache"
            log(info)
            emit("dropped", reason="weder Englisch noch Thai")
            emit("listening")
            return None
        if self.lock in ("en", "th"):
            lang = self.lock
            text, lp = self._stt(audio, lang)
            info.update(mode="lock")
        else:
            lang = "th" if pt > pe else "en"
            text, lp = self._stt(audio, lang, hotwords=hot if who and who.get("lang") == lang else None)
            # unklar? beide Sprachen probieren und die sicherere nehmen
            if (lang == "en" and pt > 0.1) or (lang == "th" and pe > 0.1) or not text:
                other = "th" if lang == "en" else "en"
                t2, lp2 = self._stt(audio, other)
                info.update(alt=other, alt_text=t2, alt_lp=round(lp2, 3), lp=round(lp, 3))
                if t2 and (lp2 > lp or not text):
                    lang, text, lp = other, t2, lp2
        info.update(lang=lang, text=text, lp=round(lp, 3))

        # --- Sprachbefehle: "Translator, ..." (oder Folgesatz nach bloßem "Translator")
        en_text = text if lang == "en" else (self._stt(audio, "en")[0] if pe > pt else "")
        if re.match(r"^\W*(?:hey|hi|ok|okay)?\W*tr\w*nsl", en_text, re.I):
            # Befehlskandidat: einmal mit Befehls-Vokabular nachhören
            hw = self._stt(audio, "en", hotwords=HOTWORDS)[0]
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
            reply = self.command(cmd.strip(" .,!?"))
            if reply and speak:
                emit("speaking"); self.speak(reply, "en")
            emit("listening")
            return None
        other = {"en": "th", "th": "en"}.get(self.lock)
        if other and p.get(other, 0.0) > 0.5:     # Sprach-Sperre: die andere Sprache ignorieren
            info["drop"] = "gesperrt"
            log(info)
            emit("dropped", reason="nur " + ("Thai" if self.lock == "th" else "Englisch") + " aktiv")
            emit("listening")
            return None
        if self.paused:
            info["drop"] = "pausiert"
            log(info)
            emit("dropped", reason="pausiert")
            emit("listening")
            return None

        if text and lp < MIN_LOGPROB:
            info["drop"] = "unsicher"
            text = ""
        if not text or text.lower().strip(" .!?") in JUNK:
            info.setdefault("drop", "nichts erkannt")
            log(info)
            emit("dropped", reason=info["drop"])
            emit("listening")
            return None
        log(info)
        t1 = time.time()
        if not self.translate_dir.get(lang, True):
            # diese Sprache bleibt wie sie ist: nur anzeigen, nicht übersetzen, nicht vorlesen
            emit("utt", lang=lang, to=lang, text=text, out=text, stt=t1 - t0, tr=0.0, translated=False,
                 speaker=who["name"] if who else None)
            emit("listening")
            return lang, text, text
        dst = TARGET[lang]
        try:
            out = translate(text, lang, dst)
        except Exception as e:
            emit("error", msg=f"Übersetzung fehlgeschlagen: {e}")
            return None
        if dst == "th":
            out = fix_thai(out, self.polite)
        self.last = (out, dst)
        emit("utt", lang=lang, to=dst, text=text, out=out, stt=t1 - t0, tr=time.time() - t1,
             speaker=who["name"] if who else None)
        if speak:
            emit("speaking")
            self.speak(out, dst)
        emit("listening")
        return lang, text, out


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


def control_loop(eng):
    """Einstellungen live aus der App (JSON-Zeilen auf stdin), ohne Neustart."""
    import threading

    def run():
        for line in sys.stdin:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if "tr_en" in d: eng.translate_dir["en"] = bool(d["tr_en"])
            if "tr_th" in d: eng.translate_dir["th"] = bool(d["tr_th"])
            if d.get("lang") in ("auto", "en", "th"): eng.lock = d["lang"]
            if d.get("polite") in ("krub", "ka"): eng.polite = d["polite"]
            if "speak" in d: eng.mute = not d["speak"]
            if "paused" in d: eng.paused = bool(d["paused"])
            log({"control": d})
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


def drain(ff):
    """Alles verwerfen, was während der Sprachausgabe aufgenommen wurde."""
    import fcntl
    fd = ff.stdout.fileno()
    fl = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, fl | os.O_NONBLOCK)
    try:
        while os.read(fd, 65536):
            pass
    except BlockingIOError:
        pass
    fcntl.fcntl(fd, fcntl.F_SETFL, fl)


def mic_loop(eng, mic, speak):
    global FF
    # leichte Vorverstärkung im ffmpeg, damit leise Stimmen mehr Pegel haben
    FF = subprocess.Popen([FFMPEG, "-hide_banner", "-loglevel", "error", "-f", "avfoundation",
                           "-i", f":{mic}", "-af", "highpass=f=80,volume=6dB,alimiter=limit=0.95",
                           "-ar", str(SR), "-ac", "1", "-f", "s16le", "-"],
                          stdout=subprocess.PIPE)
    N = StreamVAD.N

    def read():
        b = FF.stdout.read(N * 2)
        return np.frombuffer(b, dtype=np.int16).astype(np.float32) / 32768

    vad = StreamVAD()
    if read().size == 0:
        emit("error", msg="Mikrofon liefert keine Daten (Mikrofon-Zugriff erlaubt?)")
        return
    emit("listening")

    START, KEEP = 0.5, 0.3          # Hysterese: Start bei 0.5, weiter solange > 0.3
    fdur = N / SR
    buf, voiced, silence, speech, pre, peak_rms = [], False, 0.0, 0.0, [], 0.0
    while True:
        f = read()
        if f.size < N:
            break
        prob = vad(f)
        rms = float(np.sqrt(np.mean(f ** 2)))
        if not voiced:
            pre = (pre + [f])[-12:]                     # ~380 ms Vorlauf
            if prob > START:
                voiced, buf, silence, speech, peak_rms = True, pre[:], 0.0, fdur, rms
                emit("hearing")
            continue
        buf.append(f)
        peak_rms = max(peak_rms, rms)
        if prob > KEEP:
            silence = 0.0; speech += fdur
        else:
            silence += fdur
        dur = len(buf) * fdur
        if silence >= SILENCE_END or dur >= MAX_UTT:
            voiced = False
            if speech >= MIN_UTT:
                emit("thinking")
                eng.process(np.concatenate(buf), speak=speak, rms=round(peak_rms, 4))
                drain(FF); time.sleep(0.3); drain(FF)   # eigene Stimme verwerfen
                vad.reset()
            else:
                log({"drop": "zu kurz", "speech": round(speech, 2), "rms": round(peak_rms, 4)})
                emit("dropped", reason="zu kurz")
                emit("listening")
            buf, pre = [], []


def shutdown(*_):
    if FF and FF.poll() is None:
        FF.terminate()
    sys.exit(0)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="medium", help="small | medium | best (medium + large-v3-turbo für Englisch)")
    ap.add_argument("--device", choices=["auto", "mps", "cpu"], default="auto")
    ap.add_argument("--mic", default="0")
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
    a = ap.parse_args()
    JSON = a.json
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    if a.profiles or a.enroll or a.delete_profile or a.vocab is not None:
        profile_cli(a)
        sys.exit(0)
    eng = Engine(a.model, a.polite, a.lang, a.tts, a.device)
    eng.mute = a.mute
    if a.no_en: eng.translate_dir["en"] = False
    if a.no_th: eng.translate_dir["th"] = False
    if a.json and not a.file:
        control_loop(eng)
    if a.file:
        for f in a.file:   # per ffmpeg dekodieren (unabhängig von der PyAV-Version)
            raw = subprocess.run([FFMPEG, "-loglevel", "error", "-i", f, "-ar", str(SR), "-ac", "1",
                                  "-f", "s16le", "-"], capture_output=True).stdout
            eng.process(np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768, speak=not a.mute)
    else:
        mic_loop(eng, a.mic, speak=True)          # Stummschaltung über eng.mute (live änderbar)
