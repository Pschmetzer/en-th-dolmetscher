"""Runde 22 (Engine 2): Kindprozess-Umgebung, LLM-Zustand (Lock, no_effort je Modell, Circuit-Breaker half-open,
späte Antwort im Cache), Verlauf race-sicher, Segmenter-deque, Nachliefern gescheiterter Übersetzungen."""
import collections
import concurrent.futures
import inspect
import threading
import time
import types

import pytest

import dolmetscher as d


@pytest.fixture(autouse=True)
def _llm_frisch(monkeypatch):
    for k, v in (("skip_until", 0.0), ("err", None), ("fails", 0), ("probe_t", None), ("billing_told", False)):
        monkeypatch.setitem(d.LLM, k, v)
    monkeypatch.setitem(d.LLM, "no_effort_models", set())
    monkeypatch.setattr(d, "net_state", lambda *a, **k: None)
    monkeypatch.setattr(d, "emit", lambda *a, **k: None)
    monkeypatch.setattr(d, "log", lambda *a, **k: None)


# ----------------------------------------------------------------------------------- Kindprozess-Umgebung

def test_child_env_entfernt_schluessel():
    env = {"ANTHROPIC_API_KEY": "sk-x", "ANTHROPIC_AUTH_TOKEN": "t", "PATH": "/bin", "HOME": "/h"}
    out = d._child_env(env)
    assert "ANTHROPIC_API_KEY" not in out and "ANTHROPIC_AUTH_TOKEN" not in out
    assert out["PATH"] == "/bin" and out["HOME"] == "/h"


def test_child_env_nimmt_os_environ(monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-geheim")
    monkeypatch.setenv("DOLMETSCHER_X", "1")
    out = d._child_env()
    assert "ANTHROPIC_API_KEY" not in out and out["DOLMETSCHER_X"] == "1"


def test_child_env_veraendert_os_environ_nicht(monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-geheim")
    d._child_env()
    import os
    assert os.environ["ANTHROPIC_API_KEY"] == "sk-geheim"


def test_popen_ohne_schluessel(monkeypatch):
    """Player.play-Pfad: das Kind bekommt eine bereinigte Umgebung."""
    seen = {}

    class FakeP:
        def poll(self): return None

    def fake_popen(cmd, **kw):
        seen.update(kw)
        return FakeP()
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-geheim")
    monkeypatch.setattr(d.subprocess, "Popen", fake_popen)
    pl = d.Player.__new__(d.Player)
    pl.lock, pl.procs = threading.RLock(), {}
    pl._standby = None
    monkeypatch.setattr(d, "NULL_AUDIO", False)
    pl.start(["/bin/echo", "x"])
    assert "ANTHROPIC_API_KEY" not in seen["env"]


def test_alle_popen_stellen_setzen_env():
    src = inspect.getsource(d)
    import re
    for m in re.finditer(r"subprocess\.Popen\(", src):
        stueck = src[m.start():m.start() + 400].split("\n\n")[0]
        assert "env=" in stueck or "kw.setdefault(\"env\"" in src[m.start() - 120:m.start()], stueck[:100]


# ----------------------------------------------------------------------------------- no_effort je Modell

def test_no_effort_je_modell(monkeypatch):
    d._set_no_effort("claude-haiku-5-5")
    assert d._no_effort("claude-haiku-5-5")
    assert not d._no_effort("claude-sonnet-5-5")


def test_no_effort_modellwechsel_sendet_effort_wieder(monkeypatch):
    sent = []

    class Err(Exception):
        status_code = 400

    class C:
        class messages:
            @staticmethod
            def create(**kw):
                sent.append(dict(kw))
                if "output_config" in kw and kw["model"] == "claude-haiku-5-5":
                    raise Err("effort")
                return types.SimpleNamespace(content=[types.SimpleNamespace(type="text", text="Hallo")], usage=None,
                                              stop_reason="end_turn")
    monkeypatch.setattr(d, "llm_client", lambda: C)
    monkeypatch.setitem(d.LLM, "model", "claude-haiku-5-5")
    d.claude_translate("hi", "en", "de")
    assert d._no_effort("claude-haiku-5-5")
    monkeypatch.setitem(d.LLM, "model", "claude-sonnet-5-5")
    d.claude_translate("hi", "en", "de")
    assert "output_config" in sent[-1]                       # Sonnet bekommt effort weiterhin


# ----------------------------------------------------------------------------------- Lock / Zustand

def test_llm_failed_parallel_konsistent():
    errs = [RuntimeError("boom")] * 40
    ts = [threading.Thread(target=d._llm_failed, args=(e,)) for e in errs]
    [t.start() for t in ts]
    [t.join() for t in ts]
    assert d.LLM["fails"] == 40 and d.LLM["skip_until"] > time.monotonic()


def test_llm_failed_kurzer_fehler_verkuerzt_lange_pause_nicht():
    d.LLM["skip_until"] = time.monotonic() + 1800
    until = d.LLM["skip_until"]
    d._llm_failed(TimeoutError("t"))
    assert d.LLM["skip_until"] == until


def test_inhaltlicher_fehler_zaehlt_nicht_als_ausfall():
    d._llm_failed(d._BadClaudeAnswer("leer"))
    assert d.LLM["fails"] == 0


def test_llm_ok_setzt_zustand_zurueck():
    d.LLM.update(err="x", fails=3, probe_t=1.0, billing_told=True)
    d._llm_ok()
    assert (d.LLM["err"], d.LLM["fails"], d.LLM["probe_t"], d.LLM["billing_told"]) == (None, 0, None, False)


def test_reset_backoff_setzt_fails_zurueck():
    d.LLM.update(skip_until=time.monotonic() + 99, fails=2)
    d.llm_reset_backoff()
    assert d.LLM["fails"] == 0 and d.LLM["skip_until"] == 0.0


# ----------------------------------------------------------------------------------- half-open

def test_gate_normal_offen():
    assert d._llm_gate() is True


def test_gate_zu_waehrend_pause():
    d.LLM["skip_until"] = time.monotonic() + 30
    assert d._llm_gate() is False


def test_gate_half_open_nur_eine_probe():
    d.LLM.update(fails=1, skip_until=time.monotonic() - 1)
    assert d._llm_gate() is True                         # Probe
    assert d._llm_gate() is False                        # zweite Anfrage gleichzeitig: Google
    assert d._llm_gate() is False


def test_gate_probe_laeuft_ab():
    d.LLM.update(fails=1, skip_until=time.monotonic() - 1)
    assert d._llm_gate() is True
    d.LLM["probe_t"] = time.monotonic() - d.LLM_PROBE_S - 1
    assert d._llm_gate() is True


def test_gate_nach_probe_erfolg_wieder_offen():
    d.LLM.update(fails=2, skip_until=time.monotonic() - 1)
    assert d._llm_gate()
    d._llm_ok()
    assert d._llm_gate() and d._llm_gate()


def test_gate_probe_fehler_schliesst_wieder():
    d.LLM.update(fails=1, skip_until=time.monotonic() - 1)
    assert d._llm_gate()
    d._llm_failed(RuntimeError("x"))
    assert d._llm_gate() is False and d.LLM["fails"] == 2


def test_gate_skip_until_null_hebt_pause_auf():
    d.LLM.update(fails=5, skip_until=0.0)
    assert d._llm_gate() is True


# ----------------------------------------------------------------------------------- späte Antwort -> Cache

def test_llm_late_schreibt_cache():
    fut = concurrent.futures.Future()
    fut.set_result("Hallo spät")
    key = ("zz-late", "en", "de", "llm:x", "")
    d._llm_late(fut, key=key, cache_it=True)
    assert d._cache_get(key) == ("Hallo spät", "claude")


def test_llm_late_ohne_cache_flag_kein_eintrag():
    fut = concurrent.futures.Future()
    fut.set_result("x")
    key = ("zz-late2", "en", "de", "llm:x", "")
    d._llm_late(fut, key=key, cache_it=False)
    assert d._cache_get(key) is None


def test_llm_late_fehler_backoff_kein_cache():
    fut = concurrent.futures.Future()
    fut.set_exception(RuntimeError("zu spät kaputt"))
    key = ("zz-late3", "en", "de", "llm:x", "")
    d._llm_late(fut, key=key, cache_it=True)
    assert d._cache_get(key) is None and d.LLM["fails"] == 1


def test_translate_hedge_spaete_antwort_landet_im_cache(monkeypatch):
    gate = threading.Event()

    def slow(text, src, dst, history, alts, polite):
        gate.wait(5)
        return "Späte Claude-Antwort"
    monkeypatch.setattr(d, "claude_translate", slow)
    monkeypatch.setattr(d, "_check_llm", lambda text, res, dst, src: res)
    monkeypatch.setattr(d, "llm_available", lambda: True)
    monkeypatch.setattr(d, "llm_over_budget", lambda: False)
    monkeypatch.setattr(d, "_mt_chain", lambda text, src, dst, meta, deadline=None: (meta.update(provider="google"), "Google")[1])
    monkeypatch.setitem(d.LLM, "on", True)
    monkeypatch.setitem(d.LLM, "hedge_s", 0.05)
    meta = {}
    txt = "r22 late cache unique sentence"
    out = d._translate(txt, "en", "de", meta=meta)
    assert out == "Google" and meta["provider"] == "google"
    key = d._cache_key(txt, "en", "de", True, "krub")
    gate.set()
    for _ in range(100):
        if d._cache_get(key):
            break
        time.sleep(0.02)
    assert d._cache_get(key) == ("Späte Claude-Antwort", "claude")


# ----------------------------------------------------------------------------------- Verlauf race-sicher

def _eng():
    e = d.Engine.__new__(d.Engine)
    e.history = collections.deque(maxlen=8)
    e.__dict__["_hist_ids"] = {}
    return e


def test_hist_snapshot_ohne_skip():
    e = _eng()
    e.history.extend([("en", "a", "A"), ("en", "b", "B")])
    assert e._hist_snapshot() == (("en", "a", "A"), ("en", "b", "B"))


def test_hist_snapshot_skip_identitaet():
    e = _eng()
    x = ("en", "a", "A")
    e.history.extend([x, ("en", "b", "B")])
    assert e._hist_snapshot(skip=x) == (("en", "b", "B"),)


def test_hist_snapshot_parallel_zu_append():
    e = _eng()
    stop, errs = threading.Event(), []

    def writer():
        i = 0
        while not stop.is_set():
            with d._HIST_LOCK:
                e.history.append(("en", str(i), "x"))
            i += 1

    t = threading.Thread(target=writer)
    t.start()
    try:
        for _ in range(3000):
            try:
                e._hist_snapshot()
            except RuntimeError as ex:
                errs.append(ex)
    finally:
        stop.set()
        t.join()
    assert not errs


def test_forget_parallel_ohne_fehler():
    e = _eng()
    e.recent = collections.OrderedDict()
    for i in range(8):
        ent = ("en", str(i), "x")
        e.history.append(ent)
        e._hist_ids[f"u{i}"] = ent
    errs = []

    def run(i):
        try:
            e._forget(f"u{i}")
        except Exception as ex:           # noqa: BLE001
            errs.append(ex)
    ts = [threading.Thread(target=run, args=(i,)) for i in range(8)]
    [t.start() for t in ts]
    [t.join() for t in ts]
    assert not errs and len(e.history) == 0


def test_forget_entry_schon_verdraengt():
    e = _eng()
    e.__dict__["_hist_ids"]["u1"] = ("en", "alt", "x")
    e._forget("u1")                        # nicht im Fenster: kein Fehler
    assert "u1" not in e._hist_ids


# ----------------------------------------------------------------------------------- Segmenter

def test_segmenter_nutzt_deque():
    src = inspect.getsource(d)
    assert "(pre + [f])[-12:]" not in src
    assert src.count("collections.deque(maxlen=12)") >= 2


def test_deque_maxlen_12_haelt_vorlauf():
    pre = collections.deque(maxlen=12)
    for i in range(30):
        pre.append(i)
    assert list(pre) == list(range(18, 30))


# ----------------------------------------------------------------------------------- Nachliefern

def _flush_eng(monkeypatch, delivered):
    e = d.Engine.__new__(d.Engine)
    e.texts = {}
    monkeypatch.setattr(d.Engine, "deliver", lambda self, uid, lang, text, **kw: delivered.append((uid, lang, text, kw)))
    return e


def _join_retry():
    for t in threading.enumerate():
        if t.name == "retry-failed":
            t.join(2)


def test_gescheiterte_saetze_werden_nachgeliefert(monkeypatch):
    got = []
    e = _flush_eng(monkeypatch, got)
    e._remember_failed("u1", "en", "hello", dict(source="mic", polite="krub"))
    e._flush_failed("u2")
    _join_retry()
    assert got and got[0][0] == "u1" and got[0][3]["speak"] is False and got[0][3]["polite"] == "krub"


def test_nachliefern_nicht_den_aktuellen_satz(monkeypatch):
    got = []
    e = _flush_eng(monkeypatch, got)
    e._remember_failed("u1", "en", "hello", {})
    e._flush_failed("u1")
    _join_retry()
    assert got == []


def test_nachliefern_nur_einmal(monkeypatch):
    got = []
    e = _flush_eng(monkeypatch, got)
    e._remember_failed("u1", "en", "hello", {})
    e._flush_failed("u9")
    e._flush_failed("u9")
    _join_retry()
    assert len(got) == 1


def test_nachliefern_verwirft_alte(monkeypatch):
    got = []
    e = _flush_eng(monkeypatch, got)
    e._remember_failed("u1", "en", "hello", {})
    uid, (t, lang, text, kw) = next(iter(e._failed_tr.items()))
    e._failed_tr[uid] = (t - d.Engine.FAILED_TTL - 5, lang, text, kw)
    e._flush_failed("u9")
    _join_retry()
    assert got == []


def test_nachliefern_begrenzt_anzahl(monkeypatch):
    e = _flush_eng(monkeypatch, [])
    for i in range(10):
        e._remember_failed(f"u{i}", "en", "t", {})
    assert len(e._failed_tr) == d.Engine.FAILED_MAX and "u9" in e._failed_tr and "u0" not in e._failed_tr
