"""Py3 Welle 2: Mikrofon-Fehlerregel, Ende von --file, Aufräumen, clear."""
import queue
import types

import pytest

import dolmetscher as d


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    return events


def test_mic_plan_listen_before_load_with_idle_stays_idle():
    assert d.mic_plan(True, None) == (True, False)          # --idle: App startet später
    assert d.mic_plan(False, None) == (False, True)         # CLI: gleich aufnehmen, Fehler beendet
    assert d.mic_plan(True, True) == (True, True)           # listen vor dem Laden: starten, aber nie beenden
    assert d.mic_plan(True, False) == (True, False)
    assert d.mic_plan(False, False) == (True, False)        # App wollte nicht hören: wie bisher idle
    assert d.mic_plan(False, True) == (False, True)


def test_switch_to_broken_device_does_not_end_engine(ev, monkeypatch):
    monkeypatch.delenv("DOLMETSCHER_MIC_FILE", raising=False)
    monkeypatch.setattr(d, "resolve_mic", lambda m, strict=False: "9")
    monkeypatch.setattr(d, "capture_cmd", lambda **k: ["/nonexistent/ffmpeg-xyz"])
    jobs = queue.Queue()
    m = d.Mic(types.SimpleNamespace(stop_speaking=lambda: None), "0", jobs, idle=False)
    m.on = True
    assert m.switch("USB Mic") is False
    assert jobs.empty()                                      # kein None -> work_loop läuft weiter
    assert any(x == "error" for x, _ in ev) and ("mic", {"on": False}) in ev


def test_initial_start_failure_still_ends_without_idle(ev, monkeypatch):
    monkeypatch.delenv("DOLMETSCHER_MIC_FILE", raising=False)
    monkeypatch.setattr(d, "resolve_mic", lambda m, strict=False: "9")
    monkeypatch.setattr(d, "capture_cmd", lambda **k: ["/nonexistent/ffmpeg-xyz"])
    jobs = queue.Queue()
    m = d.Mic(types.SimpleNamespace(), "0", jobs, idle=False)
    assert m.start() is False
    assert jobs.get_nowait() is None


def test_finish_file_run_writes_subtitles_and_cleans(ev, monkeypatch):
    calls = []
    eng = types.SimpleNamespace(speaker=types.SimpleNamespace(wait_idle=lambda timeout=0: calls.append("idle")))
    monkeypatch.setattr(d, "_write_subtitles", lambda store, path: calls.append(("sub", path)))
    monkeypatch.setattr(d, "cleanup", lambda: calls.append("cleanup"))
    monkeypatch.setattr(d, "flush_output", lambda: calls.append("flush"))
    d.finish_file_run(eng, "x.srt", object())
    assert calls == ["idle", ("sub", "x.srt"), "cleanup", "flush"]


def test_finish_file_run_reports_subtitle_error_and_still_cleans(ev, monkeypatch):
    calls = []
    eng = types.SimpleNamespace(speaker=types.SimpleNamespace(wait_idle=lambda timeout=0: None))

    def boom(store, path):
        raise PermissionError("denied")
    monkeypatch.setattr(d, "_write_subtitles", boom)
    monkeypatch.setattr(d, "cleanup", lambda: calls.append("cleanup"))
    monkeypatch.setattr(d, "flush_output", lambda: calls.append("flush"))
    d.finish_file_run(eng, "/x/y.srt", object())
    assert calls == ["cleanup", "flush"]
    assert [kw["code"] for x, kw in ev if x == "error"] == ["file_failed"]


def test_finish_file_run_without_subtitles(ev, monkeypatch):
    calls = []
    eng = types.SimpleNamespace(speaker=types.SimpleNamespace(wait_idle=lambda timeout=0: None))
    monkeypatch.setattr(d, "cleanup", lambda: calls.append("cleanup"))
    monkeypatch.setattr(d, "flush_output", lambda: None)
    d.finish_file_run(eng)
    assert calls == ["cleanup"] and not ev


def test_cleanup_closes_offline_helper(monkeypatch):
    closed = []
    monkeypatch.setattr(d.OFFLINE_MT, "close", lambda: closed.append(1))
    monkeypatch.setattr(d, "clean_tmp", lambda *a, **k: None)
    monkeypatch.setattr(d, "tts_shutdown", lambda *a, **k: None)
    monkeypatch.setattr(d, "MIC", None)
    monkeypatch.setitem(d._QSTATE, "speaker", None)
    d.cleanup()
    assert closed == [1]


def test_clear_context_drops_echo_memory(ev, monkeypatch):
    d.note_spoken("Where is the hospital please", "en")
    assert d._SPOKEN
    e = d.Engine.__new__(d.Engine)
    e.history = d.collections.deque(maxlen=8)
    monkeypatch.setattr(d, "_cache_clear", lambda: None)
    e.clear_context()
    assert not d._SPOKEN
