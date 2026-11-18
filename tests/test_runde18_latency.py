"""Runde 18: Latenz und Ressourcen (Google-Teilstücke, Cache-Schreiben, abgelaufene TTS-Verbindungen). Ohne Netz."""
import threading
import time

import dolmetscher as d


def _closer(monkeypatch):
    closed = []
    monkeypatch.setattr(d, "_ws_close", lambda ws: ws)
    monkeypatch.setattr(d, "_spawn", lambda coro: closed.append(coro))
    return closed


# --- Teilstücke eines langen Satzes gehen gleichzeitig zu Google, nicht eins nach dem anderen -------------------

def test_google_pieces_are_requested_in_parallel_and_keep_order(monkeypatch):
    monkeypatch.setattr(d, "_split_bytes", lambda text, limit=0: ["a", "b", "c", "d"])

    def one(text, src, dst, timeout):
        time.sleep(0.3)
        return "ก" + text
    monkeypatch.setattr(d, "_google_one", one)
    t0 = time.monotonic()
    out = d.google_translate("a b c d", "en", "th")
    assert out == "กaกbกcกd"
    assert time.monotonic() - t0 < 0.8          # nacheinander wären es 1,2 s


def test_google_piece_error_is_raised_not_swallowed(monkeypatch):
    monkeypatch.setattr(d, "_split_bytes", lambda text, limit=0: ["a", "b"])

    def one(text, src, dst, timeout):
        if text == "b":
            raise ValueError("kaputt")
        return "ก"
    monkeypatch.setattr(d, "_google_one", one)
    try:
        d.google_translate("a b", "en", "th")
    except ValueError as e:
        assert "kaputt" in str(e)
    else:
        raise AssertionError("Fehler eines Teilstücks verschluckt")


def test_google_pieces_respect_total_budget(monkeypatch):
    monkeypatch.setattr(d, "_split_bytes", lambda text, limit=0: ["a", "b"])
    monkeypatch.setattr(d, "GOOGLE_TOTAL_S", 0.3)
    release = threading.Event()
    monkeypatch.setattr(d, "_google_one", lambda *a: release.wait(5) or "ก")
    t0 = time.monotonic()
    try:
        d.google_translate("a b", "en", "th")
    except RuntimeError as e:
        assert "Zeitbudget" in str(e)
    else:
        raise AssertionError("kein Zeitbudget")
    finally:
        release.set()
    assert time.monotonic() - t0 < 2.0


# --- Platte schreiben (fsync) hält die Übersetzung nicht auf -----------------------------------------------------

def test_cache_put_writes_to_disk_off_the_translate_thread(monkeypatch):
    where = []
    done = threading.Event()

    def fake_write(path, text):
        where.append(threading.current_thread())
        done.set()
    monkeypatch.setattr(d, "_write_private", fake_write)
    monkeypatch.setitem(d._CACHE_DISK, "on", True)
    monkeypatch.setitem(d._CACHE_DISK, "saved", 0.0)
    d._cache_put(("hello", "en", "th", "mt", "krub"), ("สวัสดี", "google"))
    assert done.wait(2)
    assert where[0] is not threading.current_thread()


# --- abgelaufene Vorrats-Verbindung zur Neural-Stimme wird geschlossen, nicht fallen gelassen --------------------

class _Ws:
    closed = False


def test_stale_pooled_ws_is_closed_when_taken(monkeypatch):
    closed = _closer(monkeypatch)
    fresh, stale = _Ws(), _Ws()
    now = time.time()
    monkeypatch.setitem(d._WS, "pool", [(fresh, now), (stale, now - d.WS_MAX_AGE - 5)])
    assert d._ws_take() is fresh                 # stale wird zuerst gezogen, dann fresh
    assert stale in closed
