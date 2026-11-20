"""Welle 2 (Steuerung, Warteschlange, Mikrofon, Dateimodus): reine Logik ohne Modelle."""
import io
import subprocess
import types

import pytest

import dolmetscher as d


def _eng():
    e = types.SimpleNamespace(translate_dir={"en": True, "th": True}, voices={}, lock="auto", mute=False, rate=0,
                              volume=1.0, paused=False, polite="krub", earcons=False, two_person=True)
    e.stop_speaking = lambda: None
    return e


def test_mic_kill_reaps_after_kill():
    calls = []

    class FF:
        def poll(self):
            return None

        def terminate(self):
            calls.append("terminate")

        def wait(self, t=None):
            calls.append("wait")
            if calls.count("wait") == 1:
                raise subprocess.TimeoutExpired("ff", 2)

        def kill(self):
            calls.append("kill")
    d.Mic._kill(FF())
    assert calls == ["terminate", "wait", "kill", "wait"]


def test_workqueue_utt_count_ignores_pre_partial_jobs():
    q = d.WorkQueue()
    q.put(("pre", "u1", 1, None))
    q.put(("partial", "u1", None))
    q.put(("job", lambda: None))
    assert q.qsize() == 3 and q.utt_count() == 0
    q.put((b"audio", 0.1, 1.0, "pause", 0, 1.0, "u2", 1))
    assert q.utt_count() == 1


def test_backlog_counts_only_utterances(monkeypatch):
    q = d.WorkQueue()
    q.put(("pre", "u1", 1, None))
    q.put(("pre", "u2", 1, None))
    q.put((b"a", 0.1, 1.0, "pause", 0, 1.0, "u3", 1))
    monkeypatch.setitem(d._QSTATE, "stt_q", q)
    assert d._backlog() == 1


@pytest.mark.parametrize("key", ["rate", "volume", "silence", "tts_race", "let_finish", "llm_budget", "beam"])
def test_numeric_control_invalid_is_reported(monkeypatch, key):
    ev = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: ev.append((e, kw)))
    d.apply_control(_eng(), {key: "fast"})
    assert ("control_invalid", {"key": key, "reason": "value"}) in ev


def test_numeric_control_valid_and_none_are_silent(monkeypatch):
    ev = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: ev.append((e, kw)))
    e = _eng()
    d.apply_control(e, {"rate": 10, "volume": None})
    assert e.rate == 10 and not [x for x in ev if x[0] == "control_invalid"]


def test_stop_speaking_runs_before_slow_actions(monkeypatch):
    order = []
    e = _eng()
    e.stop_speaking = lambda: order.append("stop")
    monkeypatch.setattr(d, "load_glossary", lambda g=None: order.append("glossary"))
    d.apply_control(e, {"glossary": "a=b", "stop_speaking": True})
    assert order == ["stop", "glossary"]


def test_stdin_lines_bounded(monkeypatch):
    monkeypatch.setattr(d, "CTRL_LINE_MAX", 10)
    raw = b"x" * 50 + b"\n" + b'{"a":1}\n'

    class In:
        buffer = io.BytesIO(raw)
    monkeypatch.setattr(d.sys, "stdin", In)
    lines = list(d._stdin_lines())
    assert len(lines) == 2 and len(lines[0]) > 10 and lines[1].strip() == '{"a":1}'


def test_stdin_lines_plain_iterable(monkeypatch):
    monkeypatch.setattr(d.sys, "stdin", iter(["a\n", "b\n"]))
    assert list(d._stdin_lines()) == ["a\n", "b\n"]


def test_control_loop_non_object_logged_not_crash(monkeypatch):
    logs = []
    monkeypatch.setattr(d, "log", lambda x: logs.append(x))
    monkeypatch.setattr(d.sys, "stdin", iter(["[1,2]\n", '"x"\n']))
    monkeypatch.setitem(d._BAD_JSON, "t", 0.0)
    monkeypatch.setattr(d.STOP, "set", lambda: None)
    d.control_loop(_eng(), jobs=None)
    import time
    for _ in range(50):
        if any("stdin zu" in str(x) for x in logs):
            break
        time.sleep(0.05)
    assert any(x.get("control") == "kein JSON-Objekt" for x in logs if isinstance(x, dict))


def test_subtitles_db_removed_after_export(tmp_path, monkeypatch):
    monkeypatch.setattr(d, "private_tmp", lambda: str(tmp_path))
    out = tmp_path / "o.srt"
    store = d._subtitle_recorder(str(out))
    assert (tmp_path / "subtitles.sqlite").exists()
    d._write_subtitles(store, str(out))
    assert out.exists() and not (tmp_path / "subtitles.sqlite").exists()


def test_pre_now_thread_safe_and_set_langs_clears(monkeypatch):
    d.pre_mark("u1", 1)
    assert d.pre_stale("u1", 2) and not d.pre_stale("u1", 1)
    d.PRE["u1"] = {}
    d.EARLY_END["u1"] = 1
    e = _eng()
    assert d.set_langs(e, "th", "en")
    assert not d.PRE and not d.EARLY_END and not d.PRE_NOW
    d.set_langs(e, "en", "th")


def test_mean_logprob_weighted_by_duration():
    S = types.SimpleNamespace
    long_good = S(start=0.0, end=9.0, avg_logprob=-0.1)
    short_bad = S(start=9.0, end=9.5, avg_logprob=-1.5)
    w = d.mean_logprob([long_good, short_bad])
    assert -0.2 < w < -0.1 and w > (-0.1 + -1.5) / 2
    assert d.mean_logprob([]) == -9.0
    assert d.mean_logprob([S(avg_logprob=-0.3), S(avg_logprob=-0.5)]) == pytest.approx(-0.4)


def test_stt_token_cap_thai_higher():
    assert d.stt_token_cap(10, "th") > d.stt_token_cap(10, "en")
    assert d.stt_token_cap(1000, "en") == 440 and d.stt_token_cap(1000, "th") == 600
    assert d.stt_token_cap(-1, "en") == 24


@pytest.mark.parametrize("text,ok", [
    ("Where is the station?", True), ("Thank you very much.", True), ("I'm Dr.", False),
    ("See you at 5 p.m.", False), ("Please ask Mr.", False), ("It is over.", True),
    ("I live at number 5 on King St.", False), ("No comma here", False), ("Wow!", True)])
def test_sentence_complete_en(text, ok):
    assert d.sentence_complete_en(text) is ok


def test_record_one_missing_ffmpeg_returns_none(monkeypatch):
    def boom(*a, **kw):
        raise FileNotFoundError("ffmpeg")
    monkeypatch.setattr(d.subprocess, "Popen", boom)
    monkeypatch.setattr(d, "resolve_mic", lambda m, **kw: "0")
    assert d.record_one("0") is None


def test_file_mode_error_chunk_does_not_stop_rest():
    src = open(d.__file__, encoding="utf-8").read()
    assert "abschnitt-fehler" in src and "Engine konnte nicht starten" in src


def test_translate_offline_detected_by_type():
    assert d.is_offline_error(ConnectionError("x"))
