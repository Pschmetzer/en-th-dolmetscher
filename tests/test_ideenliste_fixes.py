"""Fehlerliste .claude/IDEEN.md („Zuerst angehen“): Regressionstests für Engine-Fixes."""
import json
import queue
import threading
import time

import pytest

import dolmetscher as d


# ---- Nr. 18: Ausgabe entkoppelt (blockierte Pipe hängt weder emit noch Stopp) -----------------------

class _BlockingOut:
    def __init__(self):
        self.release = threading.Event()
        self.lines = []

    def write(self, s):
        self.release.wait(5)
        self.lines.append(s)

    def flush(self):
        pass


@pytest.fixture
def writer(monkeypatch):
    out = _BlockingOut()
    q = queue.Queue(maxsize=5)
    monkeypatch.setattr(d, "JSON", True)
    monkeypatch.setattr(d, "STOP", threading.Event())
    monkeypatch.setitem(d._OUT, "q", q)
    monkeypatch.setitem(d._OUT, "dropped", 0)
    t = threading.Thread(target=d._writer_run, args=(q, out), daemon=True)
    t.start()
    yield out, q
    out.release.set()
    q.put(None)
    t.join(2)


def test_emit_never_blocks_on_stuck_pipe(writer):
    out, q = writer
    done = threading.Event()

    def work():
        for i in range(50):                     # mehr als die Warteschlange fasst
            d.emit("level", rms=0.1, n=i)
        d.emit("error", code="x", msg="wichtig")
        done.set()
    threading.Thread(target=work, daemon=True).start()
    assert done.wait(1.0), "emit blockiert bei voller Pipe"
    assert d._OUT["dropped"] > 0
    t = time.monotonic()
    assert d.flush_output(timeout=0.2) is False         # Stopp wartet höchstens die Frist
    assert time.monotonic() - t < 0.6
    out.release.set()
    assert d.flush_output(timeout=2) is True
    events = [json.loads(x)["event"] for x in out.lines]
    assert events[-1] == "error"                        # wichtige Meldung überlebt das Verwerfen


def test_shutdown_outside_loop_does_not_hang(writer, monkeypatch):
    monkeypatch.setitem(d._LOOP, "on", False)
    monkeypatch.setattr(d, "cleanup", lambda: None)
    d.emit("ready")
    t = time.monotonic()
    with pytest.raises(SystemExit):
        d.shutdown()
    assert time.monotonic() - t < 2.5
    assert d.STOP.is_set()


def test_writer_broken_pipe_sets_stop(monkeypatch):
    class Broken:
        def write(self, s):
            raise BrokenPipeError

        def flush(self):
            pass
    monkeypatch.setattr(d, "STOP", threading.Event())
    q = queue.Queue()
    t = threading.Thread(target=d._writer_run, args=(q, Broken()), daemon=True)
    t.start()
    q.put('{"event": "x"}')
    q.put(None)
    t.join(2)
    assert d.STOP.is_set() and not t.is_alive()


# ---- Nr. 10: Verlaufsfehler bricht emit nicht ab ------------------------------------------------------

def test_history_error_does_not_break_emit(monkeypatch, capsys):
    import history_store

    class Bad:
        def utt(self, kw):
            raise OSError(28, "No space left on device")
    monkeypatch.setattr(history_store, "RECORDER", Bad())
    monkeypatch.setattr(d, "JSON", True)
    d._emit("utt", text="a", out="b", lang="en", to="th", stt=0.1, tr=0.1)
    assert json.loads(capsys.readouterr().out)["event"] == "utt"


# ---- Nr. 11: stdout UTF-8 -----------------------------------------------------------------------------

def test_utf8_stdio_reconfigures(monkeypatch):
    import io
    buf = io.BytesIO()
    w = io.TextIOWrapper(buf, encoding="ascii")
    monkeypatch.setattr(d.sys, "stdout", w)
    monkeypatch.setattr(d.sys, "stderr", io.TextIOWrapper(io.BytesIO(), encoding="ascii"))
    d._utf8_stdio()
    print("สวัสดี", file=w, flush=True)
    assert buf.getvalue().decode("utf-8").strip() == "สวัสดี"


# ---- Nr. 1, 2, 14: Sprachbefehle ohne Fehlalarm --------------------------------------------------------

@pytest.mark.parametrize("cmd, expected", [
    ("don't translate English this time", "en_off"),   # Nr. 1: "time" ist kein Thai
    ("English off this time", "en_off"),
    ("English only this time", "english"),
    ("type only", "thai"),                               # Verhörer allein gilt weiter
    ("Ty only", "thai"),
    ("Thai off", "th_off"),
    ("unmute", "resume"),                                # Nr. 2: nicht "pause"
    ("un-mute", "resume"),
    ("un mute please", "resume"),
    ("unpause", "resume"),
    ("mute", "pause"),
    ("the bus is on time", None),                        # Nr. 14: Alltagssätze sind keine Befehle
    ("see you next time", None),
    ("what type is it", None),
])
def test_command_false_alarms(cmd, expected):
    assert d.parse_command(cmd) == expected
