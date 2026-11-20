"""Runde 24: Laufzeitverhalten der Engine (Teilphrasen, Zahlen, Spur, Latenz-Verlauf, Lücken, Schnellmodus,
MPS-Rückfall, Log-Positivliste)."""
import collections
import json
import types

import numpy as np
import pytest

import dolmetscher as d

_REAL_EMIT = d.emit


# ---- first_clause: Zahlen nicht zerschneiden (Fehler: "at 10:" / "1," / "3,5" wurden als Teilphrase geliefert) ----
@pytest.mark.parametrize("buf,lang,expect", [
    ("The meeting is at 10:30 today, ok", "en", "The meeting is at 10:30 today,"),
    ("The price is 1,500 baht today, ok", "en", "The price is 1,500 baht today,"),
    ("Der Preis ist 3,5 Euro heute, ok", "de", "Der Preis ist 3,5 Euro heute,"),
    ("It costs 3.5 baht per piece, fine", "en", "It costs 3.5 baht per piece,"),
    ("I would like a table, please sit", "en", "I would like a table,"),
])
def test_first_clause_does_not_split_numbers(buf, lang, expect):
    assert d.first_clause(buf, lang) == expect


def test_first_clause_waits_while_number_is_incomplete():
    assert d.first_clause("The meeting is at 10:", "en") is None


# ---- _clamp: riesige Ganzzahl (JSON ohne Punkt) -> früher OverflowError im Steuer-Thread ----
def test_clamp_huge_int_does_not_overflow():
    assert d._clamp(10 ** 400, -50, 50) == 50
    assert d._clamp(-10 ** 400, -50, 50) == -50
    assert d._clamp(True, 0, 1) is None and d._clamp(float("inf"), 0, 1) is None and d._clamp("1", 0, 1) is None


def test_apply_control_huge_numbers_do_not_crash(monkeypatch):
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    e = types.SimpleNamespace(translate_dir={"en": True, "th": True}, lock="auto", polite="krub", mute=False,
                              paused=False, rate=0, volume=1.0, voices={"en": None, "th": None}, earcons=False)
    e.stop_speaking = lambda: None
    d.apply_control(e, {"rate": 10 ** 400, "volume": -10 ** 400})
    assert e.rate == 50 and e.volume == 0.2


# ---- erste Teilphrase -> TTS-Cache ----
class _Pool:
    def __init__(self):
        self.jobs = []

    def submit(self, fn, *a, **k):
        self.jobs.append((fn, a))


def _eng(tts="edge"):
    e = types.SimpleNamespace(tts=tts, mute=False, rate=0)
    e.voice_for = lambda lang: "voice-" + lang
    return e


def test_clause_prewarm_renders_only_whole_sentences_once(monkeypatch):
    pool = _Pool()
    monkeypatch.setattr(d, "_BG_POOL", pool)
    monkeypatch.setattr(d, "_CLAUSE_SEEN", collections.deque(maxlen=16))
    run = d.make_clause_prewarm(_eng())
    assert run("I would like a table,", "en") is False          # Komma: würde anders geschnitten
    assert run("I would like a table for two.", "en") is True
    assert run("I would like a table for two.", "en") is False  # nicht doppelt
    assert len(pool.jobs) == 1
    fn, args = pool.jobs[0]
    assert fn is d.edge_prerender and args[0] == "I would like a table for two." and args[1] == "voice-en"
    assert args[2] == "+5%"


def test_clause_prewarm_skipped_for_mute_say_and_unknown_language(monkeypatch):
    pool = _Pool()
    monkeypatch.setattr(d, "_BG_POOL", pool)
    monkeypatch.setattr(d, "_CLAUSE_SEEN", collections.deque(maxlen=16))
    assert d.make_clause_prewarm(_eng("say"))("Hello there.", "en") is False
    e = _eng()
    e.mute = True
    assert d.make_clause_prewarm(e)("Hello there.", "en") is False
    assert d.make_clause_prewarm(_eng())("Hello there.", "xx") is False
    assert pool.jobs == []


def test_claude_async_passes_on_clause_only_in_stream_mode(monkeypatch):
    seen = []
    monkeypatch.setattr(d, "claude_translate", lambda *a, **k: seen.append((a, k)) or "Hallo Welt")
    calls = []
    monkeypatch.setitem(d.CLAUSE_HOOK, "fn", lambda clause, lang: calls.append((clause, lang)))
    monkeypatch.setitem(d.LLM, "stream", False)
    d._claude_async("Hello world", "en", "de", (), (), "krub").result(2)
    assert seen[-1][1] == {}                                    # Standard: Aufruf unverändert
    monkeypatch.setitem(d.LLM, "stream", True)
    d._claude_async("Hello world", "en", "de", (), (), "krub").result(2)
    cb = seen[-1][1]["on_clause"]
    cb("Guten Tag.")
    assert calls == [("Guten Tag.", "de")]


def test_clause_hook_errors_are_swallowed(monkeypatch):
    def boom(c, lang):
        raise RuntimeError("x")
    monkeypatch.setitem(d.CLAUSE_HOOK, "fn", boom)
    d._clause_prewarm("Hello.", "en")                           # wirft nicht


def test_engine_init_installs_clause_hook():
    import inspect
    assert 'CLAUSE_HOOK["fn"] = make_clause_prewarm(self)' in inspect.getsource(d.Engine.__init__)


# ---- Spur je Satz ----
@pytest.fixture
def traces(monkeypatch):
    monkeypatch.setattr(d, "_TRACE", collections.OrderedDict())
    out = []
    monkeypatch.setattr(d, "log", lambda rec: out.append(rec))
    return out


def test_trace_marks_stages_and_finishes_once(traces):
    d.trace_mark("u1", "thinking", now=10.0)
    d.trace_mark("u1", "heard", now=10.4)
    d.trace_mark("u1", "heard", now=99.0)                        # zweite Meldung ändert den Zeitpunkt nicht
    d.trace_mark("u1", "speak_done", now=12.0)
    out = d.trace_finish("u1")
    assert out["stages"] == {"thinking": 0.0, "heard": 0.4, "speak_done": 2.0} and out["total_s"] == 2.0
    assert traces == [{"trace": out}]
    assert d.trace_finish("u1") is None


def test_trace_ignores_bad_ids_and_is_bounded(traces):
    d.trace_mark(None, "x")
    d.trace_mark("", "x")
    d.trace_mark(5, "x")
    for i in range(d.TRACE_MAX + 20):
        d.trace_mark(f"u{i}", "thinking")
    assert len(d._TRACE) == d.TRACE_MAX and "u0" not in d._TRACE


def test_emit_feeds_trace_and_logs_at_the_end(traces, monkeypatch):
    monkeypatch.setattr(d, "_emit", lambda *a, **k: None)
    _REAL_EMIT("thinking", id="u7")
    _REAL_EMIT("heard", id="u7", lang="en", text="x")
    _REAL_EMIT("dropped", id="u7", reason="zu kurz", code="too_short")
    assert len(traces) == 1 and set(traces[0]["trace"]["stages"]) == {"thinking", "heard", "dropped"}
    _REAL_EMIT("dropped", reason="x")                            # ohne id: keine Spur
    assert len(traces) == 1


# ---- p50/p95-Verlauf über Sitzungen ----
@pytest.fixture
def lathist(monkeypatch, tmp_path):
    monkeypatch.setattr(d, "LAT_FILE", str(tmp_path / "lat.json"))
    monkeypatch.setattr(d, "_LAT_HIST", {k: collections.deque(maxlen=d.LAT_HIST_N) for k in ("stt", "tr", "sound")})
    monkeypatch.setattr(d, "_LAT_PERSIST", {"on": False, "dirty": 0, "t": 0.0})
    return tmp_path / "lat.json"


def test_lat_add_feeds_history_and_percentiles(lathist):
    for i in range(1, 101):
        d.lat_add("tr", i / 10)
    p = d.lat_percentiles()["tr"]
    assert p == {"n": 100, "p50": 5.0, "p95": 9.5}
    d.lat_add("tr", float("nan"))
    d.lat_add("tr", -1)
    assert d.lat_percentiles()["tr"]["n"] == 100


def test_lat_history_persists_across_sessions(lathist, monkeypatch):
    d.lat_load()                                                # schaltet das Sichern ein (Datei fehlt: ok)
    for v in (1.0, 2.0, 3.0):
        d.lat_add("stt", v)
    assert d.lat_save_if_due(force=True) is True
    assert json.loads(lathist.read_text())["rows"]["stt"] == [1.0, 2.0, 3.0]
    monkeypatch.setattr(d, "_LAT_HIST", {k: collections.deque(maxlen=d.LAT_HIST_N) for k in ("stt", "tr", "sound")})
    assert d.lat_load() == 3 and d.lat_percentiles()["stt"]["p50"] == 2.0


def test_lat_save_is_off_by_default_and_rate_limited(lathist):
    d.lat_add("stt", 1.0)
    assert d.lat_save_if_due(force=True) is False and not lathist.exists()  # nie in den Nutzerordner
    d.lat_load()
    d.lat_add("stt", 1.0)
    assert d.lat_save_if_due(now=1000.0) is True
    d.lat_add("stt", 1.0)
    assert d.lat_save_if_due(now=1001.0) is False                               # zu früh
    assert d.lat_save_if_due(now=1000.0 + d.LAT_SAVE_EVERY_S + 1) is True


def test_lat_load_ignores_garbage(lathist):
    lathist.write_text(json.dumps({"rows": {"stt": [1.0, "x", None, True, -3, 10 ** 6, float("nan")],
                                            "evil": [1], "tr": "no"}}))
    assert d.lat_load() == 1
    lathist.write_text("{kaputt")
    assert d.lat_load() == 0
    lathist.write_text("[1, 2]")
    assert d.lat_load() == 0


# ---- Mikrofon-Überlauf markiert den nächsten Satz ----
def test_overrun_marks_next_utterance_once(monkeypatch):
    monkeypatch.setattr(d, "_OVERRUN", {"n": 0, "t": 0.0, "told": 0, "gap": False})
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    assert d.take_gap() is False
    d._note_overrun()
    assert d.take_gap() is True and d.take_gap() is False


# ---- Rückstand -> Schnellmodus ----
def _stt_engine(beam=5):
    e = d.Engine.__new__(d.Engine)
    e.beam, e.m_th, e.device = beam, None, "cpu"
    return e


def _seg():
    return types.SimpleNamespace(text=" hello", avg_logprob=-0.2, start=0.0, end=1.0)


def test_pressure_uses_beam_one(monkeypatch):
    beams = []

    class M:
        def transcribe(self, audio, **kw):
            beams.append(kw["beam_size"])
            return [_seg()], None
    e = _stt_engine()
    e.m = M()
    monkeypatch.setattr(d, "_backlog", lambda: 0)
    e._stt(np.zeros(1600, dtype=np.float32), "en")
    monkeypatch.setattr(d, "_backlog", lambda: d.PRESSURE_AT)
    e._stt(np.zeros(1600, dtype=np.float32), "en")
    assert beams == [5, 1]


def test_queue_pressure_threshold(monkeypatch):
    monkeypatch.setattr(d, "_backlog", lambda: d.PRESSURE_AT - 1)
    assert d.queue_pressure() is False
    monkeypatch.setattr(d, "_backlog", lambda: d.PRESSURE_AT)
    assert d.queue_pressure() is True


# ---- MPS -> CPU im Betrieb ----
def test_mps_runtime_failure_falls_back_to_cpu_once(monkeypatch):
    hints = []
    monkeypatch.setattr(d, "hint", lambda code, **kw: hints.append((code, kw)))
    loaded = []

    class Cpu:
        def transcribe(self, audio, **kw):
            return [_seg()], None

    class Gpu:
        def transcribe(self, audio, **kw):
            raise RuntimeError("MPS backend out of memory")
    monkeypatch.setattr(d, "load_model", lambda name, dev, *a: (loaded.append((name, dev)) or Cpu(), dev))
    e = _stt_engine(1)
    e.device = "mps"
    e.m = e.m_det = Gpu()
    e._model_names = {"m": "small", "m_det": "small", "m_th": d.THAI_MODEL}
    text, lp, segs = e._stt(np.zeros(1600, dtype=np.float32), "en")
    assert text == "hello" and e.device == "cpu" and loaded == [("small", "cpu")]      # gleiches Modell nur einmal
    assert e.m is e.m_det and isinstance(e.m, Cpu) and hints == [("device_fallback", {"device": "cpu"})]


def test_mps_fallback_not_tried_twice_or_on_cpu(monkeypatch):
    monkeypatch.setattr(d, "hint", lambda *a, **k: None)
    e = _stt_engine()
    assert e._mps_to_cpu(RuntimeError("x")) is False            # läuft schon auf der CPU

    class Bad:
        def transcribe(self, audio, **kw):
            raise RuntimeError("kaputt")
    e.device, e.m = "mps", Bad()
    e._model_names = {"m": "small"}
    monkeypatch.setattr(d, "load_model", lambda *a: (_ for _ in ()).throw(OSError("kein Speicher")))
    with pytest.raises(RuntimeError):                           # Laden scheitert: ursprünglicher Fehler bleibt
        e._stt(np.zeros(1600, dtype=np.float32), "en")
    assert e.device == "mps"
    assert e._mps_to_cpu(RuntimeError("x")) is False            # kein zweiter Versuch


def test_other_errors_on_cpu_are_not_swallowed():
    class Bad:
        def transcribe(self, audio, **kw):
            raise ValueError("audio kaputt")
    e = _stt_engine()
    e.m = Bad()
    with pytest.raises(ValueError):
        e._stt(np.zeros(1600, dtype=np.float32), "en")


# ---- Log-Positivliste ----
def test_redact_free_masks_long_text_under_unknown_keys():
    long = "Where is the nearest hospital, my friend is very sick and needs help right now please " * 2
    out = d._redact_free({"neu": long, "err": long, "n": {"tief": long}, "liste": [long, "kurz"], "x": 3})
    assert out["neu"] == f"<{len(long)} Zeichen>" and out["err"] == long
    assert out["n"]["tief"].startswith("<") and out["liste"][0].startswith("<") and out["liste"][1] == "kurz"
    assert out["x"] == 3


def test_log_applies_whitelist_when_text_logging_is_off(monkeypatch):
    lines = []
    monkeypatch.setattr(d, "_logger", lambda: types.SimpleNamespace(info=lines.append))
    monkeypatch.setattr(d, "LOG_TEXT", False)
    d.log({"orig": "Please call my mother, she lives near the old market and speaks only Thai, thank you"})
    assert "Zeichen" in lines[0] and "mother" not in lines[0]
    d.log({"llm": "prompt-cache greift nicht (Prompt unter der Mindestlänge des Modells?)"})
    assert "Mindestlänge" in lines[1]                           # bekannte, kurze Meldungen bleiben lesbar
    monkeypatch.setattr(d, "LOG_TEXT", True)
    d.log({"orig": "x" * 100})
    assert "x" * 100 in lines[2]
