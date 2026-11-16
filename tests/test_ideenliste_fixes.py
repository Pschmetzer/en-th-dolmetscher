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


# ---- Nr. 3: Cache-Schlüssel, Nr. 4: Ziffernfolgen ------------------------------------------------------

def test_norm_keeps_decimal_point():
    assert d._norm("1.5") != d._norm("1 5")
    assert d._norm("It costs 1,5 baht.") == "it costs 1,5 baht"
    assert d._norm("Hello, world.") == d._norm("hello world")
    assert d._norm("ok 。 fine") == "ok fine"
    assert d._norm("geht's ? !") == "geht's?"


@pytest.mark.parametrize("text", ["0808080808", "11111111", "Call 0812121212 please", "๐๘๐๘๐๘๐๘๐๘"])
def test_squash_keeps_digit_runs(text):
    assert d.squash_repeats(text) == text


def test_squash_still_cuts_loops():
    assert d.squash_repeats("ha ha ha ha ha ha") == "ha ha ha"
    assert d.squash_repeats("สติ๊กฮ่าาาาาาา") == "สติ๊กฮ่าาา"


# ---- Nr. 6: frische Verbindung im zweiten Versuch ------------------------------------------------------

class _FakeResp:
    status, reason, headers, will_close = 200, "OK", {}, False

    def read(self):
        return b'{"ok": 1}'

    def getheader(self, k, default=None):
        return default


class _FakeConn:
    def __init__(self, dead):
        self.dead, self.sock, self.timeout, self.closed = dead, None, None, False

    def request(self, *a, **k):
        if self.dead:
            raise ConnectionResetError(54, "reset")

    def getresponse(self):
        return _FakeResp()

    def close(self):
        self.closed = True


def test_pool_second_attempt_uses_fresh_connection(monkeypatch):
    ka = d.KeepAlive()
    dead = [_FakeConn(True), _FakeConn(True)]           # nach dem Ruhezustand: beide gemerkten tot
    ka.idle["example.org"] = list(dead)
    made = []

    def new(host, timeout):
        c = _FakeConn(False)
        made.append(c)
        return c
    monkeypatch.setattr(ka, "_new", new)
    assert ka.get_json("https://example.org/x", 2) == {"ok": 1}
    assert len(made) == 1 and all(c.closed for c in dead)


# ---- Nr. 7, 8: MyMemory -------------------------------------------------------------------------------

def test_mymemory_error_has_no_text(monkeypatch):
    secret = "my secret sentence"
    monkeypatch.setattr(d, "_get_json", lambda u, t=0: {"responseData": {"translatedText": secret},
                                                       "responseStatus": 403, "responseDetails": secret})
    with pytest.raises(RuntimeError) as ei:
        d.mymemory_translate("hello", "en", "th")
    assert secret not in str(ei.value) and str(ei.value).startswith("MyMemory-Fehler 403")
    assert secret not in d._errtxt(ei.value)


def test_mymemory_unescapes_entities(monkeypatch):
    monkeypatch.setattr(d, "_get_json", lambda u, t=0: {
        "responseData": {"translatedText": "it&#39;s &quot;ok&quot; &amp; fine"}, "responseStatus": 200})
    assert d.mymemory_translate("x", "en", "th") == 'it\'s "ok" & fine'


# ---- Nr. 9: Claude-Guthaben leer ----------------------------------------------------------------------

class _ApiErr(Exception):
    def __init__(self, sc, msg):
        super().__init__(msg)
        self.status_code = sc


def test_llm_billing_pauses_long_and_reports(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda ev, **kw: events.append((ev, kw)))
    monkeypatch.setitem(d.LLM, "skip_until", 0.0)
    monkeypatch.setitem(d.LLM, "err", None)
    e = _ApiErr(400, "Your credit balance is too low to access the Anthropic API.")
    assert d._llm_backoff(e) == d.LLM_BILLING_BACKOFF
    d._llm_failed(e)
    assert d.LLM["skip_until"] - time.monotonic() > 1000
    assert events and events[0][1]["code"] == "llm_billing"
    assert "credit balance" not in d.LLM["err"]
    assert d._llm_backoff(_ApiErr(400, "messages: field required")) == 10.0


# ---- Nr. 19: Gesamtzeit je Satz -----------------------------------------------------------------------

def test_mt_chain_skips_mymemory_without_time(monkeypatch):
    called = []

    def g(*a):
        raise ValueError("x")
    monkeypatch.setattr(d, "google_translate", g)
    monkeypatch.setattr(d, "mymemory_translate", lambda *a: called.append(a) or "ok")
    with pytest.raises(ValueError):
        d._mt_chain("hello", "en", "th", {}, deadline=time.monotonic() + 0.5)
    assert not called
    assert d._mt_chain("hello", "en", "th", {}, deadline=time.monotonic() + 10) == "ok"
    assert called[-1][-1] <= 8.0                        # MyMemory bekommt höchstens die Restzeit


# ---- Nr. 5: model_offline über Fehlertypen -------------------------------------------------------------

def test_offline_error_by_type():
    import socket
    import urllib.error

    class LocalEntryNotFoundError(Exception):
        pass
    assert d.is_offline_error(LocalEntryNotFoundError("x"))
    try:
        try:
            raise socket.gaierror(8, "nodename nor servname provided")
        except OSError as inner:
            raise RuntimeError("wrapped") from inner
    except RuntimeError as e:
        assert d.is_offline_error(e)
    assert d.is_offline_error(urllib.error.URLError("x"))
    assert not d.is_offline_error(urllib.error.HTTPError("u", 404, "nf", {}, None))
    assert not d.is_offline_error(ValueError("bad model name"))


# ---- Nr. 12: ffmpeg fehlt -> sofort melden -------------------------------------------------------------

def test_check_ffmpeg_reports_missing(monkeypatch, tmp_path):
    events = []
    monkeypatch.setattr(d, "emit", lambda ev, **kw: events.append((ev, kw)))
    monkeypatch.setattr(d, "FFMPEG", str(tmp_path / "nope" / "ffmpeg"))
    assert d.check_ffmpeg() is False
    assert events == [("error", {"code": "ffmpeg_missing", "msg": events[0][1]["msg"]})]
    exe = tmp_path / "ffmpeg"
    exe.write_text("#!/bin/sh\n")
    exe.chmod(0o755)
    monkeypatch.setattr(d, "FFMPEG", str(exe))
    assert d.check_ffmpeg() is True and len(events) == 1


# ---- Nr. 155: Neural-Stimme offline auch im Wettlauf merken -------------------------------------------

class _Local:
    voice = "Kanya"

    def ready_path(self):
        return "/tmp/x.aiff"


class _Stream:
    voice, cached = "th-TH-NiwatNeural", None

    def cancel(self):
        pass


def _speaker_engine():
    eng = object.__new__(d.Engine)
    eng.mute, eng.tts, eng.volume, eng.rate = False, "edge", 1.0, 0
    return eng


def test_tts_offline_marked_in_race(monkeypatch):
    events, deadlines = [], []
    monkeypatch.setattr(d, "emit", lambda ev, **kw: events.append((ev, kw)))
    monkeypatch.setattr(d, "NET", {"translate": True, "tts": True})
    monkeypatch.setattr(d, "wait_quiet", lambda **k: 0.0)
    monkeypatch.setattr(d.PLAYER, "run", lambda cmd: 0)

    def offline(stream, vol, on_start=None, cancelled=None, deadline=None):
        deadlines.append(deadline)
        raise ConnectionError("no route")
    monkeypatch.setattr(d, "edge_play", offline)
    eng = _speaker_engine()
    eng.speak("hi", "th", stream=_Stream(), local=_Local())
    assert d.NET["tts"] is False and ("net", {"ok": False, "what": "tts"}) in events
    eng.speak("hi", "th", stream=_Stream(), local=_Local())
    assert deadlines == [d.TTS_RACE, min(d.TTS_RACE, d.TTS_OFFLINE_PROBE)]   # offline: kürzer warten


def test_tts_slow_is_not_offline(monkeypatch):
    monkeypatch.setattr(d, "emit", lambda ev, **kw: None)
    monkeypatch.setattr(d, "NET", {"translate": True, "tts": True})
    monkeypatch.setattr(d, "wait_quiet", lambda **k: 0.0)
    monkeypatch.setattr(d.PLAYER, "run", lambda cmd: 0)

    def slow(*a, **k):
        raise RuntimeError("edge-tts lieferte keine Audiodaten")
    monkeypatch.setattr(d, "edge_play", slow)
    _speaker_engine().speak("hi", "th", stream=_Stream(), local=_Local())
    assert d.NET["tts"] is True


# ---- Nr. 156: eigene Stimme nicht als „weder … noch …“ verwerfen ---------------------------------------

def test_neither_pair_lang_respects_own_voice():
    low = d.MIN_LANG_P / 3
    assert d.neither_pair_lang(low, low, None)
    assert d.neither_pair_lang(low, low, "other")        # „nicht ich“ kann auch Musik sein
    assert not d.neither_pair_lang(low, low, "me")
    assert not d.neither_pair_lang(0.6, 0.3, None)


# ---- Nr. 15: genutzte edge-tts-Interna existieren noch (schlägt beim Update sofort an) ----------------

def test_edge_tts_internals_present(monkeypatch):
    from edge_tts import communicate as ec
    for name in ("WSS_URL", "WSS_HEADERS", "SEC_MS_GEC_VERSION", "DRM", "TTSConfig", "mkssml", "escape",
                 "remove_incompatible_characters", "ssml_headers_plus_data", "connect_id", "date_to_string",
                 "_SSL_CTX"):
        assert hasattr(ec, name), f"edge_tts.communicate.{name} fehlt – eigener Websocket-Weg prüfen"
    assert callable(ec.DRM.generate_sec_ms_gec) and callable(ec.DRM.headers_with_muid)
    monkeypatch.setitem(d._WS, "ok", True)
    msg = d._ssml("Hello", "en-US-AriaNeural", "+0%")
    assert msg and "AriaNeural" in msg and "<speak" in msg and d._WS["ok"] is True


class LocalEntryNotFoundError(Exception):
    pass


@pytest.mark.parametrize("download_err, offline", [(OSError(28, "No space left"), False),
                                                    (ConnectionError("no route"), True)])
def test_wm_model_offline_only_for_network(monkeypatch, download_err, offline):
    events = []
    monkeypatch.setattr(d, "emit", lambda ev, **kw: events.append(kw.get("code")))
    monkeypatch.setattr(d, "_DOWNLOAD_SAID", {})

    def wm(model, local_files_only=False, **kw):
        if local_files_only:
            raise LocalEntryNotFoundError("not cached")
        raise download_err
    monkeypatch.setattr(d, "WhisperModel", wm)
    with pytest.raises(type(download_err)):
        d._wm("tiny", device="cpu")
    assert ("model_offline" in events) is offline
