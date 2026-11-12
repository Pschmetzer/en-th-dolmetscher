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
TARGET = {"en": "th", "th": "en"}
# Weckwort nur am Satzanfang: "Translator, pause" / "Hey translator resume"
WAKE = re.compile(r"^\W*(?:hey|hi|ok|okay)?\W*translat(?:or|er)\b\W*(.*)$", re.I | re.S)
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


class Engine:
    def __init__(self, model, polite, lock="auto", tts="edge"):
        self.lock, self.tts = lock, tts
        t = time.time()
        emit("loading", msg=f"Lade Whisper-Modell '{model}' …")
        self.m = WhisperModel(model, device="cpu", compute_type="int8")
        self.voice = {k: pick_voice(k) for k in VOICE}
        self.polite = polite
        self.paused, self.rate, self.volume = False, 0, 1.0     # rate in %, volume 0.2..2
        self.last, self.awake_until, self.mute = None, 0.0, False
        emit("ready", msg=f"bereit ({time.time()-t:.1f}s), Stimmen: {self.voice}")

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
        c = cmd.lower()
        has = lambda *w: any(re.search(rf"\b{x}\b", c) for x in w)
        state = {}
        if not c.strip():
            self.awake_until = time.time() + 6
            reply = "Yes?"
        elif has("pause", "stop", "sleep", "be quiet", "mute"):
            self.paused = True; reply = "Paused. Say translator, resume."
        elif has("resume", "continue", "start", "wake up", "go on", "unpause"):
            self.paused = False; reply = "I'm listening."
        elif has("repeat", "again", "say that"):
            if self.last:
                emit("command", text=cmd, reply="", paused=self.paused, lang=self.lock,
                     polite=self.polite, rate=self.rate, volume=round(self.volume, 2))
                emit("speaking"); self.speak(self.last[0], self.last[1])
                return None
            reply = "Nothing to repeat yet."
        elif has("slower", "slow down"):
            self.rate = max(self.rate - 15, -50); reply = "Slower."
        elif has("faster", "speed up", "quicker"):
            self.rate = min(self.rate + 15, 50); reply = "Faster."
        elif has("louder", "volume up"):
            self.volume = min(self.volume * 1.4, 2.0); reply = "Louder."
        elif has("quieter", "softer", "volume down"):
            self.volume = max(self.volume / 1.4, 0.2); reply = "Quieter."
        elif has("thai", "tie", "ty", "tai", "thigh") and has("only", "mode"):
            self.lock = "th"; reply = "Okay, Thai only."
        elif has("english") and has("only", "mode"):
            self.lock = "en"; reply = "Okay, English only."
        elif has("auto", "automatic", "both"):
            self.lock = "auto"; reply = "Okay, automatic."
        elif has("female", "woman", "women", "girl", "lady"):
            self.polite = "ka"; reply = "Okay, female voice."
        elif has("male", "man", "men", "guy"):
            self.polite = "krub"; reply = "Okay, male voice."
        elif has("clear", "delete", "reset"):
            state["clear"] = True; reply = "Cleared."
        elif has("help", "commands", "what can you do"):
            reply = ("Say translator, then: pause, resume, repeat, slower, faster, louder, quieter, "
                     "Thai only, English only, auto, male or female voice, clear.")
        else:
            reply = "Sorry?"
        if c.strip():
            self.awake_until = 0.0
        emit("command", text=cmd, reply=reply, paused=self.paused, lang=self.lock,
             polite=self.polite, rate=self.rate, volume=round(self.volume, 2), **state)
        log({"command": cmd, "reply": reply})
        return reply

    def _stt(self, audio, lang):
        segs, _ = self.m.transcribe(audio, language=lang, beam_size=1, vad_filter=True, vad_parameters={"threshold": 0.25},
                                    condition_on_previous_text=False)
        segs = list(segs)
        text = " ".join(s.text.strip() for s in segs).strip()
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
            text, lp = self._stt(audio, lang)
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
        m = WAKE.match(en_text)
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
        dst = TARGET[lang]
        try:
            out = translate(text, lang, dst)
        except Exception as e:
            emit("error", msg=f"Übersetzung fehlgeschlagen: {e}")
            return None
        if dst == "th":
            out = fix_thai(out, self.polite)
        self.last = (out, dst)
        emit("utt", lang=lang, to=dst, text=text, out=out, stt=t1 - t0, tr=time.time() - t1)
        if speak:
            emit("speaking")
            self.speak(out, dst)
        emit("listening")
        return lang, text, out


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
    ap.add_argument("--model", default="small")
    ap.add_argument("--mic", default="0")
    ap.add_argument("--polite", choices=["krub", "ka"], default="krub")
    ap.add_argument("--file", nargs="*")
    ap.add_argument("--mute", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--lang", choices=["auto", "en", "th"], default="auto")
    ap.add_argument("--tts", choices=["edge", "say"], default="edge")
    a = ap.parse_args()
    JSON = a.json
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    eng = Engine(a.model, a.polite, a.lang, a.tts)
    eng.mute = a.mute
    if a.file:
        for f in a.file:   # per ffmpeg dekodieren (unabhängig von der PyAV-Version)
            raw = subprocess.run([FFMPEG, "-loglevel", "error", "-i", f, "-ar", str(SR), "-ac", "1",
                                  "-f", "s16le", "-"], capture_output=True).stdout
            eng.process(np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768, speak=not a.mute)
    else:
        mic_loop(eng, a.mic, speak=not a.mute)
