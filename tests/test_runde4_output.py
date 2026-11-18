"""Runde 4, Nr. 24/357: Ausgabegerät wählbar. Alle eigenen Wiedergabewege (Neural-Stimme über die Pipe,
gepuffertes mp3, macOS-Stimme, Signalton) gehen mit gewähltem Gerät über avhelper.py."""
import pathlib
import subprocess
import sys
import time
import types

import pytest

import avhelper
import dolmetscher as d

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = (ROOT / "docs" / "PROTOKOLL.md").read_text(encoding="utf-8")


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    return events


@pytest.fixture(autouse=True)
def _output_reset(monkeypatch):
    monkeypatch.setattr(d, "OUTPUT", {"device": ""})
    monkeypatch.setattr(d, "FFMPEG", None)


LIST = ["CoreAudio devices:\n", "[0]           MacBook Pro-Mikrofon, BuiltInMicrophoneDevice\n",
        "[1]       MacBook Pro-Lautsprecher, BuiltInSpeakerDevice\n", "[2] AirPods Pro, 00-11-22-33:output\n",
        "[3] Ohne UID\n"]


def test_parse_outputs_name_uid_index():
    outs = avhelper.parse_outputs(LIST)
    assert outs[1] == {"index": "1", "name": "MacBook Pro-Lautsprecher", "uid": "BuiltInSpeakerDevice"}
    assert outs[2] == {"index": "2", "name": "AirPods Pro", "uid": "00-11-22-33:output"}
    assert outs[3] == {"index": "3", "name": "Ohne UID", "uid": ""}
    assert len(outs) == 4                      # Kopfzeile ignoriert


def test_match_output_uid_vor_name_dann_index():
    outs = avhelper.parse_outputs(LIST)
    assert avhelper.match_output(outs, "00-11-22-33:output") == "2"
    assert avhelper.match_output(outs, "airpods pro") == "2"
    assert avhelper.match_output(outs, "1") == "1"
    assert avhelper.match_output(outs, "9") is None
    assert avhelper.match_output(outs, "Gibt es nicht") is None
    assert avhelper.match_output(outs, "") is None and avhelper.match_output(outs, "default") is None


def test_ohne_geraet_bleibt_afplay_und_pipe_ohne_device():
    assert d.file_play_cmd("/tmp/x.aiff", 1.0)[0].endswith("afplay")
    assert "--device" not in d.pipe_player(1.0)


def test_mit_geraet_alle_wege_ueber_avhelper():
    d.OUTPUT["device"] = "BuiltInSpeakerDevice"
    cmd = d.file_play_cmd("/tmp/x.aiff", 0.5)
    assert cmd[2] == d.AVHELPER and cmd[3] == "play"
    assert cmd[cmd.index("--file") + 1] == "/tmp/x.aiff" and cmd[cmd.index("--device") + 1] == "BuiltInSpeakerDevice"
    assert cmd[cmd.index("--volume") + 1] == "0.50"
    pc = d.pipe_player(1.0)
    assert pc[pc.index("--device") + 1] == "BuiltInSpeakerDevice" and "--file" not in pc


def test_mit_ffmpeg_bleibt_afplay(monkeypatch, ev):
    monkeypatch.setattr(d, "FFMPEG", "/opt/ffmpeg")
    d.set_output_device("AirPods", check=False)
    assert d.file_play_cmd("/tmp/x.aiff", 1.0)[0].endswith("afplay")
    assert ev and ev[-1][1]["code"] == "output_unsupported"


def test_keine_afplay_aufrufe_mehr_im_code():
    """Alle Abspielstellen gehen über file_play_cmd (sonst ignorierten sie das Ausgabegerät)."""
    src = (ROOT / "dolmetscher.py").read_text(encoding="utf-8")
    assert src.count('"/usr/bin/afplay"') == 1   # nur die Konstante AFPLAY


def test_null_audio_datei_kommando_wird_sleep(monkeypatch):
    """Tests ohne Ton: `play --file` darf nicht zu /bin/cat werden (hinge an stdin)."""
    seen = []

    class P:
        def __init__(self, cmd, **kw):
            seen.append((cmd, kw))

    monkeypatch.setattr(d, "NULL_AUDIO", True)
    monkeypatch.setattr(d.subprocess, "Popen", P)
    pl = d.Player()
    d.OUTPUT["device"] = "X"
    pl.start(d.file_play_cmd("/tmp/x.aiff", 1.0))
    assert seen[-1][0] == ["/bin/sleep", "1"]
    assert seen[-1][1]["stdin"] is subprocess.DEVNULL   # nie das Steuer-stdin der Engine erben


def test_steuerfeld_output_device(monkeypatch, ev):
    monkeypatch.setattr(d, "list_outputs", lambda: avhelper.parse_outputs(LIST))
    eng = types.SimpleNamespace(translate_dir={"en": True, "th": True}, lock="auto", polite="krub", mute=False,
                                paused=False, rate=0, volume=1.0, voices={"en": None, "th": None}, earcons=False)
    d.apply_control(eng, {"output_device": "AirPods Pro"})
    assert d.OUTPUT["device"] == "AirPods Pro"
    d.apply_control(eng, {"output_device": "Weg"})
    for _ in range(100):                       # Prüfung läuft im Hintergrund
        if any(k.get("code") == "output_not_found" for _, k in ev):
            break
        time.sleep(0.02)
    assert any(k.get("code") == "output_not_found" for _, k in ev)
    d.apply_control(eng, {"output_device": "default"})
    assert d.OUTPUT["device"] == ""
    d.apply_control(eng, {"output_device": 5})
    assert ev[-1][1]["code"] == "output_invalid" and d.OUTPUT["device"] == ""


def test_avhelper_play_file_fehler_lesbar(tmp_path):
    pytest.importorskip("av", reason="PyAV nicht installiert (steht in requirements-dev.txt)")
    out = subprocess.run([sys.executable, "-B", avhelper.__file__, "play", "--file", str(tmp_path / "nope.aiff")],
                         capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL)
    assert out.returncode != 0 and "cannot open file" in out.stderr


def test_avhelper_import_aendert_sigpipe_nicht():
    import signal
    import importlib
    before = signal.getsignal(signal.SIGPIPE)
    importlib.reload(avhelper)
    assert signal.getsignal(signal.SIGPIPE) == before


def test_protokoll_dokumentiert():
    for key in ("`--output-device", "`output_device`", "`output_not_found`", "`output_invalid`",
                "`output_unsupported`", "`outputs`"):
        assert key in DOCS, key
