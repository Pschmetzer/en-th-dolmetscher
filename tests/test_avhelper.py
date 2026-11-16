"""avhelper.py (PyAV statt ffmpeg) und die Anbindung in der Engine."""
import io
import json
import subprocess
import sys

import numpy as np
import pytest

import avhelper
import dolmetscher as d

av = pytest.importorskip("av")


def _mp3(path, seconds=1.0, rate=24000):
    buf = io.BytesIO()
    o = av.open(buf, "w", format="mp3")
    st = o.add_stream("libmp3lame" if "libmp3lame" in av.codecs_available else "mp3", rate=rate, layout="mono")
    x = (0.3 * np.sin(2 * np.pi * 440 * np.arange(int(rate * seconds)) / rate)).astype(np.float32)[None, :]
    fr = av.AudioFrame.from_ndarray(x, format="fltp", layout="mono")
    fr.sample_rate = rate
    for p in [*st.encode(fr), *st.encode(None)]:
        o.mux(p)
    o.close()
    path.write_bytes(buf.getvalue())
    return path


def test_parse_af():
    assert avhelper.parse_af("highpass=f=80,afftdn=nr=12:nf=-40,volume=6dB,alimiter=limit=0.95") == [
        ("highpass", "f=80"), ("afftdn", "nr=12:nf=-40"), ("volume", "6dB"), ("alimiter", "limit=0.95")]
    assert avhelper.parse_af("") == [] and avhelper.parse_af(" anull ") == [("anull", "")]


def test_parse_devices_nur_audio():
    lines = ["AVFoundation video devices:\n", "[0] FaceTime HD Camera\n", "AVFoundation audio devices:\n",
             "[0] MacBook Pro-Mikrofon\n", "[1] AirPods Pro\n"]
    assert avhelper.parse_devices(lines) == [{"index": "0", "name": "MacBook Pro-Mikrofon"},
                                             {"index": "1", "name": "AirPods Pro"}]


def test_capture_datei_liefert_s16le_16k(tmp_path):
    """Wie `ffmpeg -i x.mp3 -af … -ar 16000 -ac 1 -f s16le -`: 1 s Ton -> ~16000 Samples, nicht still."""
    f = _mp3(tmp_path / "t.mp3")
    out = subprocess.run([sys.executable, "-B", avhelper.__file__, "capture", "--file", str(f),
                          "--af", d.mic_filter(True), "--rate", "16000"], capture_output=True, timeout=60)
    assert out.returncode == 0, out.stderr
    a = np.frombuffer(out.stdout, dtype=np.int16)
    assert abs(a.size - 16000) < 1200 and np.abs(a).max() > 3000


def test_capture_fehler_lesbar_fuer_explain(tmp_path):
    out = subprocess.run([sys.executable, "-B", avhelper.__file__, "capture", "--file", str(tmp_path / "nope.wav")],
                         capture_output=True, text=True, timeout=60)
    assert out.returncode != 0 and out.stdout == ""
    assert d.Mic._explain([out.stderr])[0] == "mic_unavailable"


def test_play_ohne_daten_endet_still():
    out = subprocess.run([sys.executable, "-B", avhelper.__file__, "play"], input=b"", capture_output=True,
                         timeout=60)
    assert out.returncode == 0, out.stderr


def test_decode_file_pyav(tmp_path, monkeypatch):
    monkeypatch.setattr(d, "FFMPEG", None)
    a = d.decode_file(str(_mp3(tmp_path / "t.mp3", seconds=0.5)))
    assert a.dtype == np.float32 and abs(a.size - 8000) < 1200


def test_befehle_ohne_und_mit_ffmpeg(monkeypatch):
    monkeypatch.setattr(d, "FFMPEG", None)
    c = d.capture_cmd(dev="2", af="volume=6dB")
    assert c[:4] == [sys.executable, "-B", d.AVHELPER, "capture"] and "--device" in c and "2" in c
    c = d.capture_cmd(path="/x.wav", loop=True, realtime=True)
    assert c[c.index("--file") + 1] == "/x.wav" and "--loop" in c and "--realtime" in c
    assert d.pipe_player(0.5) == [sys.executable, "-B", d.AVHELPER, "play", "--volume", "0.50"]
    monkeypatch.setattr(d, "FFMPEG", "/opt/ff/ffmpeg")
    c = d.capture_cmd(dev="0", af="volume=6dB")
    assert c[0] == "/opt/ff/ffmpeg" and c[c.index("-i") + 1] == ":0" and "avfoundation" in c
    c = d.capture_cmd(path="/x.wav", loop=True, realtime=True)
    assert c[c.index("-stream_loop") + 1] == "-1" and "-re" in c


def test_ffmpeg_nur_wenn_ausdruecklich_gesetzt(monkeypatch):
    """Kein stilles Zurückfallen auf Homebrew: ohne DOLMETSCHER_FFMPEG nutzt die Engine PyAV."""
    src = open(d.__file__, encoding="utf-8").read()
    assert 'FFMPEG = os.environ.get("DOLMETSCHER_FFMPEG") or None' in src
    assert "/opt/homebrew/bin/ffmpeg" not in src and "_find_tool" not in src


def test_list_mics_ueber_helper(monkeypatch):
    monkeypatch.setattr(d, "FFMPEG", None)
    calls = []

    def run(cmd, **kw):
        calls.append(cmd)
        return subprocess.CompletedProcess(cmd, 0, stdout=json.dumps({"mics": [{"index": "0", "name": "M"}]}) + "\n",
                                           stderr="")
    monkeypatch.setattr(d.subprocess, "run", run)
    assert d.list_mics() == [{"index": "0", "name": "M"}]
    assert calls[0][-1] == "list"
    monkeypatch.setattr(d.subprocess, "run", lambda cmd, **kw: subprocess.CompletedProcess(cmd, 1, "", "kaputt"))
    with pytest.raises(RuntimeError):
        d.list_mics()


class _P:
    def __init__(self):
        self.stdin = io.BytesIO()
        self.alive = True

    def poll(self):
        return None if self.alive else 0


def test_player_vorgewaermter_prozess(monkeypatch):
    """Zweiter Satz nimmt den bereitstehenden Prozess (kein neuer Start im zeitkritischen Weg)."""
    monkeypatch.setattr(d, "FFMPEG", None)
    monkeypatch.setattr(d, "NULL_AUDIO", False)
    made = []

    def popen(cmd, **kw):
        made.append(cmd)
        return _P()
    monkeypatch.setattr(d.subprocess, "Popen", popen)
    started = []
    def thread(target, args=(), **kw):
        return type("T", (), {"start": lambda s: started.append((target, args))})()
    monkeypatch.setattr(d.threading, "Thread", thread)
    pl = d.Player()
    cmd = d.pipe_player(1.0)
    p1 = pl.start(cmd, stdin=subprocess.PIPE)
    assert len(made) == 1 and started and started[0][0] == pl._spawn_standby
    pl._spawn_standby(cmd)                       # Hintergrund-Start nachholen
    assert len(made) == 2
    sb = pl._standby[1]
    p2 = pl.start(cmd, stdin=subprocess.PIPE)
    assert p2 is sb and p2 is not p1 and len(made) == 2 and p2 in pl.procs
    # andere Lautstärke: bereitstehender Prozess passt nicht -> verworfen (EOF), neu gestartet
    pl._spawn_standby(cmd)
    old = pl._standby[1]
    p3 = pl.start(d.pipe_player(0.5), stdin=subprocess.PIPE)
    assert p3 is not old and old.stdin.closed
    # afplay/say: nie vorgewärmt
    assert not d.Player._warmable(["/usr/bin/afplay", "x"], {})


def test_download_progress_zaehlt_bytes_im_cache(tmp_path, monkeypatch):
    ev = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: ev.append((e, kw)))
    monkeypatch.setattr(d, "_hub_blobs", lambda repo: str(tmp_path / repo.replace("/", "--")))
    monkeypatch.setattr(d, "_hub_total_mb", lambda repo, rev: 3)
    monkeypatch.setattr(d.DownloadProgress, "INTERVAL", 0.02)
    blobs = tmp_path / "Systran--faster-whisper-small"
    with d.DownloadProgress("small", "abc"):
        blobs.mkdir()
        (blobs / "x.incomplete").write_bytes(b"\0" * 1_500_000)
        d.time.sleep(0.2)
        (blobs / "x.incomplete").rename(blobs / "x")
        (blobs / "y").write_bytes(b"\0" * 1_500_000)
        d.time.sleep(0.2)
    prog = [kw for e, kw in ev if e == "download_progress"]
    assert prog[0]["done_mb"] == 0 and all(p["model"] == "small" for p in prog)
    assert any(p["done_mb"] == 2 and p["total_mb"] == 3 for p in prog)
    assert prog[-1] == {"model": "small", "done_mb": 3, "total_mb": 3, "final": True}
    assert len(prog) == len({(p["done_mb"], p["total_mb"], p["final"]) for p in prog})   # nur bei Änderung


def test_download_progress_im_wm_nur_beim_herunterladen(monkeypatch):
    calls, entered = [], []

    class WM:
        def __init__(self, model, local_files_only=False, **kw):
            calls.append(local_files_only)
            if local_files_only:
                raise FileNotFoundError("local_files_only: not in cache")

    class DP:
        def __init__(self, model, rev):
            entered.append(model)

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False
    monkeypatch.setattr(d, "WhisperModel", WM)
    monkeypatch.setattr(d, "DownloadProgress", DP)
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    monkeypatch.setattr(d, "_DOWNLOAD_SAID", {})
    d._wm("small")
    assert calls == [True, False] and entered == ["small"]
