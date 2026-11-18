"""Runde 7, zweiter Teil (Engine): Mikrofon, Ausgabe-Pipe, Verlauf asynchron/WAL, Hilfsprozesse."""
import queue
import sqlite3
import types

import pytest

import dolmetscher as d
import history_store as hs


@pytest.fixture
def ev(monkeypatch):
    events = []
    monkeypatch.setattr(d, "emit", lambda e, **kw: events.append((e, kw)))
    return events


def test_reconnect_wechselt_nie_still_aufs_standardmikrofon(monkeypatch, ev):
    monkeypatch.setattr(d, "list_mics", lambda: [{"index": "1", "name": "Raum"}])
    assert d.resolve_mic("AirPods", strict=True) is None and not ev
    assert d.resolve_mic("AirPods") == "default" and ev[0][1]["code"] == "mic_not_found"
    assert d.resolve_mic("Raum", strict=True) == "1"


def test_start_im_reconnect_wartet_aufs_geraet(monkeypatch, ev):
    m = d.Mic.__new__(d.Mic)
    m.mic, m.idle, m.jobs = "AirPods", True, queue.Queue()
    monkeypatch.setattr(d, "list_mics", lambda: [])
    monkeypatch.delenv("DOLMETSCHER_MIC_FILE", raising=False)
    assert m.start(_retry=True) is False
    assert not [e for e in ev if e[0] == "error"]            # leise: nächster Versuch folgt


def test_net_llm_mit_retry_zeit(monkeypatch, ev):
    monkeypatch.setitem(d.LLM, "skip_until", 0.0)
    monkeypatch.setitem(d.LLM, "billing_told", False)
    monkeypatch.setitem(d.NET, "llm", True)
    d._llm_failed(TimeoutError("x"))
    net = [k for e, k in ev if e == "net"]
    assert net and net[0]["what"] == "llm" and net[0]["ok"] is False and net[0]["retry_in_s"] > 0


def test_ausgabe_pipe_opfert_zuerst_pegelzeilen(monkeypatch):
    q = queue.Queue(maxsize=3)
    monkeypatch.setitem(d._OUT, "q", q)
    monkeypatch.setitem(d._OUT, "dropped", 0)
    for line in ('{"event": "heard", "id": 1}', '{"event": "level", "rms": 0.1}', '{"event": "utt", "id": 1}'):
        q.put_nowait(line)
    d._enqueue("error", '{"event": "error"}')
    assert list(q.queue) == ['{"event": "heard", "id": 1}', '{"event": "utt", "id": 1}', '{"event": "error"}']


def test_ws_oeffnen_pausiert_nach_fehlschlaegen(monkeypatch):
    import asyncio
    calls = []

    async def boom():
        calls.append(1)
        raise OSError("kein Netz")
    monkeypatch.setattr(d, "_ws_open", boom)
    tasks = []
    monkeypatch.setattr(d, "_spawn", lambda coro: tasks.append(asyncio.ensure_future(coro)))
    monkeypatch.setitem(d._WS, "pool", [])
    monkeypatch.setitem(d._WS, "opening", 0)
    monkeypatch.setattr(d, "_WS_OPEN", {"fails": 0, "pause_until": 0.0})
    monkeypatch.setattr(d, "WS_POOL_N", 4)
    async def fill():
        await d._ws_fill()
        await asyncio.gather(*tasks)
    asyncio.run(fill())
    n = len(calls)
    asyncio.run(fill())
    assert len(calls) == n and d._WS_OPEN["pause_until"] > 0          # Pause: keine neuen Versuche


def test_offline_mt_leerlauf_beendet_helfer():
    mt = d.OfflineMT()
    killed = []
    mt.proc = types.SimpleNamespace(kill=lambda: killed.append(1))
    mt.last_used = 100.0
    assert not mt.close_if_idle(now=150.0) and mt.proc is not None
    assert mt.close_if_idle(now=100.0 + mt.IDLE_CLOSE_S + 1) and killed and mt.proc is None


def test_dateimodus_ohne_ueberspringen_im_quelltext():
    src = open(d.__file__, encoding="utf-8").read()
    assert 'CATCH_UP["mode"] = "off"' in src and "wait_idle(timeout=6 * 3600)" in src


def test_verlauf_async_schreibt_ausserhalb_und_flush(tmp_path):
    rec = hs.Recorder()
    rec.store, rec.on, rec.async_mode = hs.Store(str(tmp_path / "h.sqlite")), True, True
    for i in range(20):
        rec.utt({"text": f"t{i}", "out": "x", "translated": True, "lang": "en", "id": f"u{i}"})
    rec.flush()
    assert len(rec.store.rows()) == 20
    rec.enable(False)
    rec.utt({"text": "nach aus"})
    rec.flush()
    assert len(rec.store.rows()) == 20


def test_verlauf_wal_und_checkpoint_nach_loeschen(tmp_path):
    st = hs.Store(str(tmp_path / "h.sqlite"))
    assert st.db.execute("PRAGMA journal_mode").fetchone()[0] == "wal"
    st.add("geheimer text", "x", lang="en", session="s")
    st.clear()
    st.close()
    wal = tmp_path / "h.sqlite-wal"
    assert not wal.exists() or wal.stat().st_size == 0
    assert b"geheimer text" not in (tmp_path / "h.sqlite").read_bytes()
    assert sqlite3.connect(str(tmp_path / "h.sqlite")).execute("select count(*) from utt").fetchone()[0] == 0
