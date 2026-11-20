"""Welle 4 (Websocket-Zeitversatz, Beenden, Abspiel-Notbremse, Vorab-Laden, Mikrofon-Namen)."""
import asyncio
import time
import types

import pytest

import dolmetscher as d


def test_player_limit_scales_with_audio_length():
    assert d.Player.limit_for(0) == 8.0
    assert d.Player.limit_for(6000 * 10) == pytest.approx(20.0)
    assert d.Player.limit_for(10 ** 9) == d.Player.WAIT_MAX


def test_player_wait_uses_given_limit():
    calls = []

    class P:
        def wait(self, timeout=None):
            calls.append(timeout)
    pl = d.Player()
    p = P()
    pl.procs[p] = 1.0
    pl.wait(p, 12.0)
    pl.procs[p] = 1.0
    pl.wait(p)
    assert calls == [12.0, d.Player.WAIT_MAX]


def test_tts_shutdown_without_loop_is_noop(monkeypatch):
    monkeypatch.setattr(d, "_TTS_LOOP", None)
    d.tts_shutdown()


def test_tts_shutdown_stops_loop(monkeypatch):
    monkeypatch.setattr(d, "_TTS_LOOP", None)
    loop = d.tts_loop()
    assert loop.is_running()
    d.tts_shutdown()
    for _ in range(40):
        if not loop.is_running():
            break
        time.sleep(0.05)
    assert not loop.is_running() and d._TTS_LOOP is None


def test_ws_open_403_applies_clock_skew(monkeypatch):
    aiohttp = pytest.importorskip("aiohttp")
    from edge_tts import communicate as ec
    seen = []
    monkeypatch.setattr(ec.DRM, "handle_client_response_error", lambda e: seen.append(e.status))

    class Sess:
        closed = False

        async def ws_connect(self, *a, **kw):
            raise aiohttp.WSServerHandshakeError(None, (), status=403, message="Forbidden")
    monkeypatch.setitem(d._WS, "session", Sess())
    with pytest.raises(aiohttp.WSServerHandshakeError):
        asyncio.run(d._ws_open())
    assert seen == [403]


def test_proxy_switch_in_source():
    assert "DOLMETSCHER_TTS_NO_PROXY" in open(d.__file__, encoding="utf-8").read()


def test_reassign_single_lookup_and_role_history(monkeypatch):
    import numpy as np
    ev = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: ev.append((e, kw)))
    e = d.Engine.__new__(d.Engine)
    e.recent = d.collections.OrderedDict()
    e._expire_recent = lambda: None
    e.last_role = ("me", 1.0)
    e.reassign("gone", "other")
    assert ev[-1][1]["code"] == "reassign_expired"
    e.recent["u"] = (np.zeros(1600, dtype=np.float32), None)
    e._hotwords = lambda *a: None
    e._stt = lambda *a, **k: ("", -1.0, [])
    e._clean_reassigned = lambda text, *a: ""
    e.reassign("u", "other")
    assert ev[-1][1]["code"] == "reassign_empty" and e.last_role == ("me", 1.0)


def test_prerecognize_skipped_on_backlog(monkeypatch):
    import numpy as np
    logs = []
    monkeypatch.setattr(d, "log", lambda x: logs.append(x))
    monkeypatch.setattr(d, "_backlog", lambda: d.DEGRADE_AT)
    e = d.Engine.__new__(d.Engine)

    def boom(*a, **k):
        raise AssertionError("darf nicht erkennen")
    e.m_det = types.SimpleNamespace(detect_language=boom)
    e.prerecognize("u", 1, np.zeros(16000, dtype=np.float32))
    assert logs and logs[-1]["pre"]["skipped"] == "rückstand"


def test_resolve_mic_ambiguous_name_reported(monkeypatch):
    hints = []
    monkeypatch.setattr(d, "hint", lambda code, **kw: hints.append((code, kw)))
    monkeypatch.setattr(d, "list_mics", lambda: [{"index": "2", "name": "USB Audio"},
                                                 {"index": "3", "name": "USB Audio"}])
    assert d.resolve_mic("usb audio") == "2"
    assert hints == [("mic_ambiguous", {"n": 2})]


def test_tts_prepare_waits_for_speech():
    src = open(d.__file__, encoding="utf-8").read()
    assert 'emit("hearing", id=uid)\n                continue' in src          # kein Vorab-Laden mehr beim Onset
    assert "speech >= TTS_PREPARE_AFTER_S" in src and d.TTS_PREPARE_AFTER_S >= 0.2
