"""Welle 1 (Sprachausgabe/Player/TTS): Robustheit ohne Netz, Ton und Modelle."""
import asyncio
import collections
import threading

import pytest

import dolmetscher as d


def test_player_run_survives_missing_program(monkeypatch):
    def boom(*a, **kw):
        raise FileNotFoundError("afplay")
    monkeypatch.setattr(d.subprocess, "Popen", boom)
    monkeypatch.setattr(d, "NULL_AUDIO", False)
    assert d.Player().run(["/nonexistent/afplay", "x"]) is False


def test_player_playing_reads_under_lock():
    p = d.Player()
    assert p.playing() is False
    p.procs[object()] = 1.0
    assert p.playing() is True
    p.lock.acquire()
    try:
        t = threading.Thread(target=lambda: p.playing())
        t.start()
        t.join(0.2)
        assert t.is_alive()                 # wartet auf das Lock = liest nicht ungeschützt
    finally:
        p.lock.release()
    t.join(1)


def test_run_cancellable_missing_binary_returns_none():
    assert d.run_cancellable(["/nonexistent/say-binary"]) is None


def test_ws_binary_payload():
    hdr = b"Path:audio\r\n"
    raw = len(hdr).to_bytes(2, "big") + hdr + b"MP3DATA"
    assert d._ws_binary_payload(raw) == b"MP3DATA"
    with pytest.raises(ValueError):
        d._ws_binary_payload(b"\x00")
    with pytest.raises(ValueError):
        d._ws_binary_payload((500).to_bytes(2, "big") + b"short")


class _Msg:
    def __init__(self, typ, data):
        self.type, self.data = typ, data


class _FakeWS:
    closed = False

    def __init__(self, msgs, hang=False):
        self.msgs, self.hang, self.sent = list(msgs), hang, []

    async def send_str(self, s):
        self.sent.append(s)

    def __aiter__(self):
        return self

    async def __anext__(self):
        if self.hang:
            await asyncio.sleep(60)
        if not self.msgs:
            raise StopAsyncIteration
        return self.msgs.pop(0)

    async def close(self):
        self.closed = True


def _audio(data=b"A"):
    import aiohttp
    hdr = b"Path:audio\r\n"
    return _Msg(aiohttp.WSMsgType.BINARY, len(hdr).to_bytes(2, "big") + hdr + data)


def _end():
    import aiohttp
    return _Msg(aiohttp.WSMsgType.TEXT, "X-RequestId:1\r\nPath:turn.end\r\n\r\n{}")


def _speak(monkeypatch, ws, stopped=lambda: False):
    pytest.importorskip("aiohttp")
    got = []

    async def fake_open():
        return ws
    monkeypatch.setattr(d, "_ws_open", fake_open)
    monkeypatch.setattr(d, "_ws_take", lambda: None)

    async def go():
        return await d._ws_speak("ssml", got.append, stopped)
    return go, got


def test_ws_speak_complete(monkeypatch):
    pytest.importorskip("edge_tts")
    pytest.importorskip("aiohttp")
    go, got = _speak(monkeypatch, _FakeWS([_audio(b"1"), _audio(b"2"), _end()]))
    asyncio.run(go())
    assert got == [b"1", b"2"]


def test_ws_speak_truncated_stream_is_error(monkeypatch):
    pytest.importorskip("edge_tts")
    pytest.importorskip("aiohttp")
    go, got = _speak(monkeypatch, _FakeWS([_audio(b"1")]))    # Server schließt ohne turn.end
    with pytest.raises(RuntimeError, match="vor Satzende"):
        asyncio.run(go())
    assert got == [b"1"]


def test_ws_speak_no_audio_is_error(monkeypatch):
    pytest.importorskip("edge_tts")
    pytest.importorskip("aiohttp")
    go, _ = _speak(monkeypatch, _FakeWS([_end()]))
    with pytest.raises(RuntimeError, match="keine Audiodaten"):
        asyncio.run(go())


def test_ws_speak_server_hangs(monkeypatch):
    monkeypatch.setattr(d, "WS_RECV_S", 0.05)
    go, _ = _speak(monkeypatch, _FakeWS([], hang=True))
    with pytest.raises(Exception):
        asyncio.run(go())


def test_stream_queue_lost_flag_is_declared():
    q = d.StreamQueue()
    assert q.lost is False
    q.lost = True
    assert q.lost is True and d.StreamQueue().lost is False


def test_edge_say_passes_cancelled(monkeypatch):
    seen = {}
    monkeypatch.setattr(d, "EdgeStream", lambda *a: "S")
    monkeypatch.setattr(d, "edge_play", lambda stream, volume, on_start=None, cancelled=None, deadline=None:
                        seen.update(c=cancelled) or {})
    marker = lambda: True  # noqa: E731
    d.edge_say("t", "v", "+0%", 1.0, None, marker)
    assert seen["c"] is marker


def test_tts_fallback_end_emits_once(monkeypatch):
    ev = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: ev.append((e, kw)))
    monkeypatch.setitem(d._TTS_FB, "on", False)
    d._tts_fallback_end()
    assert ev == []
    d._tts_fallback("slow")
    d._tts_fallback_end()
    d._tts_fallback_end()
    assert ev == [("tts_fallback", {"reason": "slow"}), ("tts_fallback", {"ended": True})]


def test_echo_prefilter_still_detects_and_skips_far_lengths(monkeypatch):
    monkeypatch.setattr(d, "_SPOKEN", collections.deque(maxlen=8))
    d.note_spoken("Where is the nearest pharmacy please?", "en", now=10.0)
    assert d.is_echo("where is the nearest pharmacy please", "en", now=12.0)
    assert not d.is_echo("a totally different long sentence about trains", "en", now=12.0)
    assert not d.is_echo("Where is the nearest pharmacy please? And also the bus station, the market and the beach",
                         "en", now=12.0)


def test_pseud_salt_stable_and_race_safe(monkeypatch, tmp_path):
    import history_store
    monkeypatch.setattr(history_store, "home_dir", lambda: str(tmp_path))
    monkeypatch.setitem(d._PSEUD_SALT, "v", None)
    out = []
    ts = [threading.Thread(target=lambda: out.append(d._pseud_salt())) for _ in range(8)]
    [t.start() for t in ts]
    [t.join() for t in ts]
    assert len(set(out)) == 1 and len(out[0]) >= 16
    assert (tmp_path / "log_salt").read_text().strip() == out[0]


def test_restore_last_blocked_after_clear(monkeypatch):
    import history_store

    class Rec:
        on = True

        class store:
            @staticmethod
            def last_translation():
                return {"lang": "th", "translation": "สวัสดี"}
    monkeypatch.setattr(history_store, "RECORDER", Rec)
    monkeypatch.setitem(d.TARGET, "th", "th")
    e = d.Engine.__new__(d.Engine)
    e.last = None
    e._cleared = True
    assert e.restore_last() is False


def test_prerender_max_is_logged(monkeypatch):
    logs = []
    monkeypatch.setattr(d, "log", lambda x: logs.append(x))
    monkeypatch.setattr(d, "edge_prerender", lambda *a: True)
    monkeypatch.setattr(d, "PRERENDER_MAX", 2)
    monkeypatch.setattr(d, "NET", {"tts": True, "translate": True})
    monkeypatch.setitem(d.PRIVATE, "on", False)

    class E:
        tts, mute, rate = "edge", False, 0
        voice_for = staticmethod(lambda lg: "v")
    preset = {"phrases": [{"critical": True, "en": f"Help number {i} now.", "th": f"ช่วยด้วย {i}"} for i in range(3)]}
    t = d.prerender_critical(E, preset)
    assert t is not None
    t.join(5)
    assert any(x.get("prerender") == "notfall-phrasen gekürzt" for x in logs)
