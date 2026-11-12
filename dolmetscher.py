#!/usr/bin/env python3
"""Hands-free EN <-> TH Dolmetscher.

Hört dauerhaft aufs Mikrofon, erkennt selbst ob Englisch oder Thai gesprochen
wird, übersetzt und spricht die Übersetzung sofort laut aus.

Start:  python3 dolmetscher.py   (benötigt: pip install faster-whisper, ffmpeg)
Optionen: --model small|medium|base  --mic 0  --polite krub|ka  --json
          --file test.wav (ohne Mikrofon)  --mute
"""
import argparse, json, os, re, shutil, signal, subprocess, sys, time, urllib.parse, urllib.request
import numpy as np
from faster_whisper import WhisperModel

SR = 16000
FRAME = 480                       # 30 ms
SILENCE_END = 0.7                 # s Stille = Satzende
MIN_UTT = 0.4                     # s, kürzer wird ignoriert
MAX_UTT = 20.0
VOICE = {"th": "Kanya", "en": "Samantha"}
TARGET = {"en": "th", "th": "en"}
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
    if v not in out:
        loc = "th_TH" if lang == "th" else "en_US"
        for line in out.splitlines():
            if loc in line:
                return line.split(loc)[0].strip()
    return v


class Engine:
    def __init__(self, model, polite):
        t = time.time()
        emit("loading", msg=f"Lade Whisper-Modell '{model}' …")
        self.m = WhisperModel(model, device="cpu", compute_type="int8")
        self.voice = {k: pick_voice(k) for k in VOICE}
        self.polite = polite
        emit("ready", msg=f"bereit ({time.time()-t:.1f}s), Stimmen: {self.voice}")

    def process(self, audio, speak=True):
        t0 = time.time()
        _, _, probs = self.m.detect_language(audio=audio)
        p = dict(probs)
        lang = "th" if p.get("th", 0) > p.get("en", 0) else "en"
        segs, _ = self.m.transcribe(audio, language=lang, beam_size=1, vad_filter=True,
                                    condition_on_previous_text=False)
        text = " ".join(s.text.strip() for s in segs).strip()
        if not text or text.lower().strip(" .!") in JUNK:
            emit("listening")
            return None
        t1 = time.time()
        dst = TARGET[lang]
        try:
            out = translate(text, lang, dst)
        except Exception as e:
            emit("error", msg=f"Übersetzung fehlgeschlagen: {e}")
            return None
        if dst == "th":
            out = fix_thai(out, self.polite)
        emit("utt", lang=lang, to=dst, text=text, out=out, stt=t1 - t0, tr=time.time() - t1)
        if speak:
            emit("speaking")
            subprocess.run([SAY, "-v", self.voice[dst], "-r", "185", out])
        emit("listening")
        return lang, text, out


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
    FF = subprocess.Popen([FFMPEG, "-hide_banner", "-loglevel", "error", "-f", "avfoundation",
                           "-i", f":{mic}", "-ar", str(SR), "-ac", "1", "-f", "s16le", "-"],
                          stdout=subprocess.PIPE)

    def read(n):
        b = FF.stdout.read(n * 2)
        return np.frombuffer(b, dtype=np.int16).astype(np.float32) / 32768

    emit("calibrating", msg="Kalibriere Mikrofon, bitte 1 Sekunde still …")
    levels = []
    for _ in range(33):
        f = read(FRAME)
        if f.size == 0:
            emit("error", msg="Mikrofon liefert keine Daten (Mikrofon-Zugriff erlaubt?)")
            return
        levels.append(np.sqrt(np.mean(f ** 2)))
    thresh = max(float(np.median(levels)) * 3.0, 0.008)
    emit("listening")

    buf, voiced, silence, pre = [], False, 0.0, []
    while True:
        f = read(FRAME)
        if f.size == 0:
            break
        rms = float(np.sqrt(np.mean(f ** 2)))
        loud = rms > thresh
        if not voiced:
            pre = (pre + [f])[-10:]
            if loud:
                voiced, buf, silence = True, pre[:], 0.0
                emit("hearing")
            continue
        buf.append(f)
        silence = 0.0 if loud else silence + FRAME / SR
        dur = len(buf) * FRAME / SR
        if silence >= SILENCE_END or dur >= MAX_UTT:
            voiced = False
            if dur - silence >= MIN_UTT:
                emit("thinking")
                eng.process(np.concatenate(buf), speak=speak)
                drain(FF); time.sleep(0.3); drain(FF)   # eigene Stimme verwerfen
            else:
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
    a = ap.parse_args()
    JSON = a.json
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    eng = Engine(a.model, a.polite)
    if a.file:
        from faster_whisper.audio import decode_audio
        for f in a.file:
            eng.process(decode_audio(f, sampling_rate=SR), speak=not a.mute)
    else:
        mic_loop(eng, a.mic, speak=not a.mute)
