"""Runde 25: Verlauf-Recorder – die Warteschlange wird aus mehreren Threads angelegt (emit ruft utt ohne Lock)."""
import threading

import history_store


def test_queue_created_once_under_concurrent_first_use(monkeypatch):
    rec = history_store.Recorder()
    monkeypatch.setattr(history_store.Recorder, "_write", lambda self, *a: None)
    n = 16
    barrier = threading.Barrier(n)
    got = []

    def go():
        barrier.wait()
        got.append(rec._queue())

    ts = [threading.Thread(target=go) for _ in range(n)]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    assert len({id(q) for q in got}) == 1


def test_queue_is_reused_after_creation(monkeypatch):
    rec = history_store.Recorder()
    monkeypatch.setattr(history_store.Recorder, "_write", lambda self, *a: None)
    q = rec._queue()
    assert rec._q is q
    assert rec._queue() is q


def test_utt_concurrent_all_items_reach_one_queue(monkeypatch):
    rec = history_store.Recorder()
    rec.on, rec.async_mode = True, True
    rec.store = object()
    seen = []
    monkeypatch.setattr(history_store.Recorder, "_write", lambda self, kw, now: seen.append(kw["text"]))
    barrier = threading.Barrier(8)

    def go(i):
        barrier.wait()
        for j in range(5):
            rec.utt({"text": f"t{i}-{j}"})

    ts = [threading.Thread(target=go, args=(i,)) for i in range(8)]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    rec.flush()
    assert sorted(seen) == sorted(f"t{i}-{j}" for i in range(8) for j in range(5))
