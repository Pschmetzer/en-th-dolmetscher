#!/usr/bin/env python3
"""Erzeugt Test-Audio (WAV, 16 kHz mono) für bench/cases.json mit macOS `say` + ffmpeg.

    python bench/make_audio.py                  # sauber  -> bench/audio/clean/<id>.wav
    python bench/make_audio.py --noise          # rosa Rauschen, SNR 15 dB -> bench/audio/noise/
    python bench/make_audio.py --quiet          # -20 dB  -> bench/audio/quiet/
    python bench/make_audio.py --noise --quiet --rate 160 --cases th01,th27
"""
import argparse, json, os, shutil, subprocess, sys, tempfile, wave
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
SR = 16000
VOICES = {"th": "Kanya", "en": "Samantha"}
FFMPEG = os.environ.get("DOLMETSCHER_FFMPEG") or shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"


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
    a = ap.parse_args()

    if sys.platform != "darwin" or not shutil.which("say"):
        sys.exit("make_audio.py braucht macOS (`say`).")
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
