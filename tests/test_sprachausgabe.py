"""Sprachausgabe: say-Aufrufe, Abbruch, Temp-Dateien, edge-tts-Rückfall, Teilsätze (ohne Netz/Ton)."""
import os
import queue
import threading
import time
import types

import pytest

import dolmetscher as d


@pytest.fixture
def events(monkeypatch):
    ev = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: ev.append((e, kw)))
    return ev


@pytest.fixture
def tmpdir_iso(monkeypatch, tmp_path):
    """Eigenes private_tmp je Test (clean_tmp löscht es sonst für andere Tests)."""
    monkeypatch.setattr(d, "_TMPDIR", {"path": None})
    monkeypatch.setattr(d.tempfile, "tempdir", str(tmp_path))
    return tmp_path


# ---- say ----------------------------------------------------------------------------------------

def test_say_cmd_dashdash_and_rate_clamp():
    cmd = d.say_cmd("Kanya", 900, "/x.aiff", "-5 °C")
    assert cmd[cmd.index("--") + 1] == "-5 °C" and cmd[-1] == "-5 °C"
    assert int(cmd[cmd.index("-r") + 1]) == 370
    assert int(d.say_cmd("Kanya", -900, "/x.aiff", "a")[4]) >= 50


def test_run_cancellable_stops_on_cancel_and_timeout():
    t = time.monotonic()
    flag = {"c": False}
    threading.Timer(0.1, lambda: flag.update(c=True)).start()
    assert d.run_cancellable(["/bin/sleep", "30"], cancelled=lambda: flag["c"]) is None
    assert d.run_cancellable(["/bin/sleep", "30"], timeout=0.2) is None
    assert d.run_cancellable(["/usr/bin/true"]) == 0
    assert time.monotonic() - t < 5


def test_say_fallback_uses_dashdash_private_tmp_and_cancel(monkeypatch, tmpdir_iso):
    seen = {}

    def fake(cmd, timeout=d.SAY_TIMEOUT, cancelled=None):
        seen["cmd"], seen["cancelled"] = cmd, cancelled
        return 1
    monkeypatch.setattr(d, "run_cancellable", fake)
    played = []
    monkeypatch.setattr(d.PLAYER, "run", lambda cmd: played.append(cmd))
    e = types.SimpleNamespace(mute=False, tts="say", volume=1.0, rate=0, voice={"en": "Samantha"})
    stop = lambda: False  # noqa: E731
    d.Engine.speak(e, "- Yes", "en", cancelled=stop)
    cmd = seen["cmd"]
    assert cmd[cmd.index("--") + 1] == "- Yes"
    assert os.path.dirname(cmd[cmd.index("-o") + 1]) == d.private_tmp()
    assert seen["cancelled"] is stop and played == []           # say gescheitert: nichts abspielen


# ---- Temp-Dateien -------------------------------------------------------------------------------

def test_clean_tmp_removes_own_dir_and_old_leftovers(tmpdir_iso):
    own = d.private_tmp()
    open(os.path.join(own, "dolmetscher_race_x.aiff"), "wb").close()
    old_dir = tmpdir_iso / "dolmetscher_alt"
    old_dir.mkdir()
    (old_dir / "a.aiff").write_bytes(b"x")
    old_file = tmpdir_iso / "dolmetscher_say_y.aiff"
    old_file.write_bytes(b"x")
    young = tmpdir_iso / "dolmetscher_jung"
    young.mkdir()
    other = tmpdir_iso / "fremd_alt"
    other.mkdir()
    past = time.time() - 7200
    for p in (old_dir, old_file, other):
        os.utime(p, (past, past))
    d.clean_tmp()
    assert not os.path.exists(own) and not old_dir.exists() and not old_file.exists()
    assert young.exists() and other.exists()
    assert d.private_tmp() != own                              # danach neu angelegt


def test_local_voice_cleanup_removes_file_and_skips_render(monkeypatch, tmpdir_iso):
    calls = []

    def fake_run(cmd, **kw):
        calls.append(cmd)
        open(cmd[cmd.index("-o") + 1], "wb").write(b"aiff")
        return types.SimpleNamespace(returncode=0)
    monkeypatch.setattr(d.subprocess, "run", fake_run)
    lv = d.LocalVoice("hallo", "Samantha", 0)
    assert lv.ready_path(10) and os.path.exists(lv.path)
    lv.cleanup()
    t = time.monotonic()
    while os.path.exists(lv.path) and time.monotonic() - t < 10:   # Aufräum-Thread; endet sofort nach dem Löschen
        time.sleep(0.01)
    assert not os.path.exists(lv.path)
    # Großzügige Frist statt 0,4 s: der Neural-Ton (Timer 0,1 s) kommt auch auf langsamen Runnern sicher innerhalb
    # der Frist. Die Aussage bleibt dieselbe: kommt der Ton während des Wartens, wird nicht gerendert.
    monkeypatch.setattr(d.LocalVoice, "DELAY", 30)
    audio = threading.Event()
    threading.Timer(0.1, audio.set).start()                    # Neural-Ton kommt kurz danach -> nicht rendern
    lv2 = d.LocalVoice("hallo", "Samantha", 0, audio=audio)
    assert lv2.ready_path(10) is None and len(calls) == 1

    class NeverWait(threading.Event):
        """Offline darf gar nicht auf den Neural-Ton gewartet werden (statt einer Messung auf der echten Uhr)."""
        waited = False

        def wait(self, timeout=None):
            NeverWait.waited = True
            return super().wait(timeout)
    monkeypatch.setitem(d.NET, "tts", False)                   # offline: sofort rendern, nicht warten
    lv3 = d.LocalVoice("hallo", "Samantha", 0, audio=NeverWait())
    assert lv3.ready_path(10) and len(calls) == 2 and not NeverWait.waited
    lv3.cleanup()


# ---- edge-tts -----------------------------------------------------------------------------------

def test_next_chunk_returns_quickly_on_cancel():
    q = queue.Queue()
    t = time.monotonic()
    flag = {"c": False}
    threading.Timer(0.1, lambda: flag.update(c=True)).start()
    assert d._next_chunk(q, lambda: flag["c"]) is d._CANCELLED
    assert time.monotonic() - t < 1
    with pytest.raises(queue.Empty):
        d._next_chunk(q, idle=0.1, step=0.05)


class _Stream:
    voice, cached, text, hedged, t0 = "v", None, "hi", False, 0.0
    key = ("v", "+0%", "hi")

    def __init__(self, chunks):
        self.q = queue.Queue()
        for c in chunks:
            self.q.put(c)
        self.t0 = time.time()

    def first(self, deadline=None):
        return self.q.get(timeout=1), self.q

    def cancel(self):
        pass


def test_edge_play_reports_partial(monkeypatch):
    monkeypatch.setattr(d, "NULL_AUDIO", True)
    monkeypatch.setattr(d, "_PIPE_PLAYER", "at")
    st = d.edge_play(_Stream([b"a", ConnectionError("weg")]), 1.0)
    assert st.get("partial") and "err" in st
    st = d.edge_play(_Stream([b"a", b"b", None]), 1.0)
    assert not st.get("partial")


def test_speak_does_not_restart_after_sound_began(monkeypatch):
    def play(stream, volume, on_start=None, cancelled=None, deadline=None):
        on_start(0.1)
        raise OSError("abgerissen")
    monkeypatch.setattr(d, "edge_play", play)
    monkeypatch.setattr(d, "run_cancellable", lambda *a, **k: pytest.fail("say darf nicht von vorn sprechen"))
    e = types.SimpleNamespace(mute=False, tts="edge", volume=1.0, rate=0, voice={"en": "Samantha"})
    assert d.Engine.speak(e, "hi", "en", stream=_Stream([]), on_start=lambda s: None) == "partial"


class _Comm:
    def __init__(self, *a, **k):
        pass

    async def stream(self):
        yield {"type": "audio", "data": b"LEGACY"}


def _drain(q):
    out = []
    while True:
        x = q.get(timeout=3)
        out.append(x)
        if x is None or isinstance(x, Exception):
            return out


def test_produce_falls_back_to_communicate_and_switches_ws_off(monkeypatch):
    import edge_tts
    monkeypatch.setattr(d, "TTS_CACHE", d.collections.OrderedDict())
    monkeypatch.setattr(d, "_WS_HEALTH", {"fails": 0, "off_until": 0.0})
    monkeypatch.setitem(d._WS, "ok", True)
    monkeypatch.setattr(edge_tts, "Communicate", _Comm)
    monkeypatch.setattr(d, "_ssml", lambda *a: "ssml" if d._ws_usable() else None)
    calls = []

    async def ws_fail(ssml, put, stopped):
        calls.append(1)
        raise ConnectionResetError("403")
    monkeypatch.setattr(d, "_ws_speak", ws_fail)
    for _ in range(d.WS_FAIL_MAX):
        st = d.EdgeStream("Hello there", "v", "+0%")
        assert _drain(st.qs[0]) == [b"LEGACY", None] and st.audio.is_set()
    assert len(calls) == d.WS_FAIL_MAX and not d._ws_usable()      # eigener Weg vorerst aus
    st = d.EdgeStream("Hello again", "v", "+0%")
    assert _drain(st.qs[0]) == [b"LEGACY", None] and len(calls) == d.WS_FAIL_MAX


def test_produce_no_fallback_after_audio(monkeypatch):
    import edge_tts
    monkeypatch.setattr(d, "TTS_CACHE", d.collections.OrderedDict())
    monkeypatch.setattr(d, "_ssml", lambda *a: "ssml")
    monkeypatch.setattr(edge_tts, "Communicate", lambda *a, **k: pytest.fail("kein Neustart nach Ton"))

    async def half(ssml, put, stopped):
        put(b"HALB")
        raise ConnectionResetError("weg")
    monkeypatch.setattr(d, "_ws_speak", half)
    st = d.EdgeStream("Hello there", "v", "+0%")
    out = _drain(st.qs[0])
    assert out[0] == b"HALB" and isinstance(out[-1], Exception)


# ---- Speaker ------------------------------------------------------------------------------------

def test_speaker_prestarts_two_parts_and_reports_partial(monkeypatch, events):
    monkeypatch.setattr(d, "split_sentences", lambda s, lang: ["a", "b", "c", "d"])
    prepared, spoken = [], []

    class E:
        tts, mute, rate, volume = "edge", False, 0, 1.0

        def speak(self, text, lang, stream=None, on_start=None, boost=0, cancelled=None, local=None):
            spoken.append((text, list(prepared)))
            return "partial" if text == "c" else None
    sp = d.Speaker.__new__(d.Speaker)
    sp.eng, sp.items, sp.cond, sp.busy = E(), d.collections.deque(), threading.Condition(), False

    def prep(s, lang, boost):
        prepared.append(s)
        return types.SimpleNamespace(cancel=lambda: None), None
    monkeypatch.setattr(sp, "_prepare", prep)
    monkeypatch.setitem(d._QSTATE, "speaker", sp)
    sp.add("abcd", "en", "u1")
    assert prepared == ["a", "b"]
    threading.Thread(target=sp._loop, daemon=True).start()
    sp.wait_idle(3)
    assert [t for t, _ in spoken] == ["a", "b", "c", "d"]
    assert spoken[1][1] == ["a", "b", "c"]                  # c erst während b angefragt
    done = [kw for e, kw in events if e == "speak_done"]
    assert done == [{"id": "u1", "skipped": False, "interrupted": False, "partial": True}]
