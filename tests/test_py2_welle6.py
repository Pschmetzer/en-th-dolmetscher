"""Welle 6 (Aufräumen, Dateigröße, Hinweise, Warteschlange, Player-Fenster, Versionsgleichheit)."""
import os
import pathlib
import re
import time
import types

import dolmetscher as d

ROOT = pathlib.Path(__file__).resolve().parent.parent


def test_engine_version_matches_pyproject():
    m = re.search(r'^version\s*=\s*"([^"]+)"', (ROOT / "pyproject.toml").read_text(encoding="utf-8"), re.M)
    assert m and m.group(1).startswith(d.ENGINE_VERSION)


def test_clean_stale_tmp_alive_pid_old_dir_is_removed(tmp_path, monkeypatch):
    monkeypatch.setattr(d, "_pid_alive", lambda pid: True)
    monkeypatch.setitem(d._TMPDIR, "path", None)
    old = tmp_path / "dolmetscher_424242_a"
    fresh = tmp_path / "dolmetscher_424243_b"
    for p in (old, fresh):
        p.mkdir()
        (p / "x.wav").write_bytes(b"1")
    ancient = time.time() - d.PID_REUSE_AGE_S - 10
    os.utime(old, (ancient, ancient))
    d.clean_stale_tmp(str(tmp_path))
    assert not old.exists() and fresh.exists()


def test_decode_file_rejects_absurdly_long(monkeypatch):
    monkeypatch.setattr(d, "DECODE_MAX_S", 1)
    monkeypatch.setattr(d, "capture_cmd", lambda **kw: ["x"])
    monkeypatch.setattr(d.subprocess, "run",
                        lambda *a, **k: types.SimpleNamespace(returncode=0, stdout=b"\0\0" * (2 * d.SR), stderr=b""))
    try:
        d.decode_file("a.wav")
    except RuntimeError as e:
        assert "zu lang" in str(e)
    else:
        raise AssertionError("keine Ablehnung")
    monkeypatch.setattr(d.subprocess, "run",
                        lambda *a, **k: types.SimpleNamespace(returncode=0, stdout=b"\0\0" * (d.SR // 2), stderr=b""))
    assert d.decode_file("a.wav").size == d.SR // 2


def test_report_queue_counts_only_utterances(monkeypatch):
    ev = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: ev.append((e, kw)))
    q = d.WorkQueue()
    q.put(("job", lambda: None))
    q.put(("pre", "u", 1, None))
    q.put((b"a", 0.1, 1.0, "pause", 0, 1.0, "u1", 1))
    monkeypatch.setitem(d._QSTATE, "stt_q", q)
    monkeypatch.setitem(d._QSTATE, "speaker", None)
    monkeypatch.setitem(d._QSTATE, "last", None)
    d.report_queue()
    assert ev == [("queue", {"stt": 1, "tts": 0})]


def test_hint_slow_kinds_do_not_block_each_other(monkeypatch):
    ev = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: ev.append(kw))
    monkeypatch.setattr(d, "_HINT_T", {})
    d.hint("slow", what="stt", p90=6.0)
    d.hint("slow", what="tr", p90=5.0)
    d.hint("slow", what="stt", p90=6.0)                      # zweimal dasselbe: gedrosselt
    assert [e["what"] for e in ev] == ["stt", "tr"]


def test_workqueue_jobs_first_and_utterance_cap(monkeypatch):
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    q = d.WorkQueue()
    for i in range(d.WorkQueue.MAX_UTTS + 3):
        q.put((b"a", 0.1, 1.0, "pause", 0, 1.0, f"u{i}", 1))
    assert q.utt_count() == d.WorkQueue.MAX_UTTS
    q.put(("job", "fn"))
    assert q.get()[0] == "job"                                # Aufgabe vor allen Äußerungen
    assert q.get()[6] == "u3"                                 # die drei ältesten wurden verworfen


def test_player_gating_window_and_span_limit():
    p = d.Player()
    now = time.time()
    p.spans = [(now - 10, now - 9)]
    assert not p.gated(now)                                   # lange vorbei
    assert p.gated(now - 9 + d.Player.TAIL / 2)               # im Nachhall
    p.spans = [(now - i - 1, now - i - 0.5) for i in range(40)]
    class Fake:
        def wait(self, timeout=None):
            return 0
    fake = Fake()
    p.procs[fake] = now - 5
    p.wait(fake, 1.0)
    assert len(p.spans) <= 20 and fake not in p.procs


def test_player_stop_marks_interrupted_and_kills_once():
    killed = []
    p = d.Player()
    class Proc:
        def kill(self):
            killed.append(1)
    proc = Proc()
    p.procs[proc] = time.time()
    assert p.stop() is True and p.interrupted is True
    assert p.stop() is False and killed == [1]                # zweiter Stopp tötet nicht nochmal
