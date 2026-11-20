"""Py3 Welle 4: Cache nach clear/Stopp, „online“-Meldungen, Stopp im Ersatzstimmen-Wettlauf."""
import types

import pytest

import dolmetscher as d


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    return events


class _Q:
    def __init__(self, items):
        self.items = list(items)

    def get(self, timeout=None):
        return self.items.pop(0)


def _stream(text="hello"):
    return types.SimpleNamespace(
        text=text, voice="v", key=("v", "+0%", text), cached=None, hedged=False, pooled=None, t0=d.time.time(),
        first=lambda deadline=None, cancelled=None: (b"aa", _Q([b"bb", None])), cancel=lambda: None)


@pytest.fixture
def pipe(monkeypatch):
    class P:
        stdin = types.SimpleNamespace(write=lambda c: None, close=lambda: None)
    monkeypatch.setattr(d, "pipe_player", lambda v: ["x"])
    monkeypatch.setattr(d.PLAYER, "start", lambda *a, **k: P())
    monkeypatch.setattr(d.PLAYER, "wait", lambda *a, **k: None)
    monkeypatch.setattr(d, "wait_quiet", lambda **k: 0.0)
    monkeypatch.setattr(d, "TTS_CACHE", d.collections.OrderedDict())
    monkeypatch.setitem(d.TTS_LAST, "key", None)


def test_sentence_cleared_during_playback_is_not_cached(pipe):
    flag = {"c": False}
    s = _stream()
    s.first = lambda deadline=None, cancelled=None: (flag.update(c=True) or b"aa", _Q([b"bb", None]))
    st = d.edge_play(s, 1.0, cancelled=lambda: flag["c"])
    assert st["interrupted"] and not d.TTS_CACHE


def test_sentence_cleared_long_text_not_kept_as_last(pipe):
    flag = {"c": False}
    s = _stream("x" * 200)
    s.first = lambda deadline=None, cancelled=None: (flag.update(c=True) or b"aa", _Q([None]))
    d.edge_play(s, 1.0, cancelled=lambda: flag["c"])
    assert d.TTS_LAST["key"] is None


def test_complete_sentence_still_cached(pipe):
    d.edge_play(_stream(), 1.0, cancelled=lambda: False)
    assert d.TTS_CACHE


def _deliver(monkeypatch, meta):
    e = d.Engine.__new__(d.Engine)
    e.translate_dir, e.history, e.texts, e.polite = {"en": True, "th": True}, d.collections.deque(), {}, "krub"
    e.speaker = types.SimpleNamespace(add=lambda *a, **k: None)

    def tr(text, src, dst, history=(), alts=(), polite="krub", meta=None):
        meta.update(meta_in)
        return "ok"
    meta_in = meta
    monkeypatch.setattr(d, "translate", tr)
    monkeypatch.setattr(d, "fix_thai", lambda out, *a, **k: out)
    e.deliver("u1", "en", "hello", speak=False)


@pytest.mark.parametrize("meta,expect", [({"provider": "google"}, [True]), ({"provider": "google", "cached": True}, []),
                                         ({"provider": "none"}, []), ({"provider": "apple"}, [])])
def test_translate_online_only_from_real_answer(ev, monkeypatch, meta, expect):
    monkeypatch.setitem(d.NET, "translate", False)
    _deliver(monkeypatch, meta)
    nets = [kw["ok"] for x, kw in ev if x == "net" and kw.get("what") == "translate"]
    assert nets == expect                           # apple: schon offline, keine Änderung


def test_stop_during_race_returns_without_fallback(ev, monkeypatch):
    flag = {"c": False}

    def boom(*a, **k):
        raise RuntimeError("slow")
    monkeypatch.setattr(d, "edge_play", boom)
    local = types.SimpleNamespace(ready_path=lambda **k: flag.update(c=True), voice="s")
    ran = []
    monkeypatch.setattr(d, "run_cancellable", lambda *a, **k: ran.append(1))
    e = d.Engine.__new__(d.Engine)
    e.__dict__.update(tts="edge", mute=False, rate=0, volume=1.0, voice_for=lambda lg: "v", voice={}, voices={})
    e.speak("hi", "en", stream=_stream(), cancelled=lambda: flag["c"], local=local)
    assert not ran and not any(x == "tts_fallback" for x, _ in ev)


def test_player_oserror_is_not_offline(ev, monkeypatch):
    monkeypatch.setitem(d.NET, "tts", True)

    def boom(*a, **k):
        raise OSError("Too many open files")
    monkeypatch.setattr(d, "edge_play", boom)
    e = d.Engine.__new__(d.Engine)
    e.__dict__.update(tts="edge", mute=False, rate=0, volume=1.0, voice_for=lambda lg: "v", voice={}, voices={})
    monkeypatch.setattr(d, "run_cancellable", lambda *a, **k: 1)
    e.speak("hi", "en", stream=_stream(), local=None)
    assert d.NET["tts"] is True
