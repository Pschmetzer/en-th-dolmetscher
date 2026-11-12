"""Pipeline ohne Mikrofon, Lautsprecher und Netz: Echo-Sperre, Übersetzungsfehler, Log-Schalter.

Segmentierung mit echter Sprache braucht macOS `say` und das Silero-VAD aus faster-whisper;
fehlt eins davon, wird der Test übersprungen.
"""
import io
import json
import queue
import shutil
import subprocess
import threading
import time
import urllib.error

import numpy as np
import pytest

import dolmetscher as d


@pytest.fixture(autouse=True)
def _no_real_log(monkeypatch):
    """Tests schreiben nie ins echte engine.log."""
    class Null:
        def info(self, s):
            pass
    monkeypatch.setattr(d, "_logger", lambda: Null())


def test_gate_uses_capture_time_spans():
    p = d.Player()
    t = time.time()
    p.spans = [(t - 5.0, t - 3.0)]
    assert p.gated(t - 4.0)                      # während der Ausgabe aufgenommen
    assert p.gated(t - 3.0 + d.Player.TAIL - 0.01)  # Nachhall
    assert not p.gated(t - 6.0)                  # vorher: bleibt erhalten
    assert not p.gated(t - 2.0)                  # danach: bleibt erhalten


def test_stop_kills_child_once():
    p = d.Player()
    proc = p.start(["/bin/sleep", "5"])
    th = threading.Thread(target=p.wait, args=(proc,))
    th.start()
    assert p.stop() is True
    assert p.stop() is False                     # Barge-in feuert nur einmal je Ausgabe
    th.join(2)
    assert proc.poll() is not None and not p.playing()


class _Resp(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *a):
        pass


def _fake_urlopen(google, mymemory):
    def urlopen(url, timeout=0):
        src = google if "googleapis" in url else mymemory
        if isinstance(src, Exception):
            raise src
        return _Resp(json.dumps(src).encode())
    return urlopen


def test_mymemory_quota_text_is_never_returned(monkeypatch):
    monkeypatch.setattr(d.urllib.request, "urlopen", _fake_urlopen(
        urllib.error.HTTPError("u", 429, "x", None, None),
        {"responseData": {"translatedText": "MYMEMORY WARNING: YOU USED ALL AVAILABLE FREE TRANSLATIONS"},
         "responseStatus": 429, "quotaFinished": True}))
    with pytest.raises(RuntimeError, match="MyMemory"):
        d.translate("hello", "en", "th")


def test_offline_is_reported(monkeypatch):
    monkeypatch.setattr(d.urllib.request, "urlopen", _fake_urlopen(
        urllib.error.URLError("no route"), urllib.error.URLError("no route")))
    with pytest.raises(RuntimeError, match="offline"):
        d.translate("hello", "en", "th")


def test_no_log_text_redacts(tmp_path, monkeypatch):
    seen = []

    class L:
        def info(self, s):
            seen.append(json.loads(s))
    monkeypatch.setattr(d, "_logger", lambda: L())
    monkeypatch.setattr(d, "LOG_TEXT", False)
    d.log({"text": "geheim", "out": "secret", "lang": "en"})
    assert seen == [{"text": "<6 Zeichen>", "out": "<6 Zeichen>", "lang": "en"}]


def _say(voice, text, path):
    try:
        subprocess.run(["say", "-v", voice, "-o", str(path), text], check=True, capture_output=True)
    except subprocess.CalledProcessError:
        pytest.skip(f"Stimme {voice} nicht installiert")
    raw = subprocess.run([d.FFMPEG, "-loglevel", "error", "-i", str(path), "-ar", str(d.SR), "-ac", "1",
                          "-f", "s16le", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768


@pytest.mark.skipif(not shutil.which("say") or not shutil.which(d.FFMPEG), reason="braucht macOS say + ffmpeg")
def test_segmenter_keeps_speech_and_drops_own_voice(tmp_path):
    pytest.importorskip("faster_whisper.vad")
    a = _say("Samantha", "Excuse me, where is the nearest train station?", tmp_path / "a.aiff")
    b = _say("Samantha", "Thank you very much, have a nice evening.", tmp_path / "b.aiff")
    sil = np.zeros(int(1.2 * d.SR), dtype=np.float32)
    audio = np.concatenate([sil, a, sil, b, sil, a, sil])
    N = d.StreamVAD.N
    t0 = 1_000.0
    # dritter Satz (zweites a) gilt als eigene Ausgabe
    own_start = t0 + (2 * sil.size + a.size + b.size + sil.size) / d.SR
    d.PLAYER.spans = [(own_start, own_start + a.size / d.SR)]
    frames = queue.Queue()
    for i in range(0, audio.size - N + 1, N):
        frames.put((audio[i:i + N], t0 + (i + N) / d.SR))
    frames.put((np.zeros(0, dtype=np.float32), 0.0))
    utts = queue.Queue()
    try:
        d.segmenter(frames.get, utts)
    finally:
        d.PLAYER.spans = []
    got = []
    while (x := utts.get_nowait()) is not None:
        got.append(x)
    assert len(got) == 2, [round(g[0].size / d.SR, 2) for g in got]
    for g, ref in zip(got, (a, b)):
        assert abs(g[0].size - ref.size) / d.SR < 1.5
