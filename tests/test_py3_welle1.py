"""Py3 Welle 1: Sprachausgabe (Cache gilt nicht als online, Stopp-Rennen im Speaker, Vorab-Rendering,
Websocket-Leck, Abbruch vor dem ersten Ton)."""
import asyncio
import threading
import time
import types

import pytest

import dolmetscher as d


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    return events


def _eng(tts="edge"):
    return types.SimpleNamespace(tts=tts, mute=False, rate=0, volume=1.0, voice_for=lambda lang: "v",
                                 voice={"en": "x", "th": "y"}, polite="krub", voices={})


def _speaker_engine():
    e = d.Engine.__new__(d.Engine)
    e.__dict__.update(_eng().__dict__)
    return e


def test_cached_playback_does_not_claim_online(ev, monkeypatch):
    """Offline: ein Satz aus dem Cache beweist kein Netz – kein `net ok`, Ersatzstimmen-Anzeige bleibt."""
    monkeypatch.setitem(d.NET, "tts", False)
    monkeypatch.setitem(d._TTS_FB, "on", True)
    monkeypatch.setattr(d, "edge_play", lambda *a, **k: {"cached": True, "first_chunk_s": 0.0})
    monkeypatch.setattr(d, "EDGE_FIRST", d.collections.deque(maxlen=30))
    _speaker_engine().speak("hi", "en", stream=types.SimpleNamespace(voice="v", cancel=lambda: None))
    assert d.NET["tts"] is False and d._TTS_FB["on"] is True
    assert not any(x == "net" for x, _ in ev) and not d.EDGE_FIRST


def test_network_playback_still_reports_online(ev, monkeypatch):
    monkeypatch.setitem(d.NET, "tts", False)
    monkeypatch.setitem(d._TTS_FB, "on", True)
    monkeypatch.setattr(d, "edge_play", lambda *a, **k: {"cached": False, "first_chunk_s": 0.4})
    monkeypatch.setattr(d, "EDGE_FIRST", d.collections.deque(maxlen=30))
    _speaker_engine().speak("hi", "en", stream=types.SimpleNamespace(voice="v", cancel=lambda: None))
    assert d.NET["tts"] is True and d._TTS_FB["on"] is False
    assert ("net", {"ok": True, "what": "tts"}) in ev and list(d.EDGE_FIRST) == [0.4]


def test_play_uses_generation_taken_at_pop(ev):
    """flush() zwischen Entnehmen und Abspielen (Stopp): das Element wird nicht mehr gesprochen."""
    spoken = []

    class E:
        tts, mute, rate, volume = "say", False, 0, 1.0

        def voice_for(self, lang):
            return "x"

        def speak(self, text, lang, **k):
            spoken.append(text)
    sp = d.Speaker(E())
    old = d.CANCEL["gen"]
    d.CANCEL["gen"] += 1                              # Stopp kam, nachdem das Element entnommen wurde
    item = {"id": "u1", "lang": "en", "kind": "speech", "parts": [("hello", None)], "t_end": None, "pin": True,
            "text": "hello", "boost": 0}
    sp._play(item, old)
    assert spoken == []
    assert ("speak_done", {"id": "u1", "skipped": False, "interrupted": True}) in ev


def test_earcon_cancelled_while_waiting_is_silent(ev, monkeypatch):
    played = []
    monkeypatch.setattr(d.PLAYER, "run", lambda *a, **k: played.append(a))
    sp = d.Speaker(_eng())
    old = d.CANCEL["gen"]
    d.CANCEL["gen"] += 1
    sp._play({"id": "c", "kind": "earcon", "parts": []}, old)
    assert played == [] and ("speak_done", {"id": "c", "skipped": False, "interrupted": True}) in ev


def test_loop_passes_generation_from_pop(ev, monkeypatch):
    seen = []
    monkeypatch.setattr(d.Speaker, "_play", lambda self, it, gen=None: seen.append((it["id"], gen)))
    sp = d.Speaker(_eng())
    g = d.CANCEL["gen"]
    with sp.cond:
        sp.items.append({"id": "a", "lang": "en", "kind": "speech", "parts": [], "pin": True})
        sp.cond.notify_all()
    sp.wait_idle(3)
    assert seen == [("a", g)]


def test_prepare_survives_local_voice_failure(ev, monkeypatch):
    """Temp-Ordner weg/voll: kein Rückfall-Rendering, aber `add` scheitert nicht mehr nach der Übersetzung."""
    def boom(*a, **k):
        raise OSError("No space left on device")
    monkeypatch.setattr(d, "LocalVoice", boom)
    monkeypatch.setattr(d, "EdgeStream", lambda *a, **k: types.SimpleNamespace(cached=None, audio=threading.Event(),
                                                                                cancel=lambda: None))
    monkeypatch.setattr(d, "_say_voice", lambda eng, lang: "Samantha")
    sp = d.Speaker(_eng())
    stream, local = sp._prepare("hello", "en", 0)
    assert stream is not None and local is None
    sp2 = d.Speaker(_eng("say"))
    assert sp2._prepare("hello", "en", 0) == (None, None)


def test_ws_open_closes_socket_when_config_fails(monkeypatch):
    pytest.importorskip("aiohttp")
    closed = []

    class WS:
        closed = False

        async def send_str(self, s):
            raise ConnectionResetError("weg")

        async def close(self):
            closed.append(1)

    class Sess:
        closed = False

        async def ws_connect(self, *a, **kw):
            return WS()
    monkeypatch.setitem(d._WS, "session", Sess())
    with pytest.raises(ConnectionResetError):
        asyncio.run(d._ws_open())
    assert closed == [1]


def _stream():
    s = d.EdgeStream.__new__(d.EdgeStream)
    s.text, s.voice, s.rate, s.key = "x", "v", "+0%", ("v", "+0%", "x")
    s.t0, s.stop, s.hedged, s.pooled, s.audio = time.time(), threading.Event(), True, None, threading.Event()
    s.futs, s.cached, s.qs = [], None, [d.StreamQueue()]
    return s


def test_first_returns_promptly_when_cancelled():
    s = _stream()
    flag = {"c": False}
    threading.Timer(0.1, lambda: flag.update(c=True)).start()
    t = time.time()
    first, q = s.first(deadline=30.0, cancelled=lambda: flag["c"])
    assert first is d._CANCELLED and q is None and time.time() - t < 2
    assert s.stop.is_set()


def test_edge_play_cancelled_before_first_chunk_reports_interrupted():
    st = d.edge_play(_stream(), 1.0, cancelled=lambda: True, deadline=5.0)
    assert st["interrupted"] is True and "first_chunk_s" not in st


def test_speak_cancel_before_first_chunk_is_not_offline(ev, monkeypatch):
    """Ein Stopp vor dem ersten Ton ist kein Netzfehler: kein `net ok=False`, keine Ersatzstimme."""
    monkeypatch.setitem(d.NET, "tts", True)
    assert _speaker_engine().speak("hi", "en", stream=_stream(), cancelled=lambda: True) is None
    assert d.NET["tts"] is True and not any(x in ("net", "tts_fallback") for x, _ in ev)
