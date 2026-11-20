"""Runde 21 (py1) Welle 5."""
import queue
import threading
import time

import dolmetscher as d


def test_history_write_does_not_hold_emit_lock(monkeypatch):
    q = queue.Queue(maxsize=50)
    monkeypatch.setattr(d, "JSON", True)
    monkeypatch.setitem(d._OUT, "q", q)
    gate, started = threading.Event(), threading.Event()

    def slow_record(event, kw):
        started.set()
        gate.wait(3)
    monkeypatch.setattr(d, "_record", slow_record)
    t = threading.Thread(target=d.emit, args=("utt",), kwargs=dict(id="u1", text="x"), daemon=True)
    t.start()
    assert started.wait(2)
    t0 = time.monotonic()
    d.emit("level", rms=0.1)                  # darf nicht auf den langsamen Verlauf warten
    assert time.monotonic() - t0 < 1.0
    gate.set()
    t.join(3)
    events = [__import__("json").loads(x)["event"] for x in list(q.queue)]
    assert events == ["level", "utt"]


class _Conn:
    def __init__(self, fail):
        self.fail, self.sock, self.timeout, self.closed = fail, None, 1, False

    def request(self, *a, **k):
        if self.fail:
            raise ConnectionResetError("reset")

    def getresponse(self):
        class R:
            status, reason, headers, will_close = 200, "OK", {}, True

            def read(self, n=-1):
                return b'{"ok": 1}'

            def getheader(self, *_):
                return "application/json"
        return R()

    def close(self):
        self.closed = True


def test_fresh_connection_reset_is_retried_once(monkeypatch):
    ka = d.KeepAlive()
    seq = [_Conn(True), _Conn(False)]
    monkeypatch.setattr(ka, "_new", lambda host, timeout: seq.pop(0))
    assert ka.get_json("https://example.org/x", 2) == {"ok": 1}
    assert not seq


def test_fresh_connection_other_error_not_retried(monkeypatch):
    import urllib.error

    import pytest

    class Boom(_Conn):
        def request(self, *a, **k):
            raise OSError("anderer Fehler")
    ka = d.KeepAlive()
    seq = [Boom(False), _Conn(False)]
    monkeypatch.setattr(ka, "_new", lambda host, timeout: seq.pop(0))
    with pytest.raises(urllib.error.URLError):
        ka.get_json("https://example.org/x", 2)
    assert len(seq) == 1
