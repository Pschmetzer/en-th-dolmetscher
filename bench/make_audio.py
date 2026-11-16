#!/usr/bin/env python3
"""Erzeugt Test-Audio (WAV, 16 kHz mono) für bench/cases.json mit macOS `say` + ffmpeg.

    python bench/make_audio.py                  # sauber  -> bench/audio/clean/<id>.wav
    python bench/make_audio.py --noise          # rosa Rauschen, SNR 15 dB -> bench/audio/noise/
    python bench/make_audio.py --quiet          # -20 dB  -> bench/audio/quiet/
    python bench/make_audio.py --noise --quiet --rate 160 --cases th01,th27
    python bench/make_audio.py --negatives      # Negativfälle (negatives.json) -> bench/audio/negatives/
"""
import argparse, json, os, shutil, subprocess, sys, tempfile, wave
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
SR = 16000
VOICES = {"th": "Kanya", "en": "Samantha"}
# Reihenfolge: Umgebungsvariable, PATH, Homebrew (Apple Silicon, dann Intel)
FFMPEG = (os.environ.get("DOLMETSCHER_FFMPEG") or shutil.which("ffmpeg")
          or next((p for p in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg") if os.path.exists(p)), "ffmpeg"))


def variant_name(noise, quiet):
    parts = [p for p, on in (("noise", noise), ("quiet", quiet)) if on]
    return "_".join(parts) or "clean"


def read_wav(path):
    with wave.open(str(path)) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768


def write_wav(path, x):
    x = np.clip(x, -1, 1)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def pink_noise(n, seed):
    """Rosa Rauschen (1/f) per FFT, RMS = 1."""
    rng = np.random.default_rng(seed)
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.arange(spec.size); f[0] = 1
    x = np.fft.irfft(spec / np.sqrt(f), n)
    return x / (np.sqrt(np.mean(x ** 2)) + 1e-12)


def negative_signal(case):
    """Synthetische Negativfälle (Nr. 163): nichts davon darf übersetzt werden. Reproduzierbar je id."""
    rng = np.random.default_rng(sum(map(ord, case["id"])))
    dur = case.get("dur", 2.0)
    n = int(dur * SR)
    t = np.arange(n) / SR
    kind = case["kind"]
    if kind == "silence":
        x = rng.standard_normal(n) * 1e-4
    elif kind == "pink":
        x = pink_noise(n, int(rng.integers(1 << 30))) * 0.05
    elif kind == "hum":
        x = sum(0.05 / k * np.sin(2 * np.pi * 50 * k * t) for k in (1, 2, 3, 5))
    elif kind == "music":
        x = np.zeros(n)
        chords = ((261.6, 329.6, 392.0), (220.0, 261.6, 329.6), (174.6, 220.0, 261.6), (196.0, 246.9, 293.7))
        seg = n // len(chords)
        tt = t[:seg]
        env = np.minimum(1, tt * 20) * np.exp(-tt * 1.5)
        for i, ch in enumerate(chords):
            x[i * seg:(i + 1) * seg] = sum(np.sin(2 * np.pi * f * tt) for f in ch) * env * 0.08
    elif kind == "cough":
        x = rng.standard_normal(n) * 1e-4
        m = int(0.25 * SR)
        for start in (0.2, 0.7):
            a = int(start * SR)
            x[a:a + m] += rng.standard_normal(m) * np.exp(-np.linspace(0, 6, m)) * 0.3
    elif kind == "clicks":
        x = rng.standard_normal(n) * 1e-4
        for start in rng.uniform(0.1, dur - 0.1, 12):
            a = int(start * SR)
            x[a:a + 80] += rng.standard_normal(80) * np.exp(-np.linspace(0, 8, 80)) * 0.4
    else:
        raise ValueError(f"unbekannte Art: {kind}")
    return np.asarray(x, dtype=np.float32)


def say_to_array(text, voice, rate=None):
    with tempfile.TemporaryDirectory() as td:
        aiff, wav = Path(td) / "a.aiff", Path(td) / "a.wav"
        cmd = ["say", "-v", voice, "-o", str(aiff)]
        if rate:
            cmd += ["-r", str(rate)]
        subprocess.run(cmd + [text], check=True)
        subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", str(aiff),
                        "-ar", str(SR), "-ac", "1", "-c:a", "pcm_s16le", str(wav)], check=True)
        return read_wav(wav)


def synth_negative(case, out):
    x = say_to_array(case["text"], case["voice"]) if case["kind"] == "foreign" else negative_signal(case)
    write_wav(out, x)
    return x.size / SR


def synth(case, out, rate, noise, quiet, snr):
    with tempfile.TemporaryDirectory() as td:
        aiff, wav = Path(td) / "a.aiff", Path(td) / "a.wav"
        cmd = ["say", "-v", VOICES[case["lang"]], "-o", str(aiff)]
        if rate:
            cmd += ["-r", str(rate)]
        subprocess.run(cmd + [case["text"]], check=True)
        subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", "-i", str(aiff),
                        "-ar", str(SR), "-ac", "1", "-c:a", "pcm_s16le", str(wav)], check=True)
        x = read_wav(wav)
    x = np.concatenate([np.zeros(int(0.3 * SR), np.float32), x, np.zeros(int(0.4 * SR), np.float32)])
    if noise:
        speech = x[np.abs(x) > 1e-4]
        rms = np.sqrt(np.mean(speech ** 2)) if speech.size else 0.05
        seed = sum(map(ord, case["id"]))                     # reproduzierbar je Fall
        x = x + pink_noise(x.size, seed).astype(np.float32) * rms / (10 ** (snr / 20))
    if quiet:
        x = x * 10 ** (-20 / 20)
    write_wav(out, x)
    return x.size / SR


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--noise", action="store_true", help="rosa Rauschen beimischen (SNR --snr dB)")
    ap.add_argument("--snr", type=float, default=15.0)
    ap.add_argument("--quiet", action="store_true", help="Pegel um 20 dB absenken")
    ap.add_argument("--rate", type=int, default=None, help="Sprechtempo für say (Wörter/Minute)")
    ap.add_argument("--cases", default="", help="nur diese IDs, kommagetrennt")
    ap.add_argument("--out", default=None, help="Zielordner (Standard: bench/audio/<variante>)")
    ap.add_argument("--negatives", action="store_true",
                    help="Negativfälle aus negatives.json (Rauschen, Musik, Stille, Husten, Fremdsprache)")
    a = ap.parse_args()

    if sys.platform != "darwin" or not shutil.which("say"):
        sys.exit("make_audio.py braucht macOS (`say`).")
    if a.negatives:
        cases = json.loads((HERE / "negatives.json").read_text())
        out = Path(a.out) if a.out else HERE / "audio" / "negatives"
        out.mkdir(parents=True, exist_ok=True)
        for c in cases:
            dur = synth_negative(c, out / f"{c['id']}.wav")
            print(f"{c['id']}  {c['kind']:8s} {dur:5.1f} s")
        print(f"{len(cases)} Negativfälle -> {out}")
        return
    cases = json.loads((HERE / "cases.json").read_text())
    if a.cases:
        want = set(a.cases.split(","))
        cases = [c for c in cases if c["id"] in want]
    out = Path(a.out) if a.out else HERE / "audio" / variant_name(a.noise, a.quiet)
    out.mkdir(parents=True, exist_ok=True)
    for c in cases:
        dur = synth(c, out / f"{c['id']}.wav", a.rate, a.noise, a.quiet, a.snr)
        print(f"{c['id']}  {c['lang']}  {dur:5.1f} s  {c['text'][:60]}")
    print(f"{len(cases)} Dateien -> {out}")


if __name__ == "__main__":
    main()
