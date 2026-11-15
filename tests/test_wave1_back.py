import json
import queue
import types

import numpy as np

import dolmetscher as d


def _eng():
    e = types.SimpleNamespace(translate_dir={"en": True, "th": True}, lock="auto", polite="krub", mute=False,
                              paused=False, rate=0, volume=1.0, voices={"en": None, "th": None}, earcons=False)
    e.stop_speaking = lambda: None
    return e


def test_bool_strict_and_clamp():
    assert d._as_bool("false") is False and d._as_bool("true") is True and d._as_bool("maybe") is None
    assert d._as_bool(2) is None and d._as_bool(None) is None
    assert d._clamp(True, 0, 1) is None and d._clamp(float("nan"), 0, 1) is None and d._clamp(99, -50, 50) == 50
    e = _eng()
    d.apply_control(e, {"paused": "false", "tr_en": "false", "tr_th": "maybe", "rate": True})
    assert e.paused is False and e.translate_dir == {"en": False, "th": True} and e.rate == 0


def test_voice_error_and_limits(monkeypatch):
    ev = []
    monkeypatch.setattr(d, "emit", lambda event, **kw: ev.append((event, kw)))
    e = _eng()
    d.apply_control(e, {"voice_en": "nope"})
    assert ev and ev[0][0] == "error" and e.voices["en"] is None
    ev.clear()
    d.apply_control(e, {"voice_th": None, "voice_en": ""})
    assert not ev
    assert d.apply_control(e, {"say": {"text": "x" * 5000, "lang": "en"}}) is None
    assert d.apply_control(e, {"say": {"text": 5, "lang": "en"}}) is None
    assert d.apply_control(e, {"glossary": {"a": 1}}) is None
    assert [x[0] for x in ev] == ["error", "error", "error"]


def test_ping_pong(monkeypatch):
    ev = []
    monkeypatch.setattr(d, "emit", lambda event, **kw: ev.append((event, kw)))
    d.apply_control(_eng(), {"ping": 7})
    assert ev == [("pong", {"id": 7})]


def test_control_log_allowlist_and_stdin_eof(monkeypatch):
    logged = []
    monkeypatch.setattr(d, "log", lambda x: logged.append(x))
    monkeypatch.setattr(d, "_BAD_JSON", {"n": 0, "t": 0.0})
    monkeypatch.setattr(d.sys, "stdin", iter([json.dumps({"glossary": "geheim", "rate": 5, "x": "y"}) + "\n",
                                                "kaputt\n", "kaputt\n"]))
    monkeypatch.setattr(d, "load_glossary", lambda g: None)
    d.STOP.clear()
    d.control_loop(_eng())
    assert d.STOP.wait(3)                        # stdin-Ende -> geordnetes Beenden
    d.STOP.clear()
    ctl = [x["control"] for x in logged if isinstance(x.get("control"), dict)]
    assert ctl == [{"glossary": "…", "rate": 5, "x": "…"}]
    assert sum(1 for x in logged if x.get("control") == "ungültiges JSON") == 1     # ratenbegrenzt


def test_strip_punct():
    assert d._strip_punct("…“pause”。 ¿") == "pause"
    assert d._strip_punct("ปิด!") == "ปิด"


def _engine(calls=None):
    e = d.Engine.__new__(d.Engine)
    e.m_det, e.spk, e.lock, e.paused, e.awake_until = None, None, "auto", False, 0.0
    e.translate_dir = {"en": True, "th": True}
    e.history = d.collections.deque(maxlen=8)
    e.texts, e.last, e.mute = {"a": ("en", "x")}, ("o", "th", "u"), False
    e.recent = d.collections.OrderedDict(a=(np.zeros(4), None))
    e.rate, e.volume, e.polite, e.voices, e.earcons = 0, 1.0, "krub", {}, False
    e.speaker = types.SimpleNamespace(add=lambda *a, **k: calls.append(a) if calls is not None else None)
    return e


def test_sorry_keeps_wake_window_and_clear_wipes(monkeypatch):
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    e = _engine()
    e.command("")
    until = e.awake_until
    assert e.command("xyzzy plugh") == "Sorry?" and e.awake_until == until > 0
    e.command("pause")
    assert e.awake_until == 0.0
    e.command("clear")
    assert not e.texts and not e.recent and e.last is None


def test_repeat_uses_common_tail(monkeypatch):
    calls, ev = [], []
    monkeypatch.setattr(d, "emit", lambda event, **kw: ev.append(event))
    e = _engine(calls)
    assert e.command("repeat") is None and calls and ev == ["command"]


def test_detect_failure_falls_back(monkeypatch):
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    got = []

    class Det:
        def detect_language(self, **k):
            raise RuntimeError("boom")
    e = _engine()
    e.m_det = Det()
    e._stt = lambda audio, lang, hotwords=None, model=None, quick=False: ("Hello there", -0.2, [])
    e.deliver = lambda uid, lang, text, *a, **k: got.append((lang, text))
    e.process(np.full(d.SR, 0.05, dtype=np.float32), speak=False, uid="u1")
    assert got == [("en", "Hello there")]


def test_wake_window_only_for_short_followups(monkeypatch):
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    seen = []
    e = _engine()
    e.m_det = types.SimpleNamespace(detect_language=lambda **k: ("en", 1.0, [("en", 1.0)]))
    e._stt = lambda audio, lang, hotwords=None, model=None, quick=False: (
        "this is a long ordinary sentence to translate", -0.2, [])
    e.command = lambda c: seen.append(c)
    e.deliver = lambda *a, **k: seen.append("deliver")
    e.awake_until = d.time.monotonic() + 5
    e.process(np.full(d.SR * 8, 0.05, dtype=np.float32), speak=False, uid="u")
    assert seen == ["deliver"] and e.awake_until == 0.0


def test_beam_env_validated(monkeypatch):
    monkeypatch.setenv("DOLMETSCHER_BEAM", "abc")
    assert d._env_beam() == 1
    monkeypatch.setenv("DOLMETSCHER_BEAM", "99")
    assert d._env_beam() == 10


def test_pseudonym_stable_and_hides_name():
    assert d._pseud("Patrick") == d._pseud("Patrick") and "Patrick" not in d._pseud("Patrick")
    assert d._pseud(None) is None


def test_work_loop_stops_on_event():
    q = queue.Queue()
    d.STOP.set()
    try:
        d.work_loop(types.SimpleNamespace(), q, speak=False)      # kehrt sofort zurück
    finally:
        d.STOP.clear()


def test_segmenter_flushes_utterance_at_end(monkeypatch):
    N = d.StreamVAD.N

    class FakeVAD:
        N = 512
        CTX = 64

        def reset(self):
            pass

        def __call__(self, f):
            return 0.9
    monkeypatch.setattr(d, "StreamVAD", FakeVAD)
    frames = queue.Queue()
    for i in range(30):
        frames.put((np.full(N, 0.1, dtype=np.float32), 1000.0 + i * 0.032))
    frames.put((np.full(100, 0.1, dtype=np.float32), 1001.0))       # Rest-Teilframe
    frames.put((np.zeros(0, dtype=np.float32), 1002.0))
    utts = queue.Queue()
    d.segmenter(frames.get, utts)
    items = []
    while (x := utts.get_nowait()) is not None:
        if not isinstance(x[0], str):
            items.append(x)
    assert len(items) == 1 and items[0][3] == "ende" and items[0][0].size == 31 * N
